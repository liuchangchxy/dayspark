import 'dart:convert';

import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

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

  test('GET /health returns ok and version', () async {
    final response = await app.handler(Request('GET', _uri('/health')));

    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['ok'], true);
    expect(body['version'], serverVersion);
  });

  test('POST /health returns ok and version', () async {
    final response = await app.handler(Request('POST', _uri('/health')));

    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(body['ok'], true);
    expect(body['version'], serverVersion);
  });

  test('unknown route returns 404', () async {
    final response = await app.handler(Request('GET', _uri('/nope')));

    expect(response.statusCode, 404);
  });
}
