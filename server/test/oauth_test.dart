import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

const String _redirect = 'https://chatgpt.example.com/cb';

Uri _uri(String path) => Uri.parse('http://localhost$path');

String _encodeForm(Map<String, String> fields) => fields.entries
    .map(
      (e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
    )
    .join('&');

Future<Response> _request(
  AppServer app,
  String method,
  String path, {
  Map<String, Object?>? body,
  Map<String, String>? form,
  String? rawBody,
  String? contentType,
  String? token,
  String? basic,
}) async {
  final headers = <String, String>{};
  if (form != null) {
    headers['content-type'] = 'application/x-www-form-urlencoded';
  } else if (body != null || rawBody != null) {
    headers['content-type'] = contentType ?? 'application/json';
  }
  if (token != null) {
    headers['authorization'] = 'Bearer $token';
  }
  if (basic != null) {
    headers['authorization'] = 'Basic $basic';
  }
  return app.handler(
    Request(
      method,
      _uri(path),
      headers: headers,
      body:
          rawBody ??
          (form != null
              ? _encodeForm(form)
              : (body == null ? null : jsonEncode(body))),
    ),
  );
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

Future<Map<String, String>> _registerUser(
  AppServer app,
  String email, {
  String password = 'password123',
}) async {
  final response = await _request(app, 'POST', '/auth/register', body: {
    'email': email,
    'password': password,
  });
  final text = await response.readAsString();
  expect(response.statusCode, 201, reason: text);
  final body = jsonDecode(text) as Map<String, dynamic>;
  return {
    'userId': body['userId'] as String,
    'token': body['accessToken'] as String,
    'refresh': body['refreshToken'] as String,
  };
}

Future<Map<String, dynamic>> _registerClient(
  AppServer app, {
  String method = 'client_secret_basic',
  String redirectUri = _redirect,
  String clientName = 'ChatGPT Connector',
}) async {
  final response = await _request(app, 'POST', '/oauth/register', body: {
    'client_name': clientName,
    'redirect_uris': [redirectUri],
    'token_endpoint_auth_method': method,
  });
  final text = await response.readAsString();
  expect(response.statusCode, 201, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

String _basicAuth(String clientId, String clientSecret) =>
    base64.encode(utf8.encode('$clientId:$clientSecret'));

String _verifier() =>
    String.fromCharCodes(List.generate(64, (i) => 0x61 + (i % 26)));

String _challengeFor(String verifier) =>
    base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');

Future<Response> _authorizeGet(
  AppServer app, {
  required String clientId,
  required String redirectUri,
  String responseType = 'code',
  String? scope,
  String? state,
  String? challenge,
  String method = 'S256',
}) {
  final params = <String, String>{
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': responseType,
    if (scope != null) 'scope': scope,
    if (state != null) 'state': state,
    if (challenge != null) 'code_challenge': challenge,
    'code_challenge_method': method,
  };
  return _request(app, 'GET', '/oauth/authorize?${_encodeForm(params)}');
}

String _hiddenField(String html, String name) {
  final match = RegExp('name="$name" value="([^"]*)"').firstMatch(html);
  expect(match, isNotNull, reason: 'hidden field $name must be in the form');
  return match!.group(1)!;
}

Future<Response> _authorizePost(
  AppServer app, {
  required Map<String, String> oauthParams,
  required String email,
  required String password,
  String? csrf,
}) {
  return _request(
    app,
    'POST',
    '/oauth/authorize',
    form: {
      ...oauthParams,
      if (csrf != null) 'csrf': csrf,
      'email': email,
      'password': password,
    },
  );
}

String _codeFromLocation(String location) {
  final code = Uri.parse(location).queryParameters['code'];
  expect(code, isNotNull, reason: 'redirect must carry a code: $location');
  return code!;
}

class _Flow {
  _Flow({
    required this.client,
    required this.user,
    required this.verifier,
    required this.oauthParams,
    required this.code,
    required this.location,
  });

  final Map<String, dynamic> client;
  final Map<String, String> user;
  final String verifier;
  final Map<String, String> oauthParams;
  final String code;
  final String location;

  String get clientId => client['client_id'] as String;
  String? get clientSecret => client['client_secret'] as String?;

  String get basic => _basicAuth(clientId, clientSecret!);
}

/// DCR (confidential) -> authorize GET -> consent POST with credentials ->
/// authorization code. The code is NOT redeemed.
Future<_Flow> _authorized(AppServer app, {String scope = 'mcp:read'}) async {
  final client = await _registerClient(app);
  final user = await _registerUser(app, 'flow@example.com');
  final verifier = _verifier();
  final challenge = _challengeFor(verifier);
  final get = await _authorizeGet(
    app,
    clientId: client['client_id'] as String,
    redirectUri: _redirect,
    scope: scope,
    state: 'xyz-123',
    challenge: challenge,
  );
  final html = await get.readAsString();
  expect(get.statusCode, 200, reason: html);
  final params = <String, String>{
    'client_id': _hiddenField(html, 'client_id'),
    'redirect_uri': _hiddenField(html, 'redirect_uri'),
    'response_type': _hiddenField(html, 'response_type'),
    'scope': _hiddenField(html, 'scope'),
    'state': _hiddenField(html, 'state'),
    'code_challenge': _hiddenField(html, 'code_challenge'),
    'code_challenge_method': _hiddenField(html, 'code_challenge_method'),
  };
  final post = await _authorizePost(
    app,
    oauthParams: params,
    email: 'flow@example.com',
    password: 'password123',
    csrf: _hiddenField(html, 'csrf'),
  );
  expect(post.statusCode, 303, reason: await post.readAsString());
  final location = post.headers['location']!;
  expect(location, startsWith(_redirect));
  return _Flow(
    client: client,
    user: user,
    verifier: verifier,
    oauthParams: params,
    code: _codeFromLocation(location),
    location: location,
  );
}

Future<Response> _token(
  AppServer app, {
  required Map<String, String> form,
  String? basic,
  String? token,
}) => _request(
  app,
  'POST',
  '/oauth/token',
  form: form,
  basic: basic,
  token: token,
);

Future<Map<String, dynamic>> _redeem(
  AppServer app,
  _Flow flow, {
  String? verifierOverride,
  String? redirectOverride,
  String? codeOverride,
}) async {
  final response = await _token(
    app,
    basic: flow.basic,
    form: {
      'grant_type': 'authorization_code',
      'code': codeOverride ?? flow.code,
      'redirect_uri': redirectOverride ?? _redirect,
      'code_verifier': verifierOverride ?? flow.verifier,
    },
  );
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

Map<String, dynamic> _jwtClaims(String token) {
  final payload = token.split('.')[1];
  final padding = (4 - payload.length % 4) % 4;
  final padded = payload + List.filled(padding, '=').join();
  return jsonDecode(
    utf8.decode(base64Url.decode(padded)),
  ) as Map<String, dynamic>;
}

Future<Map<String, Object?>> _rpc(
  AppServer app,
  String token,
  String method, {
  Object? params,
  Object? id = 1,
}) async {
  final response = await _request(
    app,
    'POST',
    '/mcp',
    token: token,
    body: {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'method': method,
      if (params != null) 'params': params,
    },
  );
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<({bool isError, Map<String, dynamic> payload})> _toolCall(
  AppServer app,
  String token,
  String name, {
  Map<String, Object?> arguments = const {},
}) async {
  final body = await _rpc(
    app,
    token,
    'tools/call',
    params: {'name': name, 'arguments': arguments},
  );
  final result = body['result'] as Map<String, dynamic>;
  final isError = result['isError'] == true;
  final payload = jsonDecode(
    (result['content'] as List).first['text'] as String,
  ) as Map<String, dynamic>;
  return (isError: isError, payload: payload);
}

const Map<String, String> _validEventArgs = {
  'title': 'OAuth event',
  'start': '2026-10-01T10:00:00Z',
  'end': '2026-10-01T11:00:00Z',
};

void main() {
  late AppServer app;

  setUp(() {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
  });

  tearDown(() async {
    await app.close();
  });

  group('discovery metadata', () {
    test('authorization-server metadata advertises the OAuth 2.1 surface',
        () async {
      final response = await _request(
        app,
        'GET',
        '/.well-known/oauth-authorization-server',
      );
      expect(response.statusCode, 200);
      final body = await _json(response);
      expect(body['issuer'], 'http://localhost');
      expect(body['authorization_endpoint'], 'http://localhost/oauth/authorize');
      expect(body['token_endpoint'], 'http://localhost/oauth/token');
      expect(body['registration_endpoint'], 'http://localhost/oauth/register');
      expect(body['revocation_endpoint'], 'http://localhost/oauth/revoke');
      expect(body['response_types_supported'], ['code']);
      expect(body['grant_types_supported'], [
        'authorization_code',
        'refresh_token',
      ]);
      expect(body['code_challenge_methods_supported'], ['S256']);
      expect(
        body['token_endpoint_auth_methods_supported'],
        containsAll(['client_secret_basic', 'none']),
      );
      expect(body['scopes_supported'], ['mcp:read', 'mcp:write']);
    });

    test(
        'protected-resource metadata sits exactly where WWW-Authenticate points '
        'and names the authorization server', () async {
      final unauthorized = await _request(
        app,
        'POST',
        '/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
        },
      );
      expect(unauthorized.statusCode, 401);
      final challenge = unauthorized.headers['www-authenticate']!;
      final match = RegExp(
        r'resource_metadata="([^"]+)"',
      ).firstMatch(challenge);
      expect(match, isNotNull, reason: challenge);
      final metadataUrl = match!.group(1)!;
      expect(metadataUrl, 'http://localhost/.well-known/oauth-protected-resource');

      final parsed = Uri.parse(metadataUrl);
      final metadata = await _request(
        app,
        'GET',
        '${parsed.path}?${parsed.query}',
      );
      final metadataText = await metadata.readAsString();
      expect(metadata.statusCode, 200, reason: metadataText);
      final body = jsonDecode(metadataText) as Map<String, dynamic>;
      expect(body['resource'], 'http://localhost/mcp');
      expect(body['authorization_servers'], ['http://localhost']);
      expect(body['bearer_methods_supported'], ['header']);
      expect(body['scopes_supported'], ['mcp:read', 'mcp:write']);
    });
  });

  group('dynamic client registration', () {
    test('confidential client gets a client_secret issued (hashed at rest)',
        () async {
      final client = await _registerClient(app);
      expect(client['client_id'], isA<String>());
      expect(client['client_secret'], isA<String>());
      expect(client['token_endpoint_auth_method'], 'client_secret_basic');
      expect(client['redirect_uris'], [_redirect]);
      expect(client['grant_types'], ['authorization_code', 'refresh_token']);

      final row = await (app.db.select(app.db.oauthClients)
            ..where((t) => t.id.equals(client['client_id'] as String)))
          .getSingle();
      expect(row.clientSecretHash, isNot(client['client_secret']));
      expect(row.clientSecretHash, startsWith('argon2id\$'));
    });

    test('public client registers with auth method none and no secret',
        () async {
      final client = await _registerClient(app, method: 'none');
      expect(client['client_id'], isA<String>());
      expect(client['client_secret'], isNull);
      expect(client['token_endpoint_auth_method'], 'none');
    });

    test('registration rejects a redirect_uri without a host', () async {
      final response = await _request(app, 'POST', '/oauth/register', body: {
        'client_name': 'Bad',
        'redirect_uris': ['not-a-uri'],
        'token_endpoint_auth_method': 'none',
      });
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_client_metadata');
    });

    test('registration rejects a redirect_uri with a fragment', () async {
      final response = await _request(app, 'POST', '/oauth/register', body: {
        'client_name': 'Bad',
        'redirect_uris': ['https://example.com/cb#frag'],
        'token_endpoint_auth_method': 'none',
      });
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_client_metadata');
    });

    test('registration rejects an unsupported token_endpoint_auth_method',
        () async {
      final response = await _request(app, 'POST', '/oauth/register', body: {
        'client_name': 'Bad',
        'redirect_uris': [_redirect],
        'token_endpoint_auth_method': 'client_secret_post',
      });
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_client_metadata');
    });
  });

  group('authorize endpoint', () {
    test('consent page lists the client and the requested scopes', () async {
      final client = await _registerClient(app);
      final response = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:read mcp:write',
        challenge: _challengeFor(_verifier()),
      );
      expect(response.statusCode, 200);
      final html = await response.readAsString();
      expect(response.headers['content-type'], contains('text/html'));
      expect(html, contains('ChatGPT Connector'));
      expect(html, contains('mcp:read'));
      expect(html, contains('mcp:write'));
      expect(html, contains('name="csrf"'));
      expect(html, contains('name="email"'));
      expect(html, contains('name="password"'));
    });

    test('redirect_uri mismatch renders an error page with no code', () async {
      final client = await _registerClient(app);
      final response = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: 'https://evil.example.com/cb',
        scope: 'mcp:read',
        challenge: _challengeFor(_verifier()),
      );
      expect(response.statusCode, 400);
      expect(response.headers['location'], isNull);
      final html = await response.readAsString();
      expect(html.toLowerCase(), contains('redirect_uri'));
      expect(html, isNot(contains('code=')));
      expect(html, isNot(contains('code_challenge')));
    });

    test('unknown client_id renders an error page with no redirect',
        () async {
      final response = await _authorizeGet(
        app,
        clientId: 'nope',
        redirectUri: _redirect,
        scope: 'mcp:read',
        challenge: _challengeFor(_verifier()),
      );
      expect(response.statusCode, 400);
      expect(response.headers['location'], isNull);
      final html = await response.readAsString();
      expect(html, isNot(contains('code=')));
    });

    test('missing PKCE is rejected via error redirect without a code',
        () async {
      final client = await _registerClient(app);
      final response = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:read',
        challenge: null,
        method: 'S256',
      );
      expect(response.statusCode, anyOf(302, 303));
      final location = Uri.parse(response.headers['location']!);
      expect(location.toString(), startsWith(_redirect));
      expect(location.queryParameters['error'], 'invalid_request');
      expect(location.queryParameters['error_description'], contains('PKCE'));
      expect(location.queryParameters.containsKey('code'), isFalse);
    });

    test('code_challenge_method plain is rejected', () async {
      final client = await _registerClient(app);
      final response = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:read',
        challenge: _challengeFor(_verifier()),
        method: 'plain',
      );
      expect(response.statusCode, anyOf(302, 303));
      final location = Uri.parse(response.headers['location']!);
      expect(location.queryParameters['error'], 'invalid_request');
      expect(location.queryParameters.containsKey('code'), isFalse);
    });

    test('response_type other than code is rejected', () async {
      final client = await _registerClient(app);
      final response = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        responseType: 'token',
        scope: 'mcp:read',
        challenge: _challengeFor(_verifier()),
      );
      expect(response.statusCode, anyOf(302, 303));
      final location = Uri.parse(response.headers['location']!);
      expect(
        location.queryParameters['error'],
        'unsupported_response_type',
      );
      expect(location.queryParameters.containsKey('code'), isFalse);
    });

    test('unknown scope is rejected', () async {
      final client = await _registerClient(app);
      final response = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:admin',
        challenge: _challengeFor(_verifier()),
      );
      expect(response.statusCode, anyOf(302, 303));
      final location = Uri.parse(response.headers['location']!);
      expect(location.queryParameters['error'], 'invalid_scope');
    });

    test('consent POST without a CSRF token is rejected', () async {
      final client = await _registerClient(app);
      final verifier = _verifier();
      final response = await _authorizePost(
        app,
        oauthParams: {
          'client_id': client['client_id'] as String,
          'redirect_uri': _redirect,
          'response_type': 'code',
          'scope': 'mcp:read',
          'code_challenge': _challengeFor(verifier),
          'code_challenge_method': 'S256',
        },
        email: 'csrf@example.com',
        password: 'password123',
      );
      expect(response.statusCode, 400);
      final html = await response.readAsString();
      expect(html.toLowerCase(), contains('form token'));
      expect(html, isNot(contains('code=')));
      expect(response.headers['location'], isNull);
    });

    test('consent POST with a replayed CSRF token is rejected', () async {
      final client = await _registerClient(app);
      final user = await _registerUser(app, 'replay@example.com');
      final verifier = _verifier();
      final get = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:read',
        challenge: _challengeFor(verifier),
      );
      final html = await get.readAsString();
      final params = <String, String>{
        'client_id': _hiddenField(html, 'client_id'),
        'redirect_uri': _hiddenField(html, 'redirect_uri'),
        'response_type': _hiddenField(html, 'response_type'),
        'scope': _hiddenField(html, 'scope'),
        'code_challenge': _hiddenField(html, 'code_challenge'),
        'code_challenge_method': _hiddenField(html, 'code_challenge_method'),
      };
      final csrf = _hiddenField(html, 'csrf');

      final first = await _authorizePost(
        app,
        oauthParams: params,
        email: 'replay@example.com',
        password: 'password123',
        csrf: csrf,
      );
      expect(first.statusCode, 303, reason: await first.readAsString());
      expect(user['userId'], isNotEmpty);

      final second = await _authorizePost(
        app,
        oauthParams: params,
        email: 'replay@example.com',
        password: 'password123',
        csrf: csrf,
      );
      expect(second.statusCode, 400);
      expect(second.headers['location'], isNull);
    });

    test('wrong password re-renders the form without issuing a code',
        () async {
      final client = await _registerClient(app);
      await _registerUser(app, 'who@example.com');
      final get = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:read',
        challenge: _challengeFor(_verifier()),
      );
      final html = await get.readAsString();
      final params = <String, String>{
        'client_id': _hiddenField(html, 'client_id'),
        'redirect_uri': _hiddenField(html, 'redirect_uri'),
        'response_type': _hiddenField(html, 'response_type'),
        'scope': _hiddenField(html, 'scope'),
        'code_challenge': _hiddenField(html, 'code_challenge'),
        'code_challenge_method': _hiddenField(html, 'code_challenge_method'),
      };
      final post = await _authorizePost(
        app,
        oauthParams: params,
        email: 'who@example.com',
        password: 'wrong-password',
        csrf: _hiddenField(html, 'csrf'),
      );
      expect(post.statusCode, 400);
      final retryHtml = await post.readAsString();
      expect(retryHtml.toLowerCase(), contains('invalid email or password'));
      expect(retryHtml, isNot(contains('code=')));
      expect(post.headers['location'], isNull);
      expect(retryHtml, contains('name="csrf"'));
    });

    test('unknown email burns a dummy verify and fails the same way',
        () async {
      final client = await _registerClient(app);
      final get = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:read',
        challenge: _challengeFor(_verifier()),
      );
      final html = await get.readAsString();
      final post = await _authorizePost(
        app,
        oauthParams: {
          'client_id': _hiddenField(html, 'client_id'),
          'redirect_uri': _hiddenField(html, 'redirect_uri'),
          'response_type': _hiddenField(html, 'response_type'),
          'scope': _hiddenField(html, 'scope'),
          'code_challenge': _hiddenField(html, 'code_challenge'),
          'code_challenge_method': _hiddenField(html, 'code_challenge_method'),
        },
        email: 'ghost@example.com',
        password: 'password123',
        csrf: _hiddenField(html, 'csrf'),
      );
      expect(post.statusCode, 400);
      expect(
        (await post.readAsString()).toLowerCase(),
        contains('invalid email or password'),
      );
    });
  });

  group('token endpoint', () {
    test(
        'full flow: DCR -> authorize -> code -> token (PKCE ok) -> /mcp '
        'tools/list succeeds', () async {
      final flow = await _authorized(app, scope: 'mcp:read mcp:write');
      final tokens = await _redeem(app, flow);
      expect(tokens['token_type'], 'Bearer');
      expect(tokens['expires_in'], 900);
      expect(tokens['refresh_token'], isA<String>());
      expect(tokens['scope'], 'mcp:read mcp:write');

      final claims = _jwtClaims(tokens['access_token'] as String);
      expect(claims['sub'], flow.user['userId']);
      expect(claims['scope'], 'mcp:read mcp:write');
      expect(claims['track'], 'oauth');

      final rpc = await _rpc(app, tokens['access_token'] as String, 'tools/list');
      final tools = (rpc['result'] as Map)['tools'] as List;
      expect(tools, hasLength(17));
    });

    test('state is echoed on the success redirect', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      expect(flow.oauthParams['state'], 'xyz-123');
      final location = Uri.parse(flow.location);
      expect(location.queryParameters['state'], 'xyz-123');
      expect(location.queryParameters['code'], flow.code);
      final tokens = await _redeem(app, flow);
      final claims = _jwtClaims(tokens['access_token'] as String);
      expect(claims['scope'], 'mcp:read');
    });

    test('wrong PKCE verifier is rejected and the code stays redeemable',
        () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final wrong = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': _redirect,
          'code_verifier': List.filled(64, 'z').join(),
        },
      );
      expect(wrong.statusCode, 400);
      final wrongBody = await _json(wrong);
      expect(wrongBody['error'], 'invalid_grant');

      final ok = await _redeem(app, flow);
      expect(ok['access_token'], isA<String>());
    });

    test('authorization code is single-use', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      await _redeem(app, flow);
      final reuse = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': _redirect,
          'code_verifier': flow.verifier,
        },
      );
      expect(reuse.statusCode, 400);
      expect((await _json(reuse))['error'], 'invalid_grant');
    });

    test('code bound to redirect_uri: mismatched redemption is rejected',
        () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final response = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': 'https://evil.example.com/cb',
          'code_verifier': flow.verifier,
        },
      );
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_grant');
    });

    test('expired authorization code is rejected', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      await (app.db.update(app.db.oauthCodes)
            ..where((t) => t.codeHash.equals(_hashOf(flow.code))))
          .write(
        OauthCodesCompanion(
          expiresAt: Value(
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
          ),
        ),
      );
      final response = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': _redirect,
          'code_verifier': flow.verifier,
        },
      );
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_grant');
    });

    test('missing code_verifier is rejected', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final response = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': _redirect,
        },
      );
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_request');
    });

    test(
        'confidential client must authenticate with client_secret_basic '
        '(body client_id alone is rejected)', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final response = await _token(
        app,
        form: {
          'grant_type': 'authorization_code',
          'client_id': flow.clientId,
          'code': flow.code,
          'redirect_uri': _redirect,
          'code_verifier': flow.verifier,
        },
      );
      expect(response.statusCode, 401);
      expect((await _json(response))['error'], 'invalid_client');
    });

    test('wrong client_secret is rejected', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final response = await _token(
        app,
        basic: _basicAuth(flow.clientId, 'wrong-secret'),
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': _redirect,
          'code_verifier': flow.verifier,
        },
      );
      expect(response.statusCode, 401);
      expect((await _json(response))['error'], 'invalid_client');
    });

    test('public client redeems with client_id in the body', () async {
      final client = await _registerClient(app, method: 'none');
      await _registerUser(app, 'pub@example.com');
      final verifier = _verifier();
      final get = await _authorizeGet(
        app,
        clientId: client['client_id'] as String,
        redirectUri: _redirect,
        scope: 'mcp:write',
        challenge: _challengeFor(verifier),
      );
      final html = await get.readAsString();
      final post = await _authorizePost(
        app,
        oauthParams: {
          'client_id': _hiddenField(html, 'client_id'),
          'redirect_uri': _hiddenField(html, 'redirect_uri'),
          'response_type': _hiddenField(html, 'response_type'),
          'scope': _hiddenField(html, 'scope'),
          'code_challenge': _hiddenField(html, 'code_challenge'),
          'code_challenge_method': _hiddenField(html, 'code_challenge_method'),
        },
        email: 'pub@example.com',
        password: 'password123',
        csrf: _hiddenField(html, 'csrf'),
      );
      final code = _codeFromLocation(post.headers['location']!);

      final response = await _token(
        app,
        form: {
          'grant_type': 'authorization_code',
          'client_id': client['client_id'] as String,
          'code': code,
          'redirect_uri': _redirect,
          'code_verifier': verifier,
        },
      );
      final tokenText = await response.readAsString();
      expect(response.statusCode, 200, reason: tokenText);
      final tokens = jsonDecode(tokenText) as Map<String, dynamic>;
      expect(tokens['scope'], 'mcp:write');
    });

    test('unknown grant_type is rejected', () async {
      final response = await _token(
        app,
        form: {'grant_type': 'client_credentials'},
        basic: base64.encode(utf8.encode('x:y')),
      );
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'unsupported_grant_type');
    });
  });

  group('scope enforcement on /mcp', () {
    test(
        'read-only token: read tools and resources pass, write tool returns '
        'FORBIDDEN_SCOPE', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final tokens = await _redeem(app, flow);
      final token = tokens['access_token'] as String;

      final list = await _toolCall(app, token, 'list_tasks');
      expect(list.isError, isFalse);

      final resource = await _rpc(
        app,
        token,
        'resources/read',
        params: {'uri': 'dayspark://today'},
      );
      expect(resource['error'], isNull);
      expect((resource['result'] as Map)['contents'], isNotNull);

      final resourceList = await _rpc(app, token, 'resources/list');
      expect((resourceList['result'] as Map)['resources'], hasLength(3));

      final write = await _toolCall(
        app,
        token,
        'create_event',
        arguments: _validEventArgs,
      );
      expect(write.isError, isTrue);
      expect(write.payload['code'], 'FORBIDDEN_SCOPE');
      expect(write.payload['hint'], contains('mcp:write'));
    });

    test(
        'write-only token: writes pass, read tool and resources are gated '
        '(resources/read carry)', () async {
      final flow = await _authorized(app, scope: 'mcp:write');
      final tokens = await _redeem(app, flow);
      final token = tokens['access_token'] as String;

      final write = await _toolCall(
        app,
        token,
        'create_event',
        arguments: _validEventArgs,
      );
      expect(write.isError, isFalse, reason: '${write.payload}');
      expect((write.payload['event'] as Map)['title'], 'OAuth event');

      final read = await _toolCall(app, token, 'get_events');
      expect(read.isError, isTrue);
      expect(read.payload['code'], 'FORBIDDEN_SCOPE');
      expect(read.payload['hint'], contains('mcp:read'));

      final resource = await _rpc(
        app,
        token,
        'resources/read',
        params: {'uri': 'dayspark://today'},
      );
      expect(resource['result'], isNull);
      final error = resource['error'] as Map<String, dynamic>;
      expect(error['code'], -32000);
      final data = error['data'] as Map<String, dynamic>;
      expect(data['code'], 'FORBIDDEN_SCOPE');

      final resourceList = await _rpc(app, token, 'resources/list');
      expect(resourceList['result'], isNull);
      expect(
        ((resourceList['error'] as Map)['data'] as Map)['code'],
        'FORBIDDEN_SCOPE',
      );
    });

    test('full-scope token passes read and write tools', () async {
      final flow = await _authorized(app, scope: 'mcp:read mcp:write');
      final tokens = await _redeem(app, flow);
      final token = tokens['access_token'] as String;

      final read = await _toolCall(app, token, 'get_events');
      expect(read.isError, isFalse);

      final write = await _toolCall(
        app,
        token,
        'create_event',
        arguments: _validEventArgs,
      );
      expect(write.isError, isFalse, reason: '${write.payload}');

      final trash = await _toolCall(
        app,
        token,
        'trash_task',
        arguments: {'task_id': 'missing'},
      );
      expect(trash.payload['code'], 'TASK_NOT_FOUND');
      expect(trash.payload['code'], isNot('FORBIDDEN_SCOPE'));

      final resource = await _rpc(
        app,
        token,
        'resources/read',
        params: {'uri': 'dayspark://inbox'},
      );
      expect(resource['error'], isNull);
    });

    test('OAuth tokens are rejected on the sync API (two-track separation)',
        () async {
      final flow = await _authorized(app, scope: 'mcp:read mcp:write');
      final tokens = await _redeem(app, flow);
      final token = tokens['access_token'] as String;

      final push = await _request(
        app,
        'POST',
        '/sync/push',
        token: token,
        body: {
          'deviceId': 'device-1',
          'ops': [],
          'cursor': 0,
        },
      );
      expect(push.statusCode, 401);
      final body = await _json(push);
      expect(body['error']['code'], errUnauthorized);
      expect(body['error']['message'], contains('/mcp'));

      final login = await _registerUser(app, 'device@example.com');
      final devicePush = await _request(
        app,
        'POST',
        '/sync/push',
        token: login['token'],
        body: {
          'deviceId': 'device-1',
          'ops': [],
          'cursor': 0,
        },
      );
      expect(devicePush.statusCode, 200, reason: await devicePush.readAsString());
    });
  });

  group('refresh rotation and revocation', () {
    test('refresh grant rotates and reuse revokes the family', () async {
      final flow = await _authorized(app, scope: 'mcp:read mcp:write');
      final first = await _redeem(app, flow);
      final oldRefresh = first['refresh_token'] as String;

      final rotated = await _token(
        app,
        basic: flow.basic,
        form: {'grant_type': 'refresh_token', 'refresh_token': oldRefresh},
      );
      final rotatedText = await rotated.readAsString();
      expect(rotated.statusCode, 200, reason: rotatedText);
      final second = jsonDecode(rotatedText) as Map<String, dynamic>;
      expect(second['refresh_token'], isNot(oldRefresh));
      expect(second['scope'], 'mcp:read mcp:write');
      final claims = _jwtClaims(second['access_token'] as String);
      expect(claims['scope'], 'mcp:read mcp:write');
      expect(claims['track'], 'oauth');

      final reuse = await _token(
        app,
        basic: flow.basic,
        form: {'grant_type': 'refresh_token', 'refresh_token': oldRefresh},
      );
      expect(reuse.statusCode, 400);
      expect((await _json(reuse))['error'], 'invalid_grant');

      final successor = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'refresh_token',
          'refresh_token': second['refresh_token'] as String,
        },
      );
      expect(successor.statusCode, 400);
      expect((await _json(successor))['error'], 'invalid_grant');
    });

    test('refresh requires the owning client', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final tokens = await _redeem(app, flow);
      final other = await _registerClient(app);

      final response = await _token(
        app,
        basic: _basicAuth(
          other['client_id'] as String,
          other['client_secret'] as String,
        ),
        form: {
          'grant_type': 'refresh_token',
          'refresh_token': tokens['refresh_token'] as String,
        },
      );
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], 'invalid_grant');
    });

    test('revocation is best-effort 200 and kills the refresh token',
        () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final tokens = await _redeem(app, flow);
      final refresh = tokens['refresh_token'] as String;

      final unknown = await _request(
        app,
        'POST',
        '/oauth/revoke',
        basic: flow.basic,
        form: {'token': 'never-issued'},
      );
      expect(unknown.statusCode, 200);

      final noAuth = await _request(
        app,
        'POST',
        '/oauth/revoke',
        form: {'token': refresh},
      );
      expect(noAuth.statusCode, 401);

      final revoke = await _request(
        app,
        'POST',
        '/oauth/revoke',
        basic: flow.basic,
        form: {'token': refresh, 'token_type_hint': 'refresh_token'},
      );
      expect(revoke.statusCode, 200);
      expect(await revoke.readAsString(), isEmpty);

      final after = await _token(
        app,
        basic: flow.basic,
        form: {'grant_type': 'refresh_token', 'refresh_token': refresh},
      );
      expect(after.statusCode, 400);
      expect((await _json(after))['error'], 'invalid_grant');
    });

    test('the two token tracks cannot cross-refresh', () async {
      final flow = await _authorized(app, scope: 'mcp:read');
      final tokens = await _redeem(app, flow);

      final viaCli = await _request(
        app,
        'POST',
        '/auth/refresh',
        body: {'refreshToken': tokens['refresh_token'] as String},
      );
      expect(viaCli.statusCode, 401);
      expect(_errorCode(await viaCli.readAsString()), errUnauthorized);

      final login = await _registerUser(app, 'cross@example.com');
      final viaOAuth = await _token(
        app,
        basic: flow.basic,
        form: {
          'grant_type': 'refresh_token',
          'refresh_token': login['refresh'] as String,
        },
      );
      expect(viaOAuth.statusCode, 400);
      expect((await _json(viaOAuth))['error'], 'invalid_grant');
    });
  });

  group('T2 carries', () {
    test('401 distinguishes missing bearer from invalid bearer', () async {
      final missing = await _request(
        app,
        'POST',
        '/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ping',
        },
      );
      expect(missing.statusCode, 401);
      expect(
        missing.headers['www-authenticate'],
        contains('/.well-known/oauth-protected-resource'),
      );
      final missingBody = await _json(missing);
      expect(missingBody['error']['code'], errUnauthorized);
      expect(missingBody['error']['message'], 'missing bearer token');

      final invalid = await _request(
        app,
        'POST',
        '/mcp',
        token: 'not-a-token',
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ping',
        },
      );
      expect(invalid.statusCode, 401);
      final invalidBody = await _json(invalid);
      expect(invalidBody['error']['code'], errUnauthorized);
      expect(
        invalidBody['error']['message'],
        'invalid or expired access token',
      );
    });

    test('expired OAuth access token returns 401 with the challenge', () async {
      final now = DateTime.now().toUtc();
      final expired = JWT({
        'sub': 'someone',
        'scope': 'mcp:read',
        'track': 'oauth',
        'iat': now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/
            1000,
        'exp': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000,
      }).sign(SecretKey('test-secret'));
      final response = await _request(
        app,
        'POST',
        '/mcp',
        token: expired,
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/list',
        },
      );
      expect(response.statusCode, 401);
      expect(
        response.headers['www-authenticate'],
        contains('/.well-known/oauth-protected-resource'),
      );
      final body = await _json(response);
      expect(body['error']['code'], errUnauthorized);
      expect(
        body['error']['message'],
        'invalid or expired access token',
      );
    });

    test('POST /mcp body over 256KB returns a 413 envelope', () async {
      final login = await _registerUser(app, 'bigbody@example.com');
      final oversized = List.filled(256 * 1024 + 1, 'x').join();
      final response = await _request(
        app,
        'POST',
        '/mcp',
        rawBody: '{"jsonrpc":"2.0","id":1,"method":"$oversized"}',
        token: login['token'],
        contentType: 'application/json',
      );
      expect(response.statusCode, 413);
      final body = await _json(response);
      expect(body['error']['code'], errValidation);
      expect(body['error']['message'], contains('256KB'));
    });

    test('POST /mcp body exactly at the limit still parses', () async {
      final login = await _registerUser(app, 'limit@example.com');
      // Build a JSON body a few bytes under the cap: padding lives in a
      // harmless comment-free field the server ignores after parse.
      const overhead = '{"jsonrpc":"2.0","id":1,"method":"ping","pad":""}';
      final padLength = 256 * 1024 - overhead.length;
      expect(padLength, greaterThan(0));
      final body =
          '{"jsonrpc":"2.0","id":1,"method":"ping","pad":"'
          '${List.filled(padLength, 'p').join()}"}';
      expect(utf8.encode(body).length, 256 * 1024);
      final response = await _request(
        app,
        'POST',
        '/mcp',
        rawBody: body,
        token: login['token'],
        contentType: 'application/json',
      );
      final limitText = await response.readAsString();
      expect(response.statusCode, 200, reason: limitText);
      final decoded = jsonDecode(limitText) as Map<String, dynamic>;
      expect(decoded['result'], <String, Object?>{});
    });
  });

  group('fix round 1', () {
    test('register over the 256KB cap returns the 413 envelope', () async {
      final oversized = List.filled(256 * 1024 + 1, 'x').join();
      final response = await _request(
        app,
        'POST',
        '/oauth/register',
        rawBody: oversized,
        contentType: 'application/json',
      );
      expect(response.statusCode, 413);
      final text = await response.readAsString();
      final body = jsonDecode(text) as Map<String, dynamic>;
      expect(body['error']['code'], errValidation);
      expect((body['error'] as Map)['message'], contains('256KB'));
    });

    test('register exactly at the 256KB cap passes through', () async {
      const placeholder = 'PAD';
      const head = '{"client_name":"';
      const tail =
          '","redirect_uris":["https://chatgpt.example.com/cb"],'
          '"token_endpoint_auth_method":"none"}';
      final base = '$head$placeholder$tail';
      final padLength = 256 * 1024 - base.length + placeholder.length;
      expect(padLength, greaterThan(0));
      final body = base.replaceFirst(
        placeholder,
        List.filled(padLength, 'a').join(),
      );
      expect(utf8.encode(body).length, 256 * 1024);
      expect(jsonDecode(body), isA<Map<String, Object?>>());

      final response = await _request(
        app,
        'POST',
        '/oauth/register',
        rawBody: body,
        contentType: 'application/json',
      );
      final text = await response.readAsString();
      expect(response.statusCode, 201, reason: text);
      final registered = jsonDecode(text) as Map<String, dynamic>;
      expect(registered['client_id'], isA<String>());
      expect(
        (registered['client_name'] as String).length,
        padLength,
        reason: 'the padded name must survive the cap untouched',
      );
    });

    test(
        'authorize POST over the cap returns the 413 JSON envelope, '
        'not an HTML page', () async {
      final oversized = List.filled(256 * 1024 + 1, 'y').join();
      final response = await _request(
        app,
        'POST',
        '/oauth/authorize',
        rawBody: 'email=a@b.c&password=$oversized',
        contentType: 'application/x-www-form-urlencoded',
      );
      expect(response.statusCode, 413);
      expect(response.headers['content-type'], contains('application/json'));
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error']['code'], errValidation);
      expect((body['error'] as Map)['message'], contains('256KB'));
    });

    test('authorize rejects redirect_uri near-misses (trailing slash, scheme)',
        () async {
      final client = await _registerClient(app);
      final challenge = _challengeFor(_verifier());

      for (final nearMiss in [
        'https://chatgpt.example.com/cb/',
        'http://chatgpt.example.com/cb',
      ]) {
        final response = await _authorizeGet(
          app,
          clientId: client['client_id'] as String,
          redirectUri: nearMiss,
          scope: 'mcp:read',
          challenge: challenge,
        );
        expect(response.statusCode, 400, reason: nearMiss);
        expect(response.headers['location'], isNull, reason: nearMiss);
        final html = await response.readAsString();
        expect(html, isNot(contains('code=')), reason: nearMiss);
      }
    });

    test('token rejects redirect_uri near-misses against the bound code',
        () async {
      final flow = await _authorized(app, scope: 'mcp:read');

      for (final nearMiss in [
        'https://chatgpt.example.com/cb/',
        'http://chatgpt.example.com/cb',
      ]) {
        final response = await _token(
          app,
          basic: flow.basic,
          form: {
            'grant_type': 'authorization_code',
            'code': flow.code,
            'redirect_uri': nearMiss,
            'code_verifier': flow.verifier,
          },
        );
        final text = await response.readAsString();
        expect(response.statusCode, 400, reason: nearMiss);
        expect(
          (jsonDecode(text) as Map<String, dynamic>)['error'],
          'invalid_grant',
          reason: nearMiss,
        );
      }

      final ok = await _redeem(app, flow);
      expect(ok['access_token'], isA<String>());
    });

    test('code cannot be redeemed by a different client', () async {
      final flow = await _authorized(app, scope: 'mcp:read mcp:write');
      final other = await _registerClient(app);

      final stolen = await _token(
        app,
        basic: _basicAuth(
          other['client_id'] as String,
          other['client_secret'] as String,
        ),
        form: {
          'grant_type': 'authorization_code',
          'code': flow.code,
          'redirect_uri': _redirect,
          'code_verifier': flow.verifier,
        },
      );
      expect(stolen.statusCode, 400);
      final body = await _json(stolen);
      expect(body['error'], 'invalid_grant');
      expect(body['access_token'], isNull);

      final legit = await _redeem(app, flow);
      expect(legit['access_token'], isA<String>());
    });

    test('PKCE S256 construction matches the RFC 7636 Appendix B vector',
        () {
      expect(
        pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });
  });
}

String _hashOf(String code) =>
    sha256.convert(utf8.encode(code)).toString();

String _errorCode(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  return (decoded['error'] as Map<String, dynamic>)['code'] as String;
}
