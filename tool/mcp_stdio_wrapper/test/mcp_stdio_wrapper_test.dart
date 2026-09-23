import 'dart:convert';
import 'dart:io';

import 'package:mcp_stdio_wrapper/mcp_stdio_wrapper.dart';
import 'package:test/test.dart';

void main() {
  late List<String> posted;
  late List<String> written;

  Future<HttpPostResult> okPoster(String body) async {
    posted.add(body);
    return HttpPostResult(
      200,
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 7,
        'result': <String, Object?>{
          'protocolVersion': '2025-03-26',
          'capabilities': <String, Object?>{},
          'serverInfo': {'name': 'dayspark', 'version': '0.23.0'},
        },
      }),
    );
  }

  Stream<String> stdinLines(List<String> lines) => Stream.fromIterable(lines);

  setUp(() {
    posted = <String>[];
    written = <String>[];
  });

  test('initialize roundtrip proxies one POST and writes one response line',
      () async {
    final request = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'initialize',
      'params': <String, Object?>{'protocolVersion': '2025-03-26'},
    });
    await runBridge(
      lines: stdinLines(<String>[request]),
      writeLine: written.add,
      post: okPoster,
    );
    expect(posted, <String>[request]);
    expect(written, hasLength(1));
    final echoed = jsonDecode(written.single) as Map<String, dynamic>;
    expect(echoed['id'], 7);
    expect(echoed['result']['serverInfo']['name'], 'dayspark');
  });

  test('tools/call roundtrip returns the server response line unchanged',
      () async {
    final request = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': <String, Object?>{'name': 'list_tasks', 'arguments': {}},
    });
    const serverLine =
        '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{}"}]}}';
    await runBridge(
      lines: stdinLines(<String>[request]),
      writeLine: written.add,
      post: (String body) async => HttpPostResult(200, serverLine),
    );
    expect(written, <String>[serverLine]);
  });

  test('network failure surfaces JSON-RPC -32002 instead of hanging',
      () async {
    final request = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 11,
      'method': 'ping',
    });
    await runBridge(
      lines: stdinLines(<String>[request]),
      writeLine: written.add,
      post: (String body) async =>
          throw const SocketException('connection refused'),
    );
    expect(written, hasLength(1));
    final echoed = jsonDecode(written.single) as Map<String, dynamic>;
    expect(echoed['id'], 11);
    expect(echoed['error']['code'], -32002);
    expect('${echoed['error']['message']}', contains('connection refused'));
  });

  test('notification without id posts and emits nothing on 202', () async {
    final notification = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    var status = 202;
    await runBridge(
      lines: stdinLines(<String>[notification, notification]),
      writeLine: written.add,
      post: (String body) async {
        posted.add(body);
        return HttpPostResult(status, '');
      },
    );
    expect(posted, hasLength(2));
    expect(written, isEmpty);

    // Even a 200-with-body reply to a notification stays silent.
    status = 200;
    posted.clear();
    await runBridge(
      lines: stdinLines(<String>[notification]),
      writeLine: written.add,
      post: (String body) async {
        posted.add(body);
        return HttpPostResult(200, '{"jsonrpc":"2.0","result":{}}');
      },
    );
    expect(posted, hasLength(1));
    expect(written, isEmpty);
  });

  test('non-JSON-RPC HTTP error envelope is wrapped as -32002', () async {
    final request = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 5,
      'method': 'tools/list',
    });
    await runBridge(
      lines: stdinLines(<String>[request]),
      writeLine: written.add,
      post: (String body) async => HttpPostResult(
        401,
        '{"error":{"code":"unauthorized","message":"invalid token"}}',
      ),
    );
    expect(written, hasLength(1));
    final echoed = jsonDecode(written.single) as Map<String, dynamic>;
    expect(echoed['id'], 5);
    expect(echoed['error']['code'], -32002);
    expect(echoed['error']['data']['status'], 401);
  });

  test('server JSON-RPC error envelope on 400 passes through untouched',
      () async {
    final request = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 9,
      'method': 'nope',
    });
    const errorLine =
        '{"jsonrpc":"2.0","id":9,"error":{"code":-32601,"message":"Method not found: nope"}}';
    await runBridge(
      lines: stdinLines(<String>[request]),
      writeLine: written.add,
      post: (String body) async => HttpPostResult(400, errorLine),
    );
    expect(written, <String>[errorLine]);
  });

  test('malformed stdin lines are dropped with a stderr note', () async {
    final valid = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'ping',
    });
    await runBridge(
      lines: stdinLines(<String>['not-json', '  ', valid]),
      writeLine: written.add,
      post: okPoster,
    );
    expect(written, hasLength(1));
    expect(jsonDecode(written.single)['id'], 7);
  });

  test('envError names the missing variable', () {
    expect(envError(<String, String>{}), contains('DAYSPARK_MCP_URL'));
    expect(
      envError(<String, String>{'DAYSPARK_MCP_URL': 'http://x/mcp'}),
      contains('DAYSPARK_MCP_TOKEN'),
    );
    expect(
      envError(<String, String>{
        'DAYSPARK_MCP_URL': 'http://x/mcp',
        'DAYSPARK_MCP_TOKEN': 't',
      }),
      isNull,
    );
    expect(exitConfig, 78);
  });

  test('bin exits 78 when DAYSPARK_MCP_URL is missing', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/mcp_stdio_wrapper.dart'],
      environment: <String, String>{'DAYSPARK_MCP_URL': ''},
    );
    expect(result.exitCode, 78, reason: result.stderr.toString());
    expect(result.stderr.toString(), contains('DAYSPARK_MCP_URL'));
  });
}
