import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../db.dart';
import '../http.dart';
import '../mcp/schemas.dart';
import 'consent.dart';

// OAuth 2.1 authorization server for the MCP resource: RFC 8414 / RFC 9728
// discovery, RFC 7591 dynamic registration, PKCE-S256-only authorize +
// token (authorization_code / refresh_token), RFC 7009 revocation.
//
// Hard rules: redirect_uri exact string match against registration, PKCE
// S256 mandatory (plain and missing rejected), codes single-use with a 10
// minute TTL bound to (client, redirect_uri, challenge, scopes, user),
// consent form carries a one-time CSRF token, client_secret hashed at rest
// with the same argon2 path as passwords. OAuth endpoints speak RFC 6749
// error JSON ({"error": "..."}), not the sync envelope.
//
// Two tracks (documented): Agents/connectors go through this flow and get
// scope-limited track='oauth' tokens valid on /mcp only; CLI/devices use
// /auth/login session tokens (full account, track='cli').

const Duration oauthCodeTtl = Duration(minutes: 10);

const String _authMethodBasic = 'client_secret_basic';
const String _authMethodNone = 'none';

class OAuthError implements Exception {
  OAuthError(this.status, this.error, [this.description]);

  final int status;
  final String error;
  final String? description;

  Response toResponse() {
    final response = jsonResponse(status, <String, Object?>{
      'error': error,
      if (description != null) 'error_description': description,
    });
    return status == 401
        ? response.change(
            headers: {
              'www-authenticate': 'Basic realm="oauth", charset="UTF-8"',
            },
          )
        : response;
  }
}

Future<Response> _guard(Future<Response> Function() run) async {
  try {
    return await run();
  } on OAuthError catch (e) {
    return e.toResponse();
  }
}

Response _page(int status, String message) => Response(
  status,
  body: renderOAuthErrorPage(message),
  headers: {'content-type': 'text/html; charset=utf-8'},
);

Response _html(int status, String body) => Response(
  status,
  body: body,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

Response _redirect(String location, {required int status}) =>
    Response(status, headers: {'location': location});

Response _redirectError(
  String redirectUri,
  String error,
  String description,
  String? state,
) {
  final base = Uri.parse(redirectUri);
  final params = <String, String>{
    ...base.queryParameters,
    'error': error,
    'error_description': description,
    if (state != null && state.isNotEmpty) 'state': state,
  };
  return _redirect(base.replace(queryParameters: params).toString(), status: 302);
}

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

// Public so tests can pin the RFC 7636 Appendix B vector against this exact
// construction — a regression here would silently break every real connector.
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

bool _verifierFormatOk(String verifier) =>
    RegExp(r'^[A-Za-z0-9\-._~]{43,128}$').hasMatch(verifier);

bool _verifyPkce(String verifier, String challenge) =>
    _verifierFormatOk(verifier) && pkceChallenge(verifier) == challenge;

bool _validRedirectUri(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) {
    return false;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return false;
  }
  return !uri.hasFragment;
}

List<String> _parseScopes(String? raw) {
  final text = raw ?? mcpScopeFull;
  final scopes =
      text.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (scopes.isEmpty) {
    throw OAuthError(400, 'invalid_scope', 'scope must not be empty');
  }
  final unknown = scopes.where((s) => !mcpSupportedScopes.contains(s)).toList();
  if (unknown.isNotEmpty) {
    throw OAuthError(
      400,
      'invalid_scope',
      'unsupported scope: ${unknown.join(', ')} — '
          'supported: ${mcpSupportedScopes.join(' ')}',
    );
  }
  return scopes;
}

List<String> _redirectList(OauthClient client) =>
    (jsonDecode(client.redirectUris) as List).cast<String>();

Future<Map<String, Object?>> _readBody(Request request) async {
  final contentType = request.headers['content-type'] ?? '';
  final String raw;
  try {
    raw = utf8.decode(await readBodyBytes(request));
  } on FormatException {
    throw OAuthError(400, 'invalid_request', 'malformed request body');
  }
  try {
    if (contentType.contains('application/json')) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('expected a JSON object');
      }
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    if (contentType.contains('application/x-www-form-urlencoded') ||
        contentType.isEmpty) {
      return Uri.splitQueryString(raw);
    }
  } on FormatException {
    throw OAuthError(400, 'invalid_request', 'malformed request body');
  }
  throw OAuthError(
    400,
    'invalid_request',
    'content-type must be application/x-www-form-urlencoded '
        'or application/json',
  );
}

Future<OauthClient> _clientById(AppDatabase db, String clientId) async {
  final client = await (db.select(db.oauthClients)
        ..where((t) => t.id.equals(clientId)))
      .getSingleOrNull();
  if (client == null) {
    throw OAuthError(401, 'invalid_client', 'unknown client_id');
  }
  return client;
}

Future<OauthClient> _authenticateClient(
  AppDatabase db,
  Auth auth,
  Request request,
  Map<String, Object?> body,
) async {
  final header = request.headers['authorization'];
  if (header != null && header.startsWith('Basic ')) {
    final String decoded;
    try {
      final stripped = header.substring(6).replaceAll(RegExp(r'\s'), '');
      decoded = utf8.decode(base64.decode(stripped));
    } on FormatException {
      throw OAuthError(401, 'invalid_client', 'malformed Basic credentials');
    }
    final separator = decoded.indexOf(':');
    if (separator < 0) {
      throw OAuthError(401, 'invalid_client', 'malformed Basic credentials');
    }
    final String clientId;
    final String secret;
    try {
      clientId = Uri.decodeQueryComponent(decoded.substring(0, separator));
      secret = Uri.decodeQueryComponent(decoded.substring(separator + 1));
    } on ArgumentError {
      throw OAuthError(401, 'invalid_client', 'malformed Basic credentials');
    }
    final client = await _clientById(db, clientId);
    if (client.authMethod != _authMethodBasic ||
        client.clientSecretHash == null ||
        !auth.verifyPassword(secret, client.clientSecretHash!)) {
      throw OAuthError(401, 'invalid_client', 'client authentication failed');
    }
    return client;
  }

  final clientId = body['client_id'];
  if (clientId is! String || clientId.isEmpty) {
    throw OAuthError(401, 'invalid_client', 'client authentication required');
  }
  final client = await _clientById(db, clientId);
  if (client.authMethod != _authMethodNone) {
    throw OAuthError(
      401,
      'invalid_client',
      'confidential clients must authenticate with client_secret_basic',
    );
  }
  return client;
}

Map<String, Object?> _tokenResponse(
  TokenPair tokens,
  String scope,
  Auth auth,
) => <String, Object?>{
  'access_token': tokens.accessToken,
  'token_type': 'Bearer',
  'expires_in': auth.config.accessTtl.inSeconds,
  'refresh_token': tokens.refreshToken,
  'scope': scope,
};

Future<Response> _authorizationCodeGrant(
  AppDatabase db,
  Auth auth,
  Request request,
  Map<String, Object?> body,
) async {
  final client = await _authenticateClient(db, auth, request, body);
  final code = body['code'];
  final redirectUri = body['redirect_uri'];
  final verifier = body['code_verifier'];
  if (code is! String || code.isEmpty) {
    throw OAuthError(400, 'invalid_request', 'code is required');
  }
  if (redirectUri is! String || redirectUri.isEmpty) {
    throw OAuthError(400, 'invalid_request', 'redirect_uri is required');
  }
  if (verifier is! String || verifier.isEmpty) {
    throw OAuthError(400, 'invalid_request', 'code_verifier is required (PKCE S256)');
  }

  final codeHash = _sha256Hex(code);
  final row = await (db.select(db.oauthCodes)
        ..where((t) => t.codeHash.equals(codeHash)))
      .getSingleOrNull();
  final now = DateTime.now().toUtc();
  if (row == null) {
    throw OAuthError(400, 'invalid_grant', 'authorization code not found');
  }
  if (row.usedAt != null) {
    throw OAuthError(400, 'invalid_grant', 'authorization code already used');
  }
  if (row.expiresAt.isBefore(now)) {
    throw OAuthError(400, 'invalid_grant', 'authorization code expired');
  }
  if (row.clientId != client.id) {
    throw OAuthError(400, 'invalid_grant', 'code was issued to another client');
  }
  if (row.redirectUri != redirectUri) {
    throw OAuthError(400, 'invalid_grant', 'redirect_uri mismatch');
  }
  if (!_verifyPkce(verifier, row.codeChallenge)) {
    throw OAuthError(400, 'invalid_grant', 'PKCE verification failed');
  }

  // Atomic single-use: exactly one redemption can flip used_at, so a
  // parallel replay loses here even if both passed every check above.
  final consumed =
      await (db.update(db.oauthCodes)
            ..where((t) => t.codeHash.equals(codeHash) & t.usedAt.isNull()))
          .write(OauthCodesCompanion(usedAt: Value(now)));
  if (consumed == 0) {
    throw OAuthError(400, 'invalid_grant', 'authorization code already used');
  }

  final tokens = await auth.issueTokens(
    row.userId,
    scope: row.scopes,
    clientId: row.clientId,
  );
  return jsonResponse(200, _tokenResponse(tokens, row.scopes, auth));
}

Future<Response> _refreshGrant(
  AppDatabase db,
  Auth auth,
  Request request,
  Map<String, Object?> body,
) async {
  final client = await _authenticateClient(db, auth, request, body);
  final token = body['refresh_token'];
  if (token is! String || token.isEmpty) {
    throw OAuthError(400, 'invalid_request', 'refresh_token is required');
  }
  final row = await (db.select(db.refreshTokens)
        ..where((t) => t.tokenHash.equals(auth.hashRefreshToken(token))))
      .getSingleOrNull();
  final now = DateTime.now().toUtc();
  if (row == null) {
    throw OAuthError(400, 'invalid_grant', 'invalid refresh token');
  }
  // OAuth refresh rows are bound to their registering client; CLI-session
  // rows (clientId null) must not be redeemable here either.
  if (row.clientId != client.id) {
    throw OAuthError(400, 'invalid_grant', 'refresh token belongs to another client');
  }
  if (row.revokedAt != null) {
    await revokeRefreshFamily(db, row.familyId, now);
    throw OAuthError(400, 'invalid_grant', 'refresh token revoked');
  }
  if (row.expiresAt.isBefore(now)) {
    await (db.update(db.refreshTokens)..where((t) => t.id.equals(row.id)))
        .write(RefreshTokensCompanion(revokedAt: Value(now)));
    throw OAuthError(400, 'invalid_grant', 'refresh token expired');
  }
  if (row.scope == null || row.scope!.isEmpty) {
    throw OAuthError(400, 'invalid_grant', 'refresh token carries no scope');
  }
  final user = await (db.select(
    db.users,
  )..where((t) => t.id.equals(row.userId))).getSingleOrNull();
  if (user == null) {
    await (db.update(db.refreshTokens)..where((t) => t.id.equals(row.id)))
        .write(RefreshTokensCompanion(revokedAt: Value(now)));
    throw OAuthError(400, 'invalid_grant', 'invalid refresh token');
  }

  final tokens = await db.transaction(() async {
    // Same TOCTOU arbiter as the CLI refresh route (T2): revoked_at IS NULL
    // makes this UPDATE decide the rotation race; the loser revokes the
    // family after commit.
    final affected =
        await (db.update(db.refreshTokens)
              ..where((t) => t.id.equals(row.id) & t.revokedAt.isNull()))
            .write(RefreshTokensCompanion(revokedAt: Value(now)));
    if (affected == 0) {
      return null;
    }
    return auth.issueTokens(
      row.userId,
      scope: row.scope!,
      familyId: row.familyId,
      clientId: row.clientId,
    );
  });
  if (tokens == null) {
    await revokeRefreshFamily(db, row.familyId, now);
    throw OAuthError(400, 'invalid_grant', 'refresh token already used');
  }
  return jsonResponse(200, _tokenResponse(tokens, row.scope!, auth));
}

Future<Response> _tokenEndpoint(
  AppDatabase db,
  Auth auth,
  Request request,
) async {
  final body = await _readBody(request);
  switch (body['grant_type']) {
    case 'authorization_code':
      return _authorizationCodeGrant(db, auth, request, body);
    case 'refresh_token':
      return _refreshGrant(db, auth, request, body);
    default:
      throw OAuthError(
        400,
        'unsupported_grant_type',
        'supported grants: authorization_code, refresh_token',
      );
  }
}

Future<Response> _registerClient(
  AppDatabase db,
  Auth auth,
  Request request,
) async {
  final body = await _readBody(request);
  final clientName = body['client_name'];
  if (clientName is! String || clientName.trim().isEmpty) {
    throw OAuthError(400, 'invalid_client_metadata', 'client_name is required');
  }
  final rawUris = body['redirect_uris'];
  if (rawUris is! List ||
      rawUris.isEmpty ||
      rawUris.any((uri) => uri is! String || !_validRedirectUri(uri))) {
    throw OAuthError(
      400,
      'invalid_client_metadata',
      'redirect_uris must be a non-empty array of absolute http(s) URIs '
          'without fragments',
    );
  }
  final rawMethod = body['token_endpoint_auth_method'];
  if (rawMethod != null && rawMethod is! String) {
    throw OAuthError(
      400,
      'invalid_client_metadata',
      'token_endpoint_auth_method must be client_secret_basic or none',
    );
  }
  final method = rawMethod as String? ?? _authMethodBasic;
  if (method != _authMethodBasic && method != _authMethodNone) {
    throw OAuthError(
      400,
      'invalid_client_metadata',
      'token_endpoint_auth_method must be client_secret_basic or none',
    );
  }

  final clientId = newId();
  final clientSecret = method == _authMethodBasic ? newId(32) : null;
  final now = DateTime.now().toUtc();
  await db
      .into(db.oauthClients)
      .insert(
        OauthClientsCompanion.insert(
          id: clientId,
          clientSecretHash: Value(
            clientSecret == null ? null : auth.hashPassword(clientSecret),
          ),
          clientName: clientName.trim(),
          redirectUris: jsonEncode(rawUris),
          authMethod: method,
          createdAt: now,
        ),
      );
  return jsonResponse(201, <String, Object?>{
    'client_id': clientId,
    if (clientSecret != null) 'client_secret': clientSecret,
    'client_name': clientName.trim(),
    'redirect_uris': rawUris,
    'token_endpoint_auth_method': method,
    'grant_types': ['authorization_code', 'refresh_token'],
    'response_types': ['code'],
    'issued_at': now.millisecondsSinceEpoch ~/ 1000,
  });
}

void registerOauthRoutes(
  Router router, {
  required AppDatabase db,
  required Auth auth,
}) {
  final formTokens = OneTimeFormTokens();

  Response consent({
    required OauthClient client,
    required List<String> scopes,
    required Map<String, String> hidden,
    String email = '',
    String? error,
    int status = 200,
  }) {
    return _html(
      status,
      renderConsentPage(
        clientName: client.clientName,
        scopes: scopes,
        hidden: {...hidden, 'csrf': formTokens.issue()},
        email: email,
        error: error,
      ),
    );
  }

  router.get('/.well-known/oauth-authorization-server', (Request request) {
    final origin = requestOrigin(request);
    return jsonResponse(200, <String, Object?>{
      'issuer': origin,
      'authorization_endpoint': '$origin/oauth/authorize',
      'token_endpoint': '$origin/oauth/token',
      'registration_endpoint': '$origin/oauth/register',
      'revocation_endpoint': '$origin/oauth/revoke',
      'response_types_supported': ['code'],
      'response_modes_supported': ['query'],
      'grant_types_supported': ['authorization_code', 'refresh_token'],
      'code_challenge_methods_supported': ['S256'],
      'token_endpoint_auth_methods_supported': [
        _authMethodBasic,
        _authMethodNone,
      ],
      'scopes_supported': mcpSupportedScopes,
      'subject_types_supported': ['public'],
    });
  });

  router.get('/.well-known/oauth-protected-resource', (Request request) {
    final origin = requestOrigin(request);
    return jsonResponse(200, <String, Object?>{
      'resource': '$origin/mcp',
      'authorization_servers': [origin],
      'bearer_methods_supported': ['header'],
      'scopes_supported': mcpSupportedScopes,
    });
  });

  router.post(
    '/oauth/register',
    (Request request) => _guard(() => _registerClient(db, auth, request)),
  );

  router.get('/oauth/authorize', (Request request) async {
    final params = request.url.queryParameters;
    final clientId = params['client_id'];
    if (clientId == null || clientId.isEmpty) {
      return _page(400, 'client_id is required');
    }
    final client = await (db.select(db.oauthClients)
          ..where((t) => t.id.equals(clientId)))
        .getSingleOrNull();
    if (client == null) {
      return _page(400, 'unknown client_id');
    }
    final redirectUri = params['redirect_uri'];
    if (redirectUri == null || !_redirectList(client).contains(redirectUri)) {
      return _page(
        400,
        'redirect_uri does not exactly match a registered redirect URI',
      );
    }

    // From here the redirect target is trusted: OAuth protocol errors go
    // back with a redirect (never carrying a code) instead of a page.
    final state = params['state'];
    if (params['response_type'] != 'code') {
      return _redirectError(
        redirectUri,
        'unsupported_response_type',
        'only response_type=code is supported',
        state,
      );
    }
    final challenge = params['code_challenge'];
    final method = params['code_challenge_method'];
    if (challenge == null || challenge.isEmpty || method != 'S256') {
      return _redirectError(
        redirectUri,
        'invalid_request',
        'PKCE is required: code_challenge_method must be S256 '
            '(plain and missing are rejected)',
        state,
      );
    }
    final List<String> scopes;
    try {
      scopes = _parseScopes(params['scope']);
    } on OAuthError catch (e) {
      return _redirectError(
        redirectUri,
        e.error,
        e.description ?? 'invalid scope',
        state,
      );
    }

    return consent(
      client: client,
      scopes: scopes,
      hidden: <String, String>{
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        if (state != null) 'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );
  });

  router.post('/oauth/authorize', (Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.contains('application/x-www-form-urlencoded')) {
      return _page(400, 'expected an application/x-www-form-urlencoded body');
    }
    final Map<String, String> form;
    try {
      form = Uri.splitQueryString(utf8.decode(await readBodyBytes(request)));
    } on FormatException {
      return _page(400, 'malformed form body');
    }
    if (!formTokens.consume(form['csrf'])) {
      return _page(
        400,
        'missing, invalid or already-used form token — '
            'reload the authorization page',
      );
    }

    // Re-validate every OAuth parameter: hidden fields are untrusted.
    final clientId = form['client_id'];
    if (clientId == null || clientId.isEmpty) {
      return _page(400, 'client_id is required');
    }
    final client = await (db.select(db.oauthClients)
          ..where((t) => t.id.equals(clientId)))
        .getSingleOrNull();
    if (client == null) {
      return _page(400, 'unknown client_id');
    }
    final redirectUri = form['redirect_uri'];
    if (redirectUri == null || !_redirectList(client).contains(redirectUri)) {
      return _page(
        400,
        'redirect_uri does not exactly match a registered redirect URI',
      );
    }
    if (form['response_type'] != 'code') {
      return _page(400, 'only response_type=code is supported');
    }
    final challenge = form['code_challenge'];
    final method = form['code_challenge_method'];
    if (challenge == null || challenge.isEmpty || method != 'S256') {
      return _page(400, 'PKCE is required: code_challenge_method must be S256');
    }
    final List<String> scopes;
    try {
      scopes = _parseScopes(form['scope']);
    } on OAuthError catch (e) {
      return _page(400, e.description ?? 'invalid scope');
    }
    final hidden = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      if (form['state'] != null && form['state']!.isNotEmpty)
        'state': form['state']!,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    };

    final email = normalizeEmail(form['email']);
    final password = form['password'];
    if (email == null || password is! String) {
      return consent(
        client: client,
        scopes: scopes,
        hidden: hidden,
        error: 'Email and password are required / 需要邮箱与密码',
        status: 400,
      );
    }
    final user = await (db.select(
      db.users,
    )..where((t) => t.email.equals(email))).getSingleOrNull();
    if (user == null) {
      auth.dummyVerify(password);
      return consent(
        client: client,
        scopes: scopes,
        hidden: hidden,
        email: email,
        error: 'Invalid email or password / 邮箱或密码错误',
        status: 400,
      );
    }
    if (!auth.verifyPassword(password, user.passwordHash)) {
      return consent(
        client: client,
        scopes: scopes,
        hidden: hidden,
        email: email,
        error: 'Invalid email or password / 邮箱或密码错误',
        status: 400,
      );
    }

    final code = newId(32);
    await db
        .into(db.oauthCodes)
        .insert(
          OauthCodesCompanion.insert(
            codeHash: _sha256Hex(code),
            clientId: client.id,
            userId: user.id,
            redirectUri: redirectUri,
            codeChallenge: challenge,
            scopes: scopes.join(' '),
            expiresAt: DateTime.now().toUtc().add(oauthCodeTtl),
          ),
        );
    final base = Uri.parse(redirectUri);
    final location = base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'code': code,
        if (form['state'] != null && form['state']!.isNotEmpty)
          'state': form['state']!,
      },
    );
    return _redirect(location.toString(), status: 303);
  });

  router.post(
    '/oauth/token',
    (Request request) => _guard(() => _tokenEndpoint(db, auth, request)),
  );

  router.post('/oauth/revoke', (Request request) {
    return _guard(() async {
      final body = await _readBody(request);
      final client = await _authenticateClient(db, auth, request, body);
      final token = body['token'];
      if (token is! String || token.isEmpty) {
        throw OAuthError(400, 'invalid_request', 'token is required');
      }
      final row = await (db.select(db.refreshTokens)
            ..where((t) => t.tokenHash.equals(auth.hashRefreshToken(token))))
          .getSingleOrNull();
      // RFC 7009 best effort: unknown tokens, access JWTs (stateless, they
      // die at their 15 minute TTL) and other clients' tokens all still get
      // a 200; only a refresh row owned by this client is revoked — with
      // its whole rotation family.
      if (row != null && row.clientId == client.id) {
        await revokeRefreshFamily(db, row.familyId, DateTime.now().toUtc());
      }
      return Response(200);
    });
  });
}
