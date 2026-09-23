import 'dart:convert';
import 'dart:io';

import 'package:dayspark_cli/dayspark_cli.dart';
import 'package:test/test.dart';

// Fake DaySpark surface: /auth/login, /auth/refresh, /auth/me and POST /mcp
// with canned tools/call payloads keyed on the frozen T2 tool names.
class FakeDaySpark {
  FakeDaySpark._(this._server);

  final HttpServer _server;
  final List<Map<String, Object?>> mcpCalls = <Map<String, Object?>>[];
  int refreshCalls = 0;
  bool mcpRejectsAccess1 = false;
  String? forceToolErrorFor;

  String get base => 'http://127.0.0.1:${_server.port}';

  static Future<FakeDaySpark> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeDaySpark._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final path = request.uri.path;
    if (path == '/auth/login' && request.method == 'POST') {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['email'] == 'user@example.com' &&
          decoded['password'] == 'hunter22') {
        _json(request, 200, <String, Object?>{
          'userId': 'user-1',
          'accessToken': 'access-1',
          'refreshToken': 'refresh-1',
          'tokenType': 'Bearer',
          'expiresIn': 900,
        });
        return;
      }
      _json(request, 401, <String, Object?>{
        'error': {'code': 'unauthorized', 'message': 'invalid email or password'},
      });
      return;
    }
    if (path == '/auth/refresh' && request.method == 'POST') {
      refreshCalls++;
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['refreshToken'] == 'refresh-1') {
        _json(request, 200, <String, Object?>{
          'accessToken': 'access-2',
          'refreshToken': 'refresh-2',
          'tokenType': 'Bearer',
          'expiresIn': 900,
        });
        return;
      }
      _json(request, 401, <String, Object?>{
        'error': {'code': 'unauthorized', 'message': 'invalid refresh token'},
      });
      return;
    }
    if (path == '/auth/me' && request.method == 'GET') {
      final bearer = _bearer(request);
      if (bearer == 'access-1' || bearer == 'access-2') {
        _json(request, 200, <String, Object?>{
          'userId': 'user-1',
          'deviceId': null,
        });
        return;
      }
      _json(request, 401, <String, Object?>{
        'error': {'code': 'unauthorized', 'message': 'invalid or expired access token'},
      });
      return;
    }
    if (path == '/mcp' && request.method == 'POST') {
      final bearer = _bearer(request);
      if (mcpRejectsAccess1 && bearer == 'access-1') {
        _json(request, 401, <String, Object?>{
          'error': {'code': 'unauthorized', 'message': 'invalid or expired access token'},
        });
        return;
      }
      final envelope = jsonDecode(body) as Map<String, dynamic>;
      final params = envelope['params'] as Map<String, dynamic>;
      final name = params['name'] as String;
      final arguments = (params['arguments'] as Map?)?.cast<String, Object?>() ??
          <String, Object?>{};
      mcpCalls.add(<String, Object?>{
        'name': name,
        'arguments': arguments,
        'bearer': bearer,
      });
      final payload = forceToolErrorFor == name
          ? <String, Object?>{
              'code': 'VALIDATION',
              'message': 'forced tool failure',
              'hint': 'test hint',
            }
          : _toolPayload(name, arguments);
      final isError = forceToolErrorFor == name;
      _json(request, 200, <String, Object?>{
        'jsonrpc': '2.0',
        'id': envelope['id'],
        'result': <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': jsonEncode(payload)},
          ],
          if (isError) 'isError': true,
        },
      });
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  Map<String, Object?> _toolPayload(String name, Map<String, Object?> args) {
    switch (name) {
      case 'list_tasks':
        return <String, Object?>{
          'tasks': <Object?>[
            <String, Object?>{
              'task_id': 't1',
              'title': 'Buy milk',
              'status': 'NEEDS-ACTION',
              'due': '2026-09-24T10:00:00.000Z',
              'priority': 0,
            },
          ],
          'next_cursor': null,
          'has_more': false,
        };
      case 'create_task':
        return <String, Object?>{
          'task': <String, Object?>{
            'task_id': 't2',
            'title': args['title'],
            'due': args['due'],
            'priority': args['priority'] ?? 0,
            'status': 'NEEDS-ACTION',
          },
          'op': {'opId': 'op-1', 'status': 'applied'},
        };
      case 'complete_task':
        return <String, Object?>{
          'task': <String, Object?>{
            'task_id': args['task_id'],
            'title': 'Buy milk',
            'status': 'COMPLETED',
          },
          'op': {'opId': 'op-2', 'status': 'applied'},
        };
      case 'trash_task':
        return <String, Object?>{
          'task': <String, Object?>{
            'task_id': args['task_id'],
            'title': 'Buy milk',
            'trashed': true,
          },
          'trashed': true,
          'op': {'opId': 'op-3', 'status': 'applied'},
        };
      case 'get_events':
        return <String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'event_id': 'e1',
              'title': 'Standup',
              'start': '2026-09-24T09:00:00.000Z',
              'end': '2026-09-24T09:15:00.000Z',
            },
          ],
          'truncated': false,
          'invalid_rrule_ids': <Object?>[],
          'window': {'from': 'x', 'to': 'y'},
        };
      case 'create_event':
        return <String, Object?>{
          'event': <String, Object?>{
            'event_id': 'e2',
            'title': args['title'],
            'start': args['start'],
            'end': args['end'],
          },
          'op': {'opId': 'op-4', 'status': 'applied'},
        };
      default:
        return <String, Object?>{
          'code': 'UNKNOWN_TOOL',
          'message': 'unknown tool: $name',
        };
    }
  }

  String? _bearer(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  void _json(HttpRequest request, int status, Map<String, Object?> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }
}

Future<String> _fileMode(String path) async {
  if (Platform.isMacOS || Platform.isIOS) {
    final result = await Process.run('stat', <String>['-f', '%Lp', path]);
    return (result.stdout as String).trim();
  }
  final result = await Process.run('stat', <String>['-c', '%a', path]);
  return (result.stdout as String).trim();
}

void main() {
  late FakeDaySpark server;
  late Directory home;
  late List<int> exitCodes;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    server = await FakeDaySpark.start();
    home = await Directory.systemTemp.createTemp('dayspark_cli_test');
    exitCodes = <int>[];
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async {
    await server.close();
    await home.delete(recursive: true);
  });

  Future<int> run(
    List<String> args, {
    Future<String?> Function()? readPassword,
  }) async {
    final code = await runDayspark(
      args,
      out: out,
      err: err,
      environment: <String, String>{'DAYSPARK_HOME': home.path},
      readPassword: readPassword,
    );
    exitCodes.add(code);
    return code;
  }

  String credentialsPath() => '${home.path}/credentials.json';

  Future<void> writeStaleCredentials() async {
    await Directory(home.path).create(recursive: true);
    await File(credentialsPath()).writeAsString(jsonEncode(<String, Object?>{
      'server': server.base,
      'userId': 'user-1',
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
    }));
  }

  Future<void> login() async {
    final code = await run(
      <String>['login', '--server', server.base, '--email', 'user@example.com'],
      readPassword: () async => 'hunter22',
    );
    expect(code, 0, reason: err.toString());
  }

  test('login stores credentials.json with mode 600 and never the password',
      () async {
    final code = await run(
      <String>['login', '--server', server.base, '--email', 'user@example.com'],
      readPassword: () async => 'hunter22',
    );
    expect(code, 0);
    final raw = await File(credentialsPath()).readAsString();
    expect(raw, contains('access-1'));
    expect(raw, contains('refresh-1'));
    expect(raw, isNot(contains('hunter22')), reason: 'password must not be stored');
    expect(await _fileMode(credentialsPath()), '600');
    expect(out.toString(), contains('user-1'));
    expect(out.toString(), isNot(contains('access-1')), reason: 'tokens must not be printed');
  });

  test('logout removes the credentials file and is idempotent', () async {
    await login();
    expect(await run(<String>['logout']), 0);
    expect(await File(credentialsPath()).exists(), isFalse);
    expect(await run(<String>['logout']), 0, reason: 'second logout is a no-op');
  });

  test('status reports identity via /auth/me without leaking tokens', () async {
    await login();
    final code = await run(<String>['status']);
    expect(code, 0);
    expect(out.toString(), contains('user-1'));
    expect(out.toString(), contains(server.base));
    expect(out.toString(), isNot(contains('access-1')));
    expect(err.toString(), isEmpty);
  });

  test('status without credentials exits 2', () async {
    final code = await run(<String>['status']);
    expect(code, 2);
    expect(err.toString(), contains('not logged in'));
  });

  test('task list calls frozen list_tasks over MCP and prints a row', () async {
    await login();
    final code = await run(<String>['task', 'list', '--filter', 'today']);
    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('Buy milk'));
    expect(out.toString(), contains('t1'));
    expect(server.mcpCalls.single['name'], 'list_tasks');
    expect(server.mcpCalls.single['arguments'], {'filter': 'today'});
    expect(server.mcpCalls.single['bearer'], 'access-1');
  });

  test('expired access token refreshes once then retries the MCP call',
      () async {
    await writeStaleCredentials();
    server.mcpRejectsAccess1 = true;
    final code = await run(<String>['task', 'list']);
    expect(code, 0, reason: err.toString());
    expect(server.refreshCalls, 1);
    expect(server.mcpCalls, hasLength(1));
    expect(server.mcpCalls.single['bearer'], 'access-2');
    final saved =
        jsonDecode(await File(credentialsPath()).readAsString())
            as Map<String, dynamic>;
    expect(saved['accessToken'], 'access-2');
    expect(saved['refreshToken'], 'refresh-2');
  });

  test('tool isError exits 1 and prints the payload message', () async {
    await login();
    server.forceToolErrorFor = 'list_tasks';
    final code = await run(<String>['task', 'list']);
    expect(code, 1);
    expect(err.toString(), contains('forced tool failure'));
  });

  test('task add calls create_task and prints the new id', () async {
    await login();
    final code = await run(<String>[
      'task',
      'add',
      'Buy',
      'milk',
      '--due',
      '2026-09-24T10:00:00Z',
      '--priority',
      '3',
    ]);
    expect(code, 0, reason: err.toString());
    final call = server.mcpCalls.single;
    expect(call['name'], 'create_task');
    expect((call['arguments'] as Map)['title'], 'Buy milk');
    expect((call['arguments'] as Map)['due'], '2026-09-24T10:00:00Z');
    expect((call['arguments'] as Map)['priority'], 3);
    expect(out.toString(), contains('t2'));
  });

  test('task done and trash use the frozen complete/trash tool names',
      () async {
    await login();
    expect(await run(<String>['task', 'done', 't1']), 0);
    expect(await run(<String>['task', 'trash', 't1']), 0);
    expect(
      server.mcpCalls.map((call) => call['name']).toList(),
      <String>['complete_task', 'trash_task'],
    );
    expect(server.mcpCalls.first['arguments'], {'task_id': 't1'});
  });

  test('task done without an id exits 2', () async {
    await login();
    final code = await run(<String>['task', 'done']);
    expect(code, 2);
    expect(err.toString(), contains('task id'));
  });

  test('event list calls get_events with the window flags', () async {
    await login();
    final code = await run(<String>[
      'event',
      'list',
      '--from',
      '2026-09-01T00:00:00Z',
      '--to',
      '2026-09-30T00:00:00Z',
    ]);
    expect(code, 0, reason: err.toString());
    expect(server.mcpCalls.single['name'], 'get_events');
    final args = server.mcpCalls.single['arguments'] as Map;
    expect(args['from'], '2026-09-01T00:00:00Z');
    expect(args['to'], '2026-09-30T00:00:00Z');
    expect(out.toString(), contains('Standup'));
  });

  test('event add calls create_event with the frozen tool name', () async {
    await login();
    final code = await run(<String>[
      'event',
      'add',
      '--title',
      'Dentist',
      '--start',
      '2026-09-25T08:00:00Z',
      '--end',
      '2026-09-25T09:00:00Z',
    ]);
    expect(code, 0, reason: err.toString());
    final call = server.mcpCalls.single;
    expect(call['name'], 'create_event');
    final args = call['arguments'] as Map;
    expect(args['title'], 'Dentist');
    expect(args['start'], '2026-09-25T08:00:00Z');
    expect(args['end'], '2026-09-25T09:00:00Z');
    expect(out.toString(), contains('e2'));
  });

  test('unknown command exits 2', () async {
    final code = await run(<String>['frobnicate']);
    expect(code, 2);
    expect(err.toString(), contains('unknown command'));
  });
}
