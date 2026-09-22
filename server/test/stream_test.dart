import 'dart:async';
import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

Future<Response> _request(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
}) async {
  return await handler(
    Request(
      method,
      _uri(path),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
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

Future<void> _push(
  AppServer app,
  String token, {
  required String opId,
  required String recordId,
  String title = 'hello',
}) async {
  final response = await _request(app.handler, 'POST', '/sync/push', token: token, body: {
    'deviceId': 'device-1',
    'ops': [
      {
        'opId': opId,
        'op': 'upsert',
        'recordId': recordId,
        'type': 'todo',
        'fields': {'title': title},
      },
    ],
  });
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
}

Future<Response> _openStream(AppServer app, String token) async {
  final response = await _request(app.handler, 'GET', '/sync/stream', token: token);
  expect(response.statusCode, 200, reason: 'stream must open');
  return response;
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _SseFeed {
  _SseFeed(Response response) {
    _subscription = response.read().listen((chunk) {
      _buffer.write(utf8.decode(chunk));
    }, onError: (Object error) {
      _error = error;
    });
  }

  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<List<int>>? _subscription;
  Object? _error;

  String get raw => _buffer.toString();

  Iterable<String> get dataPayloads {
    final text = raw;
    final lastFrameEnd = text.lastIndexOf('\n\n');
    if (lastFrameEnd < 0) {
      return const <String>[];
    }
    return text
        .substring(0, lastFrameEnd)
        .split('\n\n')
        .where((frame) => frame.startsWith('data:'))
        .map((frame) => frame.substring('data:'.length).trim());
  }

  Future<void> waitForData(String payload, {Duration timeout = const Duration(seconds: 2)}) {
    return waitFor((text) => text.contains('data: $payload\n\n'), timeout: timeout);
  }

  Future<void> waitForPing({Duration timeout = const Duration(seconds: 2)}) {
    return waitFor((text) => text.contains(': ping\n\n'), timeout: timeout);
  }

  Future<void> waitFor(
    bool Function(String raw) condition, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition(raw)) {
      if (_error != null) {
        fail('stream failed: $_error');
      }
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'timed out waiting on stream; received: '
          '${raw.replaceAll('\n', r'\n')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
  }
}

void main() {
  late AppServer app;

  setUp(() {
    app = AppServer(
      Config(
        dbPath: ':memory:',
        port: 0,
        jwtSecret: 'test-secret',
        sseHeartbeat: const Duration(milliseconds: 40),
      ),
    );
  });

  tearDown(() async {
    await app.close();
  });

  test('default heartbeat interval is 25 seconds', () {
    const config = Config(dbPath: ':memory:', port: 0, jwtSecret: 'x');
    expect(config.sseHeartbeat, const Duration(seconds: 25));
  });

  test('stream opens with SSE headers and emits current head cursor first', () async {
    final token = (await _register(app, 'head@example.com'))['token']!;
    await _push(app, token, opId: 'op-head-1', recordId: 'rec-head-1');

    final response = await _openStream(app, token);
    expect(response.headers['content-type'], 'text/event-stream');
    expect(response.headers['cache-control'], 'no-cache');
    expect(response.headers['connection'], 'keep-alive');

    final feed = _SseFeed(response);
    await feed.waitForData('{"cursor":1}');
    expect(feed.dataPayloads.first, '{"cursor":1}');
    await feed.cancel();
  });

  test(
      'push delivers cursor-only frames to every connection of that user, no records',
      () async {
    final account = await _register(app, 'signal@example.com');
    final token = account['token']!;
    final userId = account['userId']!;

    final feedA = _SseFeed(await _openStream(app, token));
    final feedB = _SseFeed(await _openStream(app, token));
    await feedA.waitForData('{"cursor":0}');
    await feedB.waitForData('{"cursor":0}');
    expect(app.streamHub.connectionsFor(userId), 2);

    await _push(app, token, opId: 'op-sig-1', recordId: 'rec-sig-1', title: 'secret-title');

    await feedA.waitForData('{"cursor":1}');
    await feedB.waitForData('{"cursor":1}');

    for (final feed in [feedA, feedB]) {
      for (final payload in feed.dataPayloads) {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        expect(decoded.keys.toList(), ['cursor'], reason: 'payload must be cursor-only: $payload');
        expect(decoded['cursor'], isA<int>());
      }
      expect(feed.raw, isNot(contains('rec-sig-1')));
      expect(feed.raw, isNot(contains('secret-title')));
      expect(feed.raw, isNot(contains('serverRecord')));
      expect(feed.raw, isNot(contains('piggyback')));
      await feed.cancel();
    }
  });

  test('heartbeat ping comment arrives at the injected interval', () async {
    final token = (await _register(app, 'ping@example.com'))['token']!;
    final feed = _SseFeed(await _openStream(app, token));
    await feed.waitForData('{"cursor":0}');
    await feed.waitForPing();
    expect(feed.raw, contains(': ping'));
    expect(feed.dataPayloads, everyElement(startsWith('{')));
    await feed.cancel();
  });

  test('disconnect removes the connection from the registry', () async {
    final account = await _register(app, 'bye@example.com');
    final userId = account['userId']!;
    final feed = _SseFeed(await _openStream(app, account['token']!));
    await feed.waitForData('{"cursor":0}');
    expect(app.streamHub.connectionsFor(userId), 1);
    expect(app.streamHub.totalConnections, 1);

    await feed.cancel();
    await _waitUntil(
      () => app.streamHub.connectionsFor(userId) == 0 &&
          app.streamHub.totalConnections == 0,
      description: 'registry entry removed after disconnect',
    );
  });

  test("other user's push never signals this user's stream", () async {
    final alice = await _register(app, 'iso-alice@example.com');
    final bob = await _register(app, 'iso-bob@example.com');

    final aliceFeed = _SseFeed(await _openStream(app, alice['token']!));
    final bobFeed = _SseFeed(await _openStream(app, bob['token']!));
    await aliceFeed.waitForData('{"cursor":0}');
    await bobFeed.waitForData('{"cursor":0}');

    await _push(app, bob['token']!, opId: 'op-iso-bob', recordId: 'rec-iso-bob');
    await bobFeed.waitForData('{"cursor":1}');
    // Bob's signal has already landed; give any (wrongly) shared broadcast a
    // chance to arrive at Alice before asserting isolation.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(aliceFeed.dataPayloads.toList(), ['{"cursor":0}']);
    expect(bobFeed.dataPayloads.toList(), ['{"cursor":0}', '{"cursor":1}']);
    await aliceFeed.cancel();
    await bobFeed.cancel();
  });

  test('stream without valid token gets 401 envelope, no open stream', () async {
    final anonymous = await _request(app.handler, 'GET', '/sync/stream');
    expect(anonymous.statusCode, 401);
    final body = await _json(anonymous);
    final error = body['error'] as Map<String, dynamic>;
    expect(error['code'], errUnauthorized);
    expect(anonymous.headers['content-type'], contains('json'));

    final garbage = await _request(
      app.handler,
      'GET',
      '/sync/stream',
      token: 'not-a-token',
    );
    expect(garbage.statusCode, 401);
    expect((await _json(garbage))['error'], isNotNull);

    expect(app.streamHub.totalConnections, 0);
  });
}
