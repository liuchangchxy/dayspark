import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2_web/argon2_web.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shelf/shelf.dart';

import 'config.dart';
import 'db.dart';
import 'http.dart';

final Random _secureRandom = Random.secure();

Uint8List randomBytes(int length) {
  return Uint8List.fromList(
    List<int>.generate(length, (_) => _secureRandom.nextInt(256)),
  );
}

String newId([int length = 16]) => base64Url.encode(randomBytes(length));

class AuthContext {
  const AuthContext({required this.userId, this.deviceId});

  final String userId;
  final String? deviceId;
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

class AccessClaims {
  const AccessClaims({required this.userId, this.scope, this.track});

  final String userId;
  final String? scope;
  final String? track;
}

class Auth {
  Auth(this.config, this.db);

  static const int _memoryKiB = 32768;
  static const int _iterations = 3;
  static const int _lanes = 1;
  static const int _version = 0x13;
  static const int _keyLength = 32;

  final Config config;
  final AppDatabase db;

  String? _dummyHash;

  String hashPassword(String password) {
    final salt = randomBytes(16);
    final key = _derive(
      password,
      salt,
      memory: _memoryKiB,
      iterations: _iterations,
      lanes: _lanes,
    );
    return 'argon2id\$v=$_version\$m=$_memoryKiB,t=$_iterations,p=$_lanes\$'
        '${base64Url.encode(salt)}\$${base64Url.encode(key)}';
  }

  bool verifyPassword(String password, String stored) {
    try {
      final parts = stored.split(r'$');
      if (parts.length != 5 || parts[0] != 'argon2id') {
        return false;
      }
      final version = int.parse(parts[1].substring(2));
      var memory = 0;
      var iterations = 0;
      var lanes = 0;
      for (final pair in parts[2].split(',')) {
        final kv = pair.split('=');
        switch (kv[0]) {
          case 'm':
            memory = int.parse(kv[1]);
          case 't':
            iterations = int.parse(kv[1]);
          case 'p':
            lanes = int.parse(kv[1]);
        }
      }
      final salt = base64Url.decode(parts[3]);
      final expected = base64Url.decode(parts[4]);
      final actual = _derive(
        password,
        salt,
        memory: memory,
        iterations: iterations,
        lanes: lanes,
        version: version,
      );
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      // Malformed stored hash must fail closed as "wrong password", never
      // leak parsing details to the caller.
      return false;
    }
  }

  // Unknown-email logins still burn one argon2 verification so response
  // timing does not reveal whether an account exists.
  void dummyVerify(String password) {
    _dummyHash ??= hashPassword(newId());
    verifyPassword(password, _dummyHash!);
  }

  String issueAccessToken(
    String userId, {
    String? scope,
    String? track,
  }) {
    final jwt = JWT({
      'sub': userId,
      if (scope != null) 'scope': scope,
      if (track != null) 'track': track,
    });
    return jwt.sign(SecretKey(config.jwtSecret), expiresIn: config.accessTtl);
  }

  AccessClaims? verifyAccessTokenClaims(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(config.jwtSecret));
      final payload = jwt.payload;
      if (payload is! Map) {
        return null;
      }
      final sub = payload['sub'];
      if (sub is! String || sub.isEmpty) {
        return null;
      }
      final scope = payload['scope'];
      final track = payload['track'];
      return AccessClaims(
        userId: sub,
        scope: scope is String ? scope : null,
        track: track is String ? track : null,
      );
    } on JWTException {
      return null;
    }
  }

  String? verifyAccessToken(String token) =>
      verifyAccessTokenClaims(token)?.userId;

  String hashRefreshToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  // Every issued token carries a scope claim: /auth login rows mint the
  // full MCP scope (CLI/device session track), OAuth rows mint exactly the
  // consented subset. `track` derives from the client binding so a token
  // can never claim the wrong track.
  Future<TokenPair> issueTokens(
    String userId, {
    required String scope,
    String? familyId,
    String? clientId,
  }) async {
    final accessToken = issueAccessToken(
      userId,
      scope: scope,
      track: clientId != null ? 'oauth' : 'cli',
    );
    final refreshToken = newId(32);
    await db
        .into(db.refreshTokens)
        .insert(
          RefreshTokensCompanion.insert(
            id: newId(),
            userId: userId,
            tokenHash: hashRefreshToken(refreshToken),
            familyId: familyId ?? newId(),
            clientId: Value(clientId),
            scope: Value(scope),
            expiresAt: DateTime.now().toUtc().add(config.refreshTtl),
          ),
        );
    return TokenPair(accessToken: accessToken, refreshToken: refreshToken);
  }

  Handler requireAuth(
    FutureOr<Response> Function(Request request, AuthContext auth) inner,
  ) {
    return (Request request) {
      final header = request.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) {
        return jsonError(401, errUnauthorized, 'missing bearer token');
      }
      final claims = verifyAccessTokenClaims(header.substring(7));
      if (claims == null) {
        return jsonError(
          401,
          errUnauthorized,
          'invalid or expired access token',
        );
      }
      // Two-track separation: OAuth tokens are scoped MCP credentials and
      // must not reach the sync API (an mcp:read grant would otherwise be a
      // full write credential via /sync/push). Login tokens own the account.
      if (claims.track == 'oauth') {
        return jsonError(
          401,
          errUnauthorized,
          'OAuth access tokens are valid on /mcp only — '
              'sign in via /auth/login for the sync API',
        );
      }
      // deviceId stays unbound until device register (Task 5) issues it.
      final deviceId = request.headers['x-device-id'];
      return inner(
        request,
        AuthContext(userId: claims.userId, deviceId: deviceId),
      );
    };
  }

  Uint8List _derive(
    String password,
    Uint8List salt, {
    required int memory,
    required int iterations,
    required int lanes,
    int version = _version,
  }) {
    final generator = Argon2BytesGenerator();
    generator.init(
      Argon2Parameters(
        Argon2Parameters.argon2id,
        salt,
        desiredKeyLength: _keyLength,
        version: version,
        iterations: iterations,
        memory: memory,
        lanes: lanes,
      ),
    );
    final out = Uint8List(_keyLength);
    generator.generateBytes(Uint8List.fromList(utf8.encode(password)), out);
    return out;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

// Shared by the CLI refresh route and the OAuth refresh grant: one rotation
// family dies together so a replayed token can never leave a live successor.
Future<void> revokeRefreshFamily(
  AppDatabase db,
  String familyId,
  DateTime now,
) {
  return (db.update(db.refreshTokens)..where((t) => t.familyId.equals(familyId)))
      .write(RefreshTokensCompanion(revokedAt: Value(now)));
}

String? normalizeEmail(Object? raw) {
  if (raw is! String) {
    return null;
  }
  // Lowercase so the unique index is case-insensitive for real-world emails.
  final email = raw.trim().toLowerCase();
  if (email.isEmpty || email.length > 254 || !email.contains('@')) {
    return null;
  }
  return email;
}
