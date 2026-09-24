import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

// Frozen tool table from the Task-2 brief (names/params exactly as listed).
const Set<String> frozenTools = {
  'get_events',
  'get_event',
  'list_tasks',
  'get_task',
  'search',
  'find_free_time',
  'list_trash',
  'create_event',
  'update_event',
  'trash_event',
  'create_task',
  'update_task',
  'complete_task',
  'reopen_task',
  'snooze_task',
  'trash_task',
  'batch_create_tasks',
};

const Set<String> readOnlyTools = {
  'get_events',
  'get_event',
  'list_tasks',
  'get_task',
  'search',
  'find_free_time',
  'list_trash',
};

const Set<String> trashTools = {'trash_event', 'trash_task'};

Uri _uri(String path) => Uri.parse('http://localhost$path');

Future<Response> _request(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? rawBody,
  String? token,
  String? contentType,
}) async {
  return await handler(
    Request(
      method,
      _uri(path),
      headers: {
        if (body != null || rawBody != null)
          'content-type': contentType ?? 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: rawBody ?? (body == null ? null : jsonEncode(body)),
    ),
  );
}

Future<Map<String, dynamic>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

Future<Map<String, String>> _register(AppServer app, String email) async {
  final response = await _request(app.handler, 'POST', '/auth/register', body: {
    'email': email,
    'password': 'password123',
  });
  expect(response.statusCode, 201, reason: 'register must succeed');
  final body = await _json(response);
  return {
    'userId': body['userId'] as String,
    'token': body['accessToken'] as String,
  };
}

Future<Map<String, dynamic>> _rpc(
  AppServer app,
  String token,
  String method, {
  Object? params,
  Object? id = 1,
  bool withId = true,
}) async {
  final response = await _request(
    app.handler,
    'POST',
    '/mcp',
    token: token,
    body: {
      'jsonrpc': '2.0',
      if (withId) 'id': id,
      'method': method,
      if (params != null) 'params': params,
    },
  );
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

void main() {
  late AppServer app;
  late String token;

  setUp(() async {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
    token = (await _register(app, 'mcp-proto@example.com'))['token']!;
  });

  tearDown(() async {
    await app.close();
  });

  test('initialize roundtrip echoes a supported protocol version and serverInfo',
      () async {
    final body = await _rpc(
      app,
      token,
      'initialize',
      params: {
        'protocolVersion': '2025-03-26',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'test-client', 'version': '1.0'},
      },
    );
    final result = body['result'] as Map<String, dynamic>;
    expect(result['protocolVersion'], '2025-03-26');
    // Reference the constant, not a literal: the value is pinned against
    // pubspec.yaml by tool/check_version_consistency.sh, so a literal here
    // would just re-assert the drift.
    expect(result['serverInfo'], {'name': 'dayspark', 'version': mcpServerVersion});
    final capabilities = result['capabilities'] as Map<String, dynamic>;
    expect((capabilities['tools'] as Map)['listChanged'], false);
    expect((capabilities['resources'] as Map)['listChanged'], false);
    expect(body['id'], 1);
    expect(body['jsonrpc'], '2.0');
  });

  test('initialize falls back to the latest version for an unknown client version',
      () async {
    final body = await _rpc(
      app,
      token,
      'initialize',
      params: {
        'protocolVersion': '1999-01-01',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'old-client', 'version': '0.1'},
      },
    );
    final result = body['result'] as Map<String, dynamic>;
    expect(result['protocolVersion'], '2025-06-18');
  });

  test('ping returns an empty result', () async {
    final body = await _rpc(app, token, 'ping');
    expect(body['result'], <String, Object?>{});
  });

  test('internal tool failure is opaque and carries INTERNAL', () {
    final payload = mcpToolInternalFailure(
      'get_events',
      Exception('SELECT * FROM secrets failed'),
    );
    expect(payload['code'], mcpCodeInternal);
    expect(payload['message'], contains('get_events'));
    expect(payload['message'], isNot(contains('SELECT')));
    expect(payload['message'], isNot(contains('secrets')));
    expect(payload['hint'], contains('server logs'));
  });

  test('unknown method returns JSON-RPC -32601 with the request id', () async {
    final body = await _rpc(app, token, 'resources/subscribe', id: 7);
    expect(body['result'], isNull);
    final error = body['error'] as Map<String, dynamic>;
    expect(error['code'], -32601);
    expect(error['message'], contains('Method not found'));
    expect(body['id'], 7);
  });

  test(
      'unauthenticated /mcp returns 401 with WWW-Authenticate pointing at the OAuth resource metadata',
      () async {
    final response = await _request(
      app.handler,
      'POST',
      '/mcp',
      body: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18'},
      },
    );
    expect(response.statusCode, 401);
    final www = response.headers['www-authenticate'];
    expect(www, isNotNull, reason: 'RFC 9728 discovery header is required');
    expect(www, contains('Bearer'));
    expect(www, contains('resource_metadata='));
    expect(www, contains('/.well-known/oauth-protected-resource'));
    final body = await _json(response);
    expect(body['error'], isNotNull);
    expect((body['error'] as Map)['code'], errUnauthorized);
  });

  test('invalid bearer token returns 401 with the same WWW-Authenticate challenge',
      () async {
    final response = await _request(
      app.handler,
      'POST',
      '/mcp',
      token: 'not-a-token',
      body: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'ping',
      },
    );
    expect(response.statusCode, 401);
    expect(
      response.headers['www-authenticate'],
      contains('/.well-known/oauth-protected-resource'),
    );
    expect(((await _json(response))['error'] as Map)['code'], errUnauthorized);
  });

  test('tools/list exposes exactly the frozen tools with schemas and annotations',
      () async {
    final body = await _rpc(app, token, 'tools/list');
    final tools = (body['result'] as Map)['tools'] as List<dynamic>;
    final names = tools.map((t) => (t as Map)['name'] as String).toSet();
    expect(names, frozenTools, reason: 'frozen table is the contract');
    expect(tools, hasLength(frozenTools.length));

    for (final raw in tools) {
      final tool = raw as Map<String, dynamic>;
      expect(tool['description'], isA<String>());
      expect((tool['description'] as String).isNotEmpty, isTrue);
      final schema = tool['inputSchema'] as Map<String, dynamic>;
      expect(schema['type'], 'object');
      expect(schema['properties'], isA<Map<String, dynamic>>());

      final annotations = tool['annotations'] as Map<String, dynamic>;
      final name = tool['name'] as String;
      expect(annotations['readOnlyHint'], readOnlyTools.contains(name),
          reason: '$name readOnlyHint');
      if (readOnlyTools.contains(name)) {
        expect(annotations['destructiveHint'], isNot(true),
            reason: '$name is read-only');
      } else {
        expect(annotations['readOnlyHint'], false);
        if (trashTools.contains(name)) {
          expect(annotations['destructiveHint'], true,
              reason: '$name soft-deletes data');
        } else {
          expect(annotations['destructiveHint'], isNot(true),
              reason: '$name must not claim destructive');
        }
      }
    }
  });

  test('tools/call with an unknown tool returns a tool result, not a JSON-RPC error',
      () async {
    final body = await _rpc(
      app,
      token,
      'tools/call',
      params: {'name': 'delete_everything', 'arguments': <String, Object?>{}},
    );
    expect(body['error'], isNull);
    final result = body['result'] as Map<String, dynamic>;
    expect(result['isError'], true);
    final payload =
        jsonDecode((result['content'] as List).first['text'] as String)
            as Map<String, dynamic>;
    expect(payload['code'], 'UNKNOWN_TOOL');
    expect(payload['hint'], contains('tools/list'));
  });

  test('unparseable body returns JSON-RPC -32700 with HTTP 400', () async {
    final response = await _request(
      app.handler,
      'POST',
      '/mcp',
      rawBody: 'not json {',
      token: token,
      contentType: 'application/json',
    );
    expect(response.statusCode, 400);
    final body = await _json(response);
    expect(body['error']['code'], -32700);
    expect(body['jsonrpc'], '2.0');
  });

  test('notification without id returns 202 with an empty body', () async {
    final response = await _request(
      app.handler,
      'POST',
      '/mcp',
      token: token,
      body: {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
    );
    expect(response.statusCode, 202);
    expect(await response.readAsString(), isEmpty);
  });

  test('message missing jsonrpc field returns -32600 Invalid Request', () async {
    final response = await _request(
      app.handler,
      'POST',
      '/mcp',
      token: token,
      body: {
        'id': 1,
        'method': 'ping',
      },
    );
    expect(response.statusCode, 400);
    final body = await _json(response);
    expect(body['error']['code'], -32600);
    expect(body['error']['message'], contains('jsonrpc'));
  });

  test('batch arrays are rejected as Invalid Request (single-message subset)',
      () async {
    final response = await _request(
      app.handler,
      'POST',
      '/mcp',
      token: token,
      rawBody: jsonEncode([
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ping',
        },
      ]),
    );
    expect(response.statusCode, 400);
    final body = await _json(response);
    expect(body['error']['code'], -32600);
    expect(body['error']['message'], contains('one JSON-RPC message'));
  });

  test('resources/list returns the three dayspark URIs as application/json',
      () async {
    final body = await _rpc(app, token, 'resources/list');
    final resources = (body['result'] as Map)['resources'] as List<dynamic>;
    expect(resources, hasLength(3));
    final byUri = {
      for (final raw in resources)
        (raw as Map)['uri'] as String: raw,
    };
    expect(
      byUri.keys.toSet(),
      {'dayspark://today', 'dayspark://overdue', 'dayspark://inbox'},
    );
    for (final entry in byUri.entries) {
      final resource = entry.value;
      expect(resource['mimeType'], 'application/json');
      expect(resource['name'], isA<String>());
      expect((resource['name'] as String).isNotEmpty, isTrue);
      expect(resource['description'], isA<String>());
      expect((resource['description'] as String).isNotEmpty, isTrue);
    }
    final today = byUri['dayspark://today'] as Map;
    expect((today['description'] as String).toLowerCase(), contains('utc'));
  });

  test('resources/read of an unknown URI returns JSON-RPC -32002', () async {
    final body = await _rpc(
      app,
      token,
      'resources/read',
      params: {'uri': 'dayspark://tomorrow'},
    );
    expect(body['result'], isNull);
    final error = body['error'] as Map<String, dynamic>;
    expect(error['code'], -32002);
    expect(error['message'], contains('dayspark://tomorrow'));
    final data = error['data'] as Map<String, dynamic>;
    expect(data['code'], 'RESOURCE_NOT_FOUND');
    expect(data['hint'], contains('resources/list'));
  });

  test('scope checker seam is consulted per call and can deny with FORBIDDEN_SCOPE',
      () async {
    final seen = <McpScopeRequest>[];
    app.mcp.scopeChecker = (request) {
      seen.add(request);
      if (request.tool == 'create_event') {
        return const ScopeDecision(
          'FORBIDDEN_SCOPE',
          'token lacks scope mcp:write',
          'request an access token granted the mcp:write scope',
        );
      }
      return null;
    };

    final readBody = await _rpc(
      app,
      token,
      'tools/call',
      params: {'name': 'list_tasks', 'arguments': <String, Object?>{}},
    );
    expect((readBody['result'] as Map)['isError'], isNull);

    final writeBody = await _rpc(
      app,
      token,
      'tools/call',
      params: {
        'name': 'create_event',
        'arguments': {
          'title': 'nope',
          'start': '2026-09-23T10:00:00Z',
          'end': '2026-09-23T11:00:00Z',
        },
      },
    );
    final writeResult = writeBody['result'] as Map<String, dynamic>;
    expect(writeResult['isError'], true);
    final payload = jsonDecode(
      (writeResult['content'] as List).first['text'] as String,
    ) as Map<String, dynamic>;
    expect(payload['code'], 'FORBIDDEN_SCOPE');
    expect(payload['hint'], contains('mcp:write'));

    expect(seen.map((r) => r.tool).toList(),
        ['list_tasks', 'create_event']);
    expect(seen.first.readOnly, isTrue);
    expect(seen.first.destructive, isFalse);
    expect(seen.last.readOnly, isFalse);
    expect(seen.first.userId, isNotEmpty);
  });
}
