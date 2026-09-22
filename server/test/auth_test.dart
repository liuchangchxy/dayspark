import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

Future<Response> _postJson(
  Handler handler,
  String path,
  Map<String, Object?> body,
) async {
  return await handler(
    Request(
      'POST',
      _uri(path),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );
}

String _errorCode(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final error = decoded['error'] as Map<String, dynamic>;
  return error['code'] as String;
}

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

  test('register -> login -> refresh rotates, old refresh rejected', () async {
    final register = await _postJson(app.handler, '/auth/register', {
      'email': 'alice@example.com',
      'password': 'password123',
    });
    expect(register.statusCode, 201);
    final registered =
        jsonDecode(await register.readAsString()) as Map<String, dynamic>;
    expect(registered['userId'], isNotEmpty);
    expect(registered['accessToken'], isNotEmpty);
    expect(registered['refreshToken'], isNotEmpty);

    final login = await _postJson(app.handler, '/auth/login', {
      'email': 'alice@example.com',
      'password': 'password123',
    });
    expect(login.statusCode, 200);
    final loggedIn =
        jsonDecode(await login.readAsString()) as Map<String, dynamic>;
    final firstRefresh = loggedIn['refreshToken'] as String;
    expect(firstRefresh, isNotEmpty);

    final refresh = await _postJson(app.handler, '/auth/refresh', {
      'refreshToken': firstRefresh,
    });
    expect(refresh.statusCode, 200);
    final rotated =
        jsonDecode(await refresh.readAsString()) as Map<String, dynamic>;
    final secondRefresh = rotated['refreshToken'] as String;
    expect(secondRefresh, isNotEmpty);
    expect(secondRefresh, isNot(firstRefresh));
    expect(rotated['accessToken'], isNotEmpty);

    final reuse = await _postJson(app.handler, '/auth/refresh', {
      'refreshToken': firstRefresh,
    });
    expect(reuse.statusCode, 401);
    expect(_errorCode(await reuse.readAsString()), errUnauthorized);

    // Reuse detection revokes the whole family: the successor from the
    // rotation above must die together with the replayed token.
    final familyRevoked = await _postJson(app.handler, '/auth/refresh', {
      'refreshToken': secondRefresh,
    });
    expect(familyRevoked.statusCode, 401);
    expect(_errorCode(await familyRevoked.readAsString()), errUnauthorized);
  });

  test('login with wrong password returns 401 unauthorized', () async {
    final register = await _postJson(app.handler, '/auth/register', {
      'email': 'bob@example.com',
      'password': 'password123',
    });
    expect(register.statusCode, 201);

    final login = await _postJson(app.handler, '/auth/login', {
      'email': 'bob@example.com',
      'password': 'wrong-password',
    });
    expect(login.statusCode, 401);
    expect(_errorCode(await login.readAsString()), errUnauthorized);
  });

  test('login with unknown email returns 401 unauthorized', () async {
    final login = await _postJson(app.handler, '/auth/login', {
      'email': 'ghost@example.com',
      'password': 'password123',
    });
    expect(login.statusCode, 401);
    expect(_errorCode(await login.readAsString()), errUnauthorized);
  });

  test('duplicate register returns 409 conflict', () async {
    final first = await _postJson(app.handler, '/auth/register', {
      'email': 'carol@example.com',
      'password': 'password123',
    });
    expect(first.statusCode, 201);

    final second = await _postJson(app.handler, '/auth/register', {
      'email': 'carol@example.com',
      'password': 'password456',
    });
    expect(second.statusCode, 409);
    expect(_errorCode(await second.readAsString()), errConflict);
  });

  test('register with short password returns 400 validation', () async {
    final register = await _postJson(app.handler, '/auth/register', {
      'email': 'dave@example.com',
      'password': 'short',
    });
    expect(register.statusCode, 400);
    expect(_errorCode(await register.readAsString()), errValidation);
  });

  test('protected route requires valid bearer token', () async {
    final register = await _postJson(app.handler, '/auth/register', {
      'email': 'erin@example.com',
      'password': 'password123',
    });
    final registered =
        jsonDecode(await register.readAsString()) as Map<String, dynamic>;
    final accessToken = registered['accessToken'] as String;
    final userId = registered['userId'] as String;

    final anonymous = await app.handler(Request('GET', _uri('/auth/me')));
    expect(anonymous.statusCode, 401);
    expect(_errorCode(await anonymous.readAsString()), errUnauthorized);

    final garbage = await app.handler(
      Request(
        'GET',
        _uri('/auth/me'),
        headers: {'authorization': 'Bearer not-a-token'},
      ),
    );
    expect(garbage.statusCode, 401);

    final wrongScheme = await app.handler(
      Request(
        'GET',
        _uri('/auth/me'),
        headers: {'authorization': 'Basic dXNlcjpwYXNz'},
      ),
    );
    expect(wrongScheme.statusCode, 401);

    final authorized = await app.handler(
      Request(
        'GET',
        _uri('/auth/me'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    expect(authorized.statusCode, 200);
    final me =
        jsonDecode(await authorized.readAsString()) as Map<String, dynamic>;
    expect(me['userId'], userId);
  });

  group('requireAuth middleware', () {
    late Auth auth;

    setUp(() {
      auth = app.auth;
    });

    test('missing header yields 401 envelope', () async {
      final handler = auth.requireAuth(
        (request, context) async => Response(200, body: context.userId),
      );
      final response = await handler(Request('GET', _uri('/protected')));
      expect(response.statusCode, 401);
      expect(_errorCode(await response.readAsString()), errUnauthorized);
    });

    test('valid token passes AuthContext through', () async {
      final handler = auth.requireAuth(
        (request, context) async => Response(200, body: context.userId),
      );
      final token = auth.issueAccessToken('user-123');
      final response = await handler(
        Request(
          'GET',
          _uri('/protected'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'user-123');
    });

    test('expired token is rejected', () async {
      final handler = auth.requireAuth(
        (request, context) async => Response(200, body: context.userId),
      );
      final now = DateTime.now().toUtc();
      final jwt = JWT({
        'sub': 'user-123',
        'iat':
            now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/
            1000,
        'exp':
            now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000,
      });
      final expired = jwt.sign(SecretKey('test-secret'));
      final response = await handler(
        Request(
          'GET',
          _uri('/protected'),
          headers: {'authorization': 'Bearer $expired'},
        ),
      );
      expect(response.statusCode, 401);
      expect(_errorCode(await response.readAsString()), errUnauthorized);
    });
  });
}
