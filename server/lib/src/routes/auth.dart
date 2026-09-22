import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../db.dart';
import '../http.dart';

void registerAuthRoutes(
  Router router, {
  required AppDatabase db,
  required Auth auth,
}) {
  router.post('/auth/register', (Request request) async {
    final body = await _readJsonObject(request);
    final email = _normalizeEmail(body['email']);
    final password = body['password'];
    if (email == null || password is! String || password.length < 8) {
      throw ApiException(
        400,
        errValidation,
        'email invalid or password shorter than 8 characters',
      );
    }
    final existing = await (db.select(
      db.users,
    )..where((t) => t.email.equals(email))).getSingleOrNull();
    if (existing != null) {
      throw ApiException(409, errConflict, 'email already registered');
    }
    final userId = newId();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: userId,
            email: email,
            passwordHash: auth.hashPassword(password),
            createdAt: DateTime.now().toUtc(),
          ),
        );
    final tokens = await auth.issueTokens(userId);
    return jsonResponse(201, {
      'userId': userId,
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'tokenType': 'Bearer',
      'expiresIn': auth.config.accessTtl.inSeconds,
    });
  });

  router.post('/auth/login', (Request request) async {
    final body = await _readJsonObject(request);
    final email = _normalizeEmail(body['email']);
    final password = body['password'];
    if (email == null || password is! String) {
      throw ApiException(400, errValidation, 'email or password missing');
    }
    final user = await (db.select(
      db.users,
    )..where((t) => t.email.equals(email))).getSingleOrNull();
    if (user == null) {
      auth.dummyVerify(password);
      throw ApiException(401, errUnauthorized, 'invalid email or password');
    }
    if (!auth.verifyPassword(password, user.passwordHash)) {
      throw ApiException(401, errUnauthorized, 'invalid email or password');
    }
    final tokens = await auth.issueTokens(user.id);
    return jsonResponse(200, {
      'userId': user.id,
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'tokenType': 'Bearer',
      'expiresIn': auth.config.accessTtl.inSeconds,
    });
  });

  router.post('/auth/refresh', (Request request) async {
    final body = await _readJsonObject(request);
    final token = body['refreshToken'];
    if (token is! String || token.isEmpty) {
      throw ApiException(400, errValidation, 'refreshToken missing');
    }
    final now = DateTime.now().toUtc();
    final row =
        await (db.select(db.refreshTokens)
              ..where((t) => t.tokenHash.equals(auth.hashRefreshToken(token))))
            .getSingleOrNull();
    if (row == null) {
      throw ApiException(401, errUnauthorized, 'invalid refresh token');
    }
    if (row.revokedAt != null) {
      // Replaying an already-rotated token signals theft: revoke the whole
      // family so the legitimate successor chain dies with the stolen copy.
      await (db.update(db.refreshTokens)
            ..where((t) => t.familyId.equals(row.familyId)))
          .write(RefreshTokensCompanion(revokedAt: Value(now)));
      throw ApiException(401, errUnauthorized, 'invalid refresh token');
    }
    if (row.expiresAt.isBefore(now)) {
      await (db.update(db.refreshTokens)..where((t) => t.id.equals(row.id)))
          .write(RefreshTokensCompanion(revokedAt: Value(now)));
      throw ApiException(401, errUnauthorized, 'refresh token expired');
    }
    final user = await (db.select(
      db.users,
    )..where((t) => t.id.equals(row.userId))).getSingleOrNull();
    if (user == null) {
      await (db.update(db.refreshTokens)..where((t) => t.id.equals(row.id)))
          .write(RefreshTokensCompanion(revokedAt: Value(now)));
      throw ApiException(401, errUnauthorized, 'invalid refresh token');
    }
    final tokens = await db.transaction(() async {
      await (db.update(db.refreshTokens)..where((t) => t.id.equals(row.id)))
          .write(RefreshTokensCompanion(revokedAt: Value(now)));
      return auth.issueTokens(row.userId, familyId: row.familyId);
    });
    return jsonResponse(200, {
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'tokenType': 'Bearer',
      'expiresIn': auth.config.accessTtl.inSeconds,
    });
  });

  router.get(
    '/auth/me',
    auth.requireAuth((request, context) async {
      return jsonResponse(200, {
        'userId': context.userId,
        'deviceId': context.deviceId,
      });
    }),
  );
}

Future<Map<String, dynamic>> _readJsonObject(Request request) async {
  try {
    final decoded = jsonDecode(await request.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(400, errValidation, 'body must be a JSON object');
    }
    return decoded;
  } on ApiException {
    rethrow;
  } on FormatException {
    throw ApiException(400, errValidation, 'invalid JSON body');
  }
}

String? _normalizeEmail(Object? raw) {
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
