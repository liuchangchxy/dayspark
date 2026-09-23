import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

// MCP × device-sync end-to-end matrix (Task 5, P3) — the cross-layer five
// cases that mcp_tools_test/oauth_test (in-process handler harness) cannot
// cover: AI-write → device-pull convergence over real sockets, LWW between
// an MCP op and a /sync/push op on one record, and the full OAuth chain
// served (not harnessed).
//
// Location choice: server-side (`server/test/mcp_e2e_test.dart`), not the
// Flutter app harness. The P2 two-device harness already boots this exact
// AppServer in-process, so the device half here is a second real-HTTP
// client driving the production /sync/push + /sync/pull routes — the
// brief's "second HTTP client mimicking device pull". That keeps all five
// matrix cases in one suite, exercises the wire protocol both AI and
// devices share, and avoids duplicating the engine stack; the P2 harness
// remains the authority for engine-level convergence.
//
// Sync is driven explicitly: MCP calls are awaited to completion and the
// device issues pull(cursor) rounds (plus push piggyback watermarks). The
// only waits are bounded SSE event awaits (waitForData: 5s deadline, 5ms
// poll) — never a bare sleep as a sync mechanism.

String _iso(DateTime dt) => dt.toUtc().toIso8601String();

class _Api {
  _Api(this.baseUrl)
    : _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  final String baseUrl;
  final HttpClient _client;

  Future<void> close() async {
    _client.close(force: true);
  }

  Future<({int status, String text, String? location})> send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? form,
    String? token,
    Map<String, String>? headers,
  }) async {
    final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.followRedirects = false;
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    headers?.forEach(request.headers.set);
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    } else if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(
        form.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}='
                  '${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (
      status: response.statusCode,
      text: text,
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  Future<_SseFeed> openSse(String token) async {
    final request = await _client.openUrl(
      'GET',
      Uri.parse('$baseUrl/sync/stream'),
    );
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    expect(response.statusCode, 200, reason: 'stream must open');
    return _SseFeed(response);
  }
}

class _SseFeed {
  _SseFeed(HttpClientResponse response) {
    _subscription = response.listen((chunk) {
      _buffer.write(utf8.decode(chunk));
    }, onError: (Object error) {
      _error = error;
    });
  }

  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<List<int>>? _subscription;
  Object? _error;

  String get raw => _buffer.toString();

  /// Bounded await on a specific SSE frame (not a bare sleep): polls every
  /// 5ms until the frame arrives or the 5s deadline fails the test.
  Future<void> waitForData(
    String payload, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!raw.contains('data: $payload\n\n')) {
      if (_error != null) {
        fail('stream failed: $_error');
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $payload; received: $raw');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
  }
}

/// Second HTTP client mimicking a device: its own bearer token (separate
/// /auth/login session for the same user), its own cursor and record
/// mirror, driving sync via explicit push/pull rounds.
class _Device {
  _Device(this.api, this.token);

  final _Api api;
  final String token;
  int cursor = 0;
  final records = <String, Map<String, dynamic>>{};

  void _absorb(List<Map<String, dynamic>> changes) {
    for (final change in changes) {
      records[change['id'] as String] = change;
    }
  }

  Future<List<Map<String, dynamic>>> pull() async {
    final res = await api.send(
      'GET',
      '/sync/pull?cursor=$cursor',
      token: token,
    );
    expect(res.status, 200, reason: res.text);
    final body = jsonDecode(res.text) as Map<String, dynamic>;
    final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
    _absorb(changes);
    cursor = body['nextCursor'] as int;
    return changes;
  }

  Future<Map<String, dynamic>> push(List<Map<String, Object?>> ops) async {
    final res = await api.send(
      'POST',
      '/sync/push',
      token: token,
      json: {'deviceId': 'e2e-device', 'ops': ops, 'cursor': cursor},
    );
    expect(res.status, 200, reason: res.text);
    final body = jsonDecode(res.text) as Map<String, dynamic>;
    expect(
      (body['results'] as List).map((r) => (r as Map)['status']),
      everyElement('applied'),
      reason: res.text,
    );
    _absorb((body['piggyback'] as List).cast<Map<String, dynamic>>());
    cursor = body['cursor'] as int;
    return body;
  }
}

Future<Map<String, String>> _register(
  _Api api,
  String email, {
  String password = 'password123',
}) async {
  final res = await api.send('POST', '/auth/register', json: {
    'email': email,
    'password': password,
  });
  expect(res.status, 201, reason: res.text);
  final body = jsonDecode(res.text) as Map<String, dynamic>;
  return {
    'userId': body['userId'] as String,
    'token': body['accessToken'] as String,
    'refresh': body['refreshToken'] as String,
  };
}

Future<String> _login(_Api api, String email, String password) async {
  final res = await api.send('POST', '/auth/login', json: {
    'email': email,
    'password': password,
  });
  expect(res.status, 200, reason: res.text);
  final body = jsonDecode(res.text) as Map<String, dynamic>;
  return body['accessToken'] as String;
}

Future<Map<String, dynamic>> _rpc(
  _Api api,
  String token,
  String method, {
  Object? params,
}) async {
  final res = await api.send('POST', '/mcp', token: token, json: {
    'jsonrpc': '2.0',
    'id': 1,
    'method': method,
    if (params != null) 'params': params,
  });
  expect(res.status, 200, reason: res.text);
  final body = jsonDecode(res.text) as Map<String, dynamic>;
  expect(body['error'], isNull, reason: res.text);
  return body['result'] as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _tool(
  _Api api,
  String token,
  String name,
  Map<String, Object?> args,
) async {
  final result = await _rpc(
    api,
    token,
    'tools/call',
    params: {'name': name, 'arguments': args},
  );
  expect(result['isError'], isNot(true), reason: '${result['content']}');
  final text = (result['content'] as List).first['text'] as String;
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _toolErr(
  _Api api,
  String token,
  String name,
  Map<String, Object?> args,
) async {
  final result = await _rpc(
    api,
    token,
    'tools/call',
    params: {'name': name, 'arguments': args},
  );
  expect(result['isError'], true, reason: '${result['content']}');
  final text = (result['content'] as List).first['text'] as String;
  return jsonDecode(text) as Map<String, dynamic>;
}

String _verifier() =>
    String.fromCharCodes(List.generate(64, (i) => 0x61 + (i % 26)));

String _challengeFor(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

String _hiddenField(String html, String name) {
  final match = RegExp('name="$name" value="([^"]*)"').firstMatch(html);
  expect(match, isNotNull, reason: 'hidden field $name must be in the form');
  return match!.group(1)!;
}

Future<Map<String, String>> _dcr(
  _Api api, {
  String redirect = 'https://chatgpt.example.com/cb',
}) async {
  final res = await api.send('POST', '/oauth/register', json: {
    'client_name': 'MCP e2e matrix',
    'redirect_uris': [redirect],
    'token_endpoint_auth_method': 'client_secret_basic',
  });
  expect(res.status, 201, reason: res.text);
  final body = jsonDecode(res.text) as Map<String, dynamic>;
  return {
    'client_id': body['client_id'] as String,
    'client_secret': body['client_secret'] as String,
    'redirect': redirect,
  };
}

/// DCR → authorize GET → consent POST (real credentials) → 303 code.
Future<({String code, String clientId, String clientSecret, String verifier})>
    _authorizeCode(
  _Api api, {
  required String email,
  String password = 'password123',
  String scope = 'mcp:read mcp:write',
}) async {
  final client = await _dcr(api);
  final verifier = _verifier();
  final params = {
    'client_id': client['client_id']!,
    'redirect_uri': client['redirect']!,
    'response_type': 'code',
    'scope': scope,
    'state': 'e2e-state',
    'code_challenge': _challengeFor(verifier),
    'code_challenge_method': 'S256',
  };
  final query = params.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
  final get = await api.send('GET', '/oauth/authorize?$query');
  expect(get.status, 200, reason: get.text);
  final post = await api.send('POST', '/oauth/authorize', form: {
    'client_id': _hiddenField(get.text, 'client_id'),
    'redirect_uri': _hiddenField(get.text, 'redirect_uri'),
    'response_type': _hiddenField(get.text, 'response_type'),
    'scope': _hiddenField(get.text, 'scope'),
    'state': _hiddenField(get.text, 'state'),
    'code_challenge': _hiddenField(get.text, 'code_challenge'),
    'code_challenge_method': _hiddenField(get.text, 'code_challenge_method'),
    'csrf': _hiddenField(get.text, 'csrf'),
    'email': email,
    'password': password,
  });
  expect(post.status, 303, reason: post.text);
  final location = Uri.parse(post.location!);
  expect(location.queryParameters['error'], isNull, reason: post.location);
  final code = location.queryParameters['code'];
  expect(code, isNotNull, reason: post.location);
  return (
    code: code!,
    clientId: client['client_id']!,
    clientSecret: client['client_secret']!,
    verifier: verifier,
  );
}

Future<Map<String, dynamic>> _redeem(
  _Api api, {
  required String code,
  required String clientId,
  required String clientSecret,
  required String verifier,
  String redirect = 'https://chatgpt.example.com/cb',
}) async {
  final basic = base64.encode(utf8.encode('$clientId:$clientSecret'));
  final res = await api.send(
    'POST',
    '/oauth/token',
    form: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirect,
      'code_verifier': verifier,
    },
    headers: {'authorization': 'Basic $basic'},
  );
  expect(res.status, 200, reason: res.text);
  return jsonDecode(res.text) as Map<String, dynamic>;
}

Map<String, Object?> _eventFields({
  required String summary,
  required DateTime start,
  required DateTime end,
  String? description,
}) {
  final now = DateTime.now().toUtc();
  return {
    'summary': summary,
    'description': description,
    'startDt': _iso(start),
    'endDt': _iso(end),
    'isAllDay': false,
    'location': null,
    'rrule': null,
    'deletedAt': null,
    'createdAt': _iso(now),
    'updatedAt': _iso(now),
  };
}

void main() {
  late _Api api;
  late AppServer app;
  late HttpServer http;
  late Directory tempDir;
  late String baseUrl;
  late String email;
  late String aiToken;
  late List<int> seqAdvances;
  var registerSeq = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dayspark_mcp_e2e_');
    app = AppServer(
      Config(
        dbPath: '${tempDir.path}/server.db',
        port: 0,
        jwtSecret: 'e2e-secret',
      ),
    );
    seqAdvances = <int>[];
    app.onSeqAdvanced = (user, seq) => seqAdvances.add(seq);
    http = await app.serve();
    baseUrl = 'http://127.0.0.1:${http.port}';
    api = _Api(baseUrl);
    email = 'mcp-e2e-${registerSeq++}@dayspark.test';
    final account = await _register(api, email);
    aiToken = account['token']!;
  });

  tearDown(() async {
    await api.close();
    await http.close(force: true);
    await app.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<_Device> device() async =>
      _Device(api, await _login(api, email, 'password123'));

  test(
      '① AI create_event → device pull sees the record and the SSE cursor fires',
      () async {
    final feed = await api.openSse(aiToken);
    await feed.waitForData('{"cursor":0}');

    final start = DateTime.now().toUtc().add(const Duration(hours: 5));
    final data = await _tool(api, aiToken, 'create_event', {
      'title': 'AI created',
      'start': _iso(start),
      'end': _iso(start.add(const Duration(hours: 1))),
    });
    final id = (data['event'] as Map)['event_id'] as String;
    expect((data['op'] as Map)['status'], 'applied');

    // Hub capture: the SSE frame (via streamHub.broadcast) and the explicit
    // onSeqAdvanced seam both observe seq 1 for this write.
    await feed.waitForData('{"cursor":1}');
    expect(seqAdvances, contains(1), reason: 'hub seam fired');

    final d = await device();
    final changes = await d.pull();
    expect(changes, hasLength(1));
    final change = changes.single;
    expect(change['id'], id);
    expect(change['rev'], 1);
    expect((change['payload'] as Map)['summary'], 'AI created');
    expect(d.cursor, greaterThan(0));

    final empty = await d.pull();
    expect(empty, isEmpty, reason: 'follow-up pull round is a no-op');
    await feed.cancel();
  });

  test('② AI complete_task → device pull shows the completed state converging',
      () async {
    final d = await device();
    final due = DateTime.now().toUtc().add(const Duration(hours: 3));
    await d.push([
      {
        'opId': 'e2e-td-create-1',
        'op': 'upsert',
        'recordId': 'e2e-td-1',
        'type': 'todo',
        'fields': {
          'summary': 'device task',
          'description': null,
          'dueDate': _iso(due),
          'priority': 1,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'completedAt': null,
          'deletedAt': null,
          'createdAt': _iso(DateTime.now().toUtc()),
          'updatedAt': _iso(DateTime.now().toUtc()),
        },
      },
    ]);
    expect(d.records['e2e-td-1']!['rev'], 1);

    final data = await _tool(api, aiToken, 'complete_task', {
      'task_id': 'e2e-td-1',
    });
    expect((data['task'] as Map)['status'], 'COMPLETED');

    final changes = await d.pull();
    expect(changes, hasLength(1));
    final change = changes.single;
    expect(change['id'], 'e2e-td-1');
    expect(change['rev'], 2, reason: 'create + complete = rev 2');
    final payload = change['payload'] as Map;
    expect(payload['status'], 'COMPLETED');
    expect(payload['percentComplete'], 100);
    expect(payload['completedAt'], isNotNull);
    expect(payload['summary'], 'device task',
        reason: 'fields the AI op did not set keep the device value');
    expect(d.records['e2e-td-1']!['rev'], 2, reason: 'mirror converged');

    final empty = await d.pull();
    expect(empty, isEmpty, reason: 'stable convergence on the next round');
  });

  test(
      '③ AI write vs device write on the SAME record concurrently → '
      'field-level LWW keeps both disjoint edits on both sides', () async {
    final d = await device();
    final start = DateTime.now().toUtc().add(const Duration(days: 1));
    await d.push([
      {
        'opId': 'e2e-evt-create-1',
        'op': 'upsert',
        'recordId': 'e2e-evt-1',
        'type': 'event',
        'fields': _eventFields(
          summary: 'shared note',
          start: start,
          end: start.add(const Duration(hours: 1)),
          description: 'original',
        ),
      },
    ]);
    expect(d.records['e2e-evt-1']!['rev'], 1);

    // Concurrent disjoint-field writes on one record, exactly like the P2
    // lost-update case: AI sets summary (update_event title), device sets
    // description via /sync/push. Arrival order at the server is racy but
    // field-level LWW merges keys, so both must survive either way.
    final aiCall = _tool(api, aiToken, 'update_event', {
      'event_id': 'e2e-evt-1',
      'title': 'AI title',
    });
    final deviceCall = d.push([
      {
        'opId': 'e2e-evt-dev-2',
        'op': 'upsert',
        'recordId': 'e2e-evt-1',
        'type': 'event',
        'baseRev': 1,
        'fields': {
          'description': 'device description',
          'updatedAt': _iso(DateTime.now().toUtc()),
        },
      },
    ]);
    final results = await Future.wait([aiCall, deviceCall]);
    final aiData = results[0];
    expect((aiData['event'] as Map)['title'], 'AI title');

    // Explicit device pull round catches anything the concurrent push's
    // piggyback watermark could not have seen.
    await d.pull();
    final onDevice = d.records['e2e-evt-1']!;
    expect(onDevice['rev'], 3, reason: 'create + 2 edits = rev 3');
    final devicePayload = onDevice['payload'] as Map;
    expect(devicePayload['summary'], 'AI title', reason: 'AI write survives');
    expect(devicePayload['description'], 'device description',
        reason: 'device write survives');
    expect(devicePayload['startDt'], _iso(start),
        reason: 'untouched time fields keep the original value');

    final aiView = await _tool(api, aiToken, 'get_event', {
      'event_id': 'e2e-evt-1',
    });
    final aiEvent = aiView['event'] as Map;
    expect(aiEvent['title'], 'AI title');
    expect(aiEvent['description'], 'device description',
        reason: 'AI side sees the merged truth too');

    final empty = await d.pull();
    expect(empty, isEmpty, reason: 'both sides converged, no leftover tail');
  });

  test(
      '④ OAuth full chain live: DCR → PKCE authorize with creds → code → '
      'token → tools/call → refresh → tools/call', () async {
    final flow = await _authorizeCode(api, email: email);
    final tokens = await _redeem(
      api,
      code: flow.code,
      clientId: flow.clientId,
      clientSecret: flow.clientSecret,
      verifier: flow.verifier,
    );
    expect(tokens['token_type'], 'Bearer');
    expect(tokens['expires_in'], 900);
    expect(tokens['scope'], 'mcp:read mcp:write');
    final oauthToken = tokens['access_token'] as String;

    final list = await _rpc(api, oauthToken, 'tools/list');
    expect((list['tools'] as List), isNotEmpty);

    final start = DateTime.now().toUtc().add(const Duration(hours: 6));
    final data = await _tool(api, oauthToken, 'create_event', {
      'title': 'OAuth live event',
      'start': _iso(start),
      'end': _iso(start.add(const Duration(hours: 1))),
    });
    final id = (data['event'] as Map)['event_id'] as String;

    // Two-track same user: the login-token device pull sees the
    // OAuth-track write without any extra handshake.
    final d = await device();
    final changes = await d.pull();
    expect(changes.map((c) => c['id']), contains(id));
    expect(
      (changes.firstWhere((c) => c['id'] == id)['payload'] as Map)['summary'],
      'OAuth live event',
    );

    final basic = base64.encode(utf8.encode('${flow.clientId}:${flow.clientSecret}'));
    final refresh = await api.send(
      'POST',
      '/oauth/token',
      form: {
        'grant_type': 'refresh_token',
        'refresh_token': tokens['refresh_token'] as String,
      },
      headers: {'authorization': 'Basic $basic'},
    );
    expect(refresh.status, 200, reason: refresh.text);
    final rotated = jsonDecode(refresh.text) as Map<String, dynamic>;
    expect(rotated['access_token'], isA<String>());
    expect(rotated['refresh_token'], isNot(tokens['refresh_token']));
    final refreshedToken = rotated['access_token'] as String;

    final again = await _tool(api, refreshedToken, 'create_event', {
      'title': 'After refresh',
      'start': _iso(start.add(const Duration(days: 1))),
      'end': _iso(start.add(const Duration(days: 1, hours: 1))),
    });
    expect((again['event'] as Map)['title'], 'After refresh');
  });

  test(
      '⑤ scope demotion: read-only token create_* → FORBIDDEN_SCOPE, '
      'resources/read still allowed', () async {
    final flow = await _authorizeCode(api, email: email, scope: 'mcp:read');
    final tokens = await _redeem(
      api,
      code: flow.code,
      clientId: flow.clientId,
      clientSecret: flow.clientSecret,
      verifier: flow.verifier,
    );
    final readOnly = tokens['access_token'] as String;
    expect(tokens['scope'], 'mcp:read');

    final start = DateTime.now().toUtc().add(const Duration(hours: 2));
    final deniedEvent = await _toolErr(api, readOnly, 'create_event', {
      'title': 'Should be refused',
      'start': _iso(start),
      'end': _iso(start.add(const Duration(hours: 1))),
    });
    expect(deniedEvent['code'], 'FORBIDDEN_SCOPE');
    expect(deniedEvent['hint'], contains('mcp:write'));

    final deniedTask = await _toolErr(api, readOnly, 'create_task', {
      'title': 'Should also be refused',
    });
    expect(deniedTask['code'], 'FORBIDDEN_SCOPE');

    final read = await _tool(api, readOnly, 'list_tasks', {});
    expect(read['tasks'], isA<List>());

    final resource = await _rpc(
      api,
      readOnly,
      'resources/read',
      params: {'uri': 'dayspark://today'},
    );
    // _rpc already unwraps the JSON-RPC result envelope (and asserts
    // error is null).
    expect(resource['contents'], isNotNull);

    // No write sneaked past the gate: a login-token device pull for the
    // same user sees zero records. (The OAuth bearer itself is refused on
    // /sync/* by the two-track split — covered in oauth_test.)
    final d = await device();
    final changes = await d.pull();
    expect(changes, isEmpty, reason: 'scope gate wrote nothing');
  });
}
