import 'dart:async';
import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

String iso(DateTime dt) => dt.toUtc().toIso8601String();

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

Future<Map<String, dynamic>> _callTool(
  AppServer app,
  String token,
  String name,
  Map<String, Object?> args,
) async {
  final response = await _request(
    app.handler,
    'POST',
    '/mcp',
    token: token,
    body: {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    },
  );
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  final body = jsonDecode(text) as Map<String, dynamic>;
  expect(body['error'], isNull, reason: text);
  return body['result'] as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _toolData(
  AppServer app,
  String token,
  String name,
  Map<String, Object?> args,
) async {
  final result = await _callTool(app, token, name, args);
  expect(result['isError'], isNot(true),
      reason: '${result['content']}');
  final text = (result['content'] as List).first['text'] as String;
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _toolError(
  AppServer app,
  String token,
  String name,
  Map<String, Object?> args,
) async {
  final result = await _callTool(app, token, name, args);
  expect(result['isError'], true,
      reason: 'expected isError for $name ${result['content']}');
  final text = (result['content'] as List).first['text'] as String;
  final payload = jsonDecode(text) as Map<String, dynamic>;
  expect(payload['code'], isA<String>(), reason: text);
  expect(payload['message'], isA<String>(), reason: text);
  expect(payload['hint'], isA<String>(), reason: text);
  expect((payload['hint'] as String).isNotEmpty, isTrue, reason: text);
  expect((result['content'] as List).first['type'], 'text');
  return payload;
}

Future<void> _seed(
  AppServer app,
  String userId,
  String id, {
  required RecordType type,
  required Map<String, Object?> fields,
  int? baseRev,
}) async {
  final result = await applyInternalOp(
    db: app.db,
    userId: userId,
    op: PushOp(
      opId: 'seed-$id-${baseRev ?? 0}',
      op: OpType.upsert,
      recordId: id,
      type: type,
      fields: fields,
      baseRev: baseRev,
    ),
    notify: (userId, seq) {},
  );
  expect(result.status, OpStatus.applied,
      reason: 'seed $id must apply: ${result.code}');
}

Future<RecordRow?> _row(AppServer app, String userId, String id) {
  return (app.db.select(app.db.records)
        ..where((t) => t.userId.equals(userId) & t.id.equals(id)))
      .getSingleOrNull();
}

Future<List<String>> _liveIds(
  AppDatabase db, {
  required String userId,
  RecordType? type,
  bool trashedOnly = false,
}) async {
  final page = await queryRecords(
    db,
    userId: userId,
    type: type,
    trashedOnly: trashedOnly,
    limit: recordQueryMaxLimit,
  );
  return page.records.map((r) => r.id).toList();
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

  Future<void> waitForData(
    String payload, {
    Duration timeout = const Duration(seconds: 2),
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

void main() {
  late AppServer app;
  late String token;
  late String userId;

  setUp(() async {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
    final account = await _register(app, 'mcp-tools@example.com');
    token = account['token']!;
    userId = account['userId']!;
  });

  tearDown(() async {
    await app.close();
  });

  DateTime now() => DateTime.now().toUtc();

  group('get_events', () {
    test('returns window instances with rrule expansion and skips out-of-window rows',
        () async {
      final start = now().add(const Duration(hours: 2));
      await _seed(
        app,
        userId,
        'ev-standup',
        type: RecordType.event,
        fields: {
          'summary': 'Standup',
          'description': 'daily sync',
          'startDt': iso(start),
          'endDt': iso(start.add(const Duration(hours: 1))),
          'isAllDay': false,
          'location': null,
          'rrule': null,
          'deletedAt': null,
        },
      );
      await _seed(
        app,
        userId,
        'ev-old',
        type: RecordType.event,
        fields: {
          'summary': 'Ancient',
          'startDt': iso(now().subtract(const Duration(days: 40))),
          'endDt': iso(now().subtract(const Duration(days: 40, hours: -1))),
          'isAllDay': false,
          'rrule': null,
          'deletedAt': null,
        },
      );
      final dailyStart = now().add(const Duration(days: 1));
      await _seed(
        app,
        userId,
        'ev-daily',
        type: RecordType.event,
        fields: {
          'summary': 'Daily stretch',
          'startDt': iso(dailyStart),
          'endDt': iso(dailyStart.add(const Duration(minutes: 30))),
          'isAllDay': false,
          'rrule': 'RRULE:FREQ=DAILY',
          'deletedAt': null,
        },
      );

      final data = await _toolData(
        app,
        token,
        'get_events',
        {
          'from': iso(now()),
          'to': iso(now().add(const Duration(days: 7))),
          'limit': 50,
        },
      );
      final events = data['events'] as List;
      final ids = events.map((e) => e['event_id'] as String).toSet();
      expect(ids, contains('ev-standup'));
      expect(ids, contains('ev-daily'));
      expect(ids, isNot(contains('ev-old')));
      expect(events.length, greaterThanOrEqualTo(7),
          reason: 'daily series expands inside a 7-day window');
      final daily = events
          .where((e) => e['event_id'] == 'ev-daily')
          .toList();
      expect(daily.length, greaterThanOrEqualTo(6));
      final first = daily.first as Map<String, dynamic>;
      expect(first['title'], 'Daily stretch');
      expect(first['start'], matches(RegExp(r'\.\d{6}Z$')));
      expect(data['window'], isA<Map>());

      final starts = daily
          .map((e) => DateTime.parse(e['start'] as String))
          .toList();
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]),
          const Duration(days: 1),
          reason: 'DAILY expansion is one instance per day',
        );
      }
    });

    test('rejects a naive datetime with a timezone hint', () async {
      final payload = await _toolError(app, token, 'get_events', {
        'from': '2026-09-23T10:00:00',
        'to': '2026-09-30T10:00:00',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('timezone offset or Z'));
    });

    test('rejects windows longer than 366 days with WINDOW_TOO_LARGE', () async {
      final payload = await _toolError(app, token, 'get_events', {
        'from': iso(now()),
        'to': iso(now().add(const Duration(days: 400))),
      });
      expect(payload['code'], 'WINDOW_TOO_LARGE');
      expect(payload['hint'], contains('366'));
    });

    test('WINDOW_TOO_LARGE hint narrows the window without promising '
        'cursor paging', () async {
      final payload = await _toolError(app, token, 'get_events', {
        'from': iso(now()),
        'to': iso(now().add(const Duration(days: 400))),
      });
      expect(payload['hint'], contains('Narrow the window'));
      expect(payload['hint'], contains('lower the limit'));
      expect(payload['hint'], isNot(contains('cursor')));
    });

    test('rejects an invalid IANA timezone', () async {
      final payload = await _toolError(app, token, 'get_events', {
        'timezone': 'Mars/Olympus_Mons',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('IANA'));
    });
  });

  group('get_event', () {
    test('returns a single event', () async {
      await _seed(
        app,
        userId,
        'ev-one',
        type: RecordType.event,
        fields: {
          'summary': 'Dentist',
          'startDt': iso(now().add(const Duration(days: 1))),
          'endDt': iso(now().add(const Duration(days: 1, hours: 1))),
          'isAllDay': false,
          'rrule': null,
          'deletedAt': null,
        },
      );
      final data = await _toolData(
        app,
        token,
        'get_event',
        {'event_id': 'ev-one'},
      );
      final event = data['event'] as Map<String, dynamic>;
      expect(event['event_id'], 'ev-one');
      expect(event['title'], 'Dentist');
      expect(event['trashed'], false);
      expect(event['start'], matches(RegExp(r'Z$')));
    });

    test('missing event reports EVENT_NOT_FOUND steering to get_events', () async {
      final payload = await _toolError(
        app,
        token,
        'get_event',
        {'event_id': 'nope'},
      );
      expect(payload['code'], 'EVENT_NOT_FOUND');
      expect(payload['hint'], contains('get_events'));
    });
  });

  group('list_tasks', () {
    test('filter=today returns only tasks due today (UTC day bucket)', () async {
      await _seed(
        app,
        userId,
        'td-today',
        type: RecordType.todo,
        fields: {
          'summary': 'due now',
          'dueDate': iso(now()),
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'deletedAt': null,
        },
      );
      await _seed(
        app,
        userId,
        'td-later',
        type: RecordType.todo,
        fields: {
          'summary': 'due later',
          'dueDate': iso(now().add(const Duration(hours: 36))),
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'deletedAt': null,
        },
      );
      await _seed(
        app,
        userId,
        'td-nodue',
        type: RecordType.todo,
        fields: {
          'summary': 'no due',
          'dueDate': null,
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'deletedAt': null,
        },
      );

      final data = await _toolData(
        app,
        token,
        'list_tasks',
        {'filter': 'today'},
      );
      final tasks = data['tasks'] as List;
      expect(tasks.map((t) => t['task_id']), ['td-today']);
      expect(data['has_more'], false);
      expect(data['next_cursor'], isNull);
    });

    test('filter=inbox returns only tasks without a due date', () async {
      await _seed(
        app,
        userId,
        'td-inbox',
        type: RecordType.todo,
        fields: {
          'summary': 'floating',
          'dueDate': null,
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
        },
      );
      await _seed(
        app,
        userId,
        'td-dated',
        type: RecordType.todo,
        fields: {
          'summary': 'dated',
          'dueDate': iso(now().add(const Duration(days: 2))),
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
        },
      );
      final data = await _toolData(
        app,
        token,
        'list_tasks',
        {'filter': 'inbox', 'status': 'open'},
      );
      expect(
        (data['tasks'] as List).map((t) => t['task_id']),
        ['td-inbox'],
      );
    });

    test('rejects an unknown status filter value with a hint', () async {
      final payload = await _toolError(app, token, 'list_tasks', {
        'status': 'wandering',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], isNotEmpty);
    });
  });

  group('get_task', () {
    test('returns a single task', () async {
      await _seed(
        app,
        userId,
        'td-one',
        type: RecordType.todo,
        fields: {
          'summary': 'Buy milk',
          'dueDate': iso(now().add(const Duration(hours: 3))),
          'priority': 2,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'deletedAt': null,
        },
      );
      final data =
          await _toolData(app, token, 'get_task', {'task_id': 'td-one'});
      final task = data['task'] as Map<String, dynamic>;
      expect(task['task_id'], 'td-one');
      expect(task['title'], 'Buy milk');
      expect(task['priority'], 2);
      expect(task['due'], matches(RegExp(r'Z$')));
    });

    test('missing task reports TASK_NOT_FOUND steering to list_tasks', () async {
      final payload = await _toolError(
        app,
        token,
        'get_task',
        {'task_id': 'ghost'},
      );
      expect(payload['code'], 'TASK_NOT_FOUND');
      expect(payload['hint'], contains('list_tasks'));
    });
  });

  group('search', () {
    test('matches summaries across kinds with a kind filter', () async {
      await _seed(
        app,
        userId,
        'ev-dentist',
        type: RecordType.event,
        fields: {
          'summary': 'Dentist visit',
          'startDt': iso(now().add(const Duration(days: 3))),
          'endDt': iso(now().add(const Duration(days: 3, hours: 1))),
          'isAllDay': false,
          'rrule': null,
          'deletedAt': null,
        },
      );
      await _seed(
        app,
        userId,
        'td-dentist',
        type: RecordType.todo,
        fields: {
          'summary': 'dentist follow-up',
          'dueDate': null,
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
        },
      );

      final all = await _toolData(
        app,
        token,
        'search',
        {'query': 'dentist'},
      );
      expect((all['results'] as List).length, 2);

      final eventsOnly = await _toolData(
        app,
        token,
        'search',
        {'query': 'dentist', 'kind': 'event'},
      );
      final results = eventsOnly['results'] as List;
      expect(results, hasLength(1));
      expect(results.first['kind'], 'event');
      expect(results.first['event_id'], 'ev-dentist');
      expect(results.first['title'], 'Dentist visit');
    });

    test('rejects an empty query', () async {
      final payload =
          await _toolError(app, token, 'search', {'query': '   '});
      expect(payload['code'], 'VALIDATION');
      expect(payload['message'], contains('query'));
    });
  });

  group('find_free_time', () {
    test('returns slots inside working hours that avoid busy events', () async {
      final busyStart = now();
      final busyEnd = busyStart.add(const Duration(minutes: 30));
      await _seed(
        app,
        userId,
        'ev-busy',
        type: RecordType.event,
        fields: {
          'summary': 'Busy block',
          'startDt': iso(busyStart),
          'endDt': iso(busyEnd),
          'isAllDay': false,
          'rrule': null,
          'deletedAt': null,
        },
      );

      final data = await _toolData(app, token, 'find_free_time', {
        'from': iso(now()),
        'to': iso(now().add(const Duration(days: 2))),
        'duration_minutes': 60,
        'timezone': 'Asia/Shanghai',
        'working_hours_start': '09:00',
        'working_hours_end': '18:00',
        'working_days': ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'],
      });
      final slots = data['slots'] as List;
      expect(slots, isNotEmpty);
      expect(slots.length, lessThanOrEqualTo(10));

      for (final raw in slots) {
        final slot = raw as Map<String, dynamic>;
        final start = DateTime.parse(slot['start'] as String);
        final end = DateTime.parse(slot['end'] as String);
        expect(end.difference(start), const Duration(minutes: 60));
        expect(start.isBefore(end), isTrue);
        final overlapsBusy =
            start.isBefore(busyEnd) && end.isAfter(busyStart);
        expect(overlapsBusy, isFalse, reason: 'slot must avoid busy events');
      }
      final starts = slots
          .map((s) => DateTime.parse((s as Map)['start'] as String))
          .toList();
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i].isAfter(starts[i - 1]), isTrue,
            reason: 'slots are earliest-first and non-decreasing');
      }
      expect(data['timezone'], 'Asia/Shanghai');
    });

    test('rejects a duration longer than the window', () async {
      final payload = await _toolError(app, token, 'find_free_time', {
        'from': iso(now()),
        'to': iso(now().add(const Duration(hours: 2))),
        'duration_minutes': 0,
        'timezone': 'UTC',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['message'], contains('duration_minutes'));
    });

    test('rejects an invalid timezone', () async {
      final payload = await _toolError(app, token, 'find_free_time', {
        'from': iso(now()),
        'to': iso(now().add(const Duration(days: 1))),
        'duration_minutes': 30,
        'timezone': 'Not/A_Zone',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('IANA'));
    });
  });

  group('list_trash', () {
    test('lists soft-trashed and tombstoned records but not live ones', () async {
      await _seed(
        app,
        userId,
        'td-live',
        type: RecordType.todo,
        fields: {'summary': 'live', 'status': 'NEEDS-ACTION'},
      );
      await _seed(
        app,
        userId,
        'td-soft',
        type: RecordType.todo,
        fields: {
          'summary': 'soft trashed',
          'status': 'NEEDS-ACTION',
          'deletedAt': iso(now().subtract(const Duration(hours: 1))),
        },
      );
      await _seed(
        app,
        userId,
        'ev-tomb',
        type: RecordType.event,
        fields: {
          'summary': 'tombstoned',
          'startDt': iso(now()),
          'endDt': iso(now().add(const Duration(hours: 1))),
          'isAllDay': false,
          'deletedAt': iso(now().subtract(const Duration(hours: 2))),
        },
      );
      final tombRow = await _row(app, userId, 'ev-tomb');
      await (app.db.update(app.db.records)
            ..where((t) =>
                t.userId.equals(userId) & t.id.equals('ev-tomb')))
          .write(tombRow!.copyWith(deleted: true));

      final all = await _toolData(app, token, 'list_trash', {});
      final items = all['items'] as List;
      expect(
        items.map((i) => i['id']).toSet(),
        {'td-soft', 'ev-tomb'},
      );
      final soft = items.firstWhere((i) => i['id'] == 'td-soft') as Map;
      expect(soft['trashed'], true);
      expect(soft['trashed_at'], matches(RegExp(r'Z$')));

      final eventsOnly = await _toolData(
        app,
        token,
        'list_trash',
        {'kind': 'event'},
      );
      expect(
        (eventsOnly['items'] as List).map((i) => i['id']),
        ['ev-tomb'],
      );
    });

    test('rejects an unknown kind', () async {
      final payload = await _toolError(app, token, 'list_trash', {
        'kind': 'attachment',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], isNotEmpty);
    });
  });

  group('create_event', () {
    test('creates a canonical record readable by queryRecords', () async {
      final start = now().add(const Duration(hours: 2));
      final data = await _toolData(app, token, 'create_event', {
        'title': 'AI sync',
        'start': iso(start),
        'end': iso(start.add(const Duration(hours: 1))),
        'timezone': 'Asia/Shanghai',
        'description': 'created by AI',
        'location': 'Room 42',
      });
      final event = data['event'] as Map<String, dynamic>;
      final id = event['event_id'] as String;
      expect(id, isNotEmpty);
      expect(event['title'], 'AI sync');
      expect(event['start'], matches(RegExp(r'\.\d{6}Z$')));
      expect(data['op'], isA<Map>());
      expect((data['op'] as Map)['status'], 'applied');

      final page = await queryRecords(
        app.db,
        userId: userId,
        type: RecordType.event,
      );
      final row = page.records.singleWhere((r) => r.id == id);
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['summary'], 'AI sync');
      expect(payload['location'], 'Room 42');
      expect(payload['startDt'], matches(RegExp(r'\.\d{6}Z$')));
      expect(payload['endDt'], matches(RegExp(r'\.\d{6}Z$')));
      expect(payload['deletedAt'], isNull);
    });

    test('rejects a naive start datetime at the boundary', () async {
      final payload = await _toolError(app, token, 'create_event', {
        'title': 'Naive',
        'start': '2026-09-23T10:00:00',
        'end': '2026-09-23T11:00:00',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('timezone offset or Z'));
    });

    test('rejects end before start', () async {
      final payload = await _toolError(app, token, 'create_event', {
        'title': 'Backwards',
        'start': iso(now().add(const Duration(hours: 2))),
        'end': iso(now().add(const Duration(hours: 1))),
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['message'], contains('end'));
    });

    test('rejects a bare RRULE string and asks for a structured object', () async {
      final payload = await _toolError(app, token, 'create_event', {
        'title': 'Recurring',
        'start': iso(now().add(const Duration(hours: 1))),
        'end': iso(now().add(const Duration(hours: 2))),
        'recurrence': 'FREQ=WEEKLY',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('structured'));
    });
  });

  test('AI create_event is visible to device pull and notifies the SSE hub',
      () async {
    final feedResponse = await _request(
      app.handler,
      'GET',
      '/sync/stream',
      token: token,
    );
    expect(feedResponse.statusCode, 200, reason: 'stream must open');
    final feed = _SseFeed(feedResponse);
    await feed.waitForData('{"cursor":0}');

    final start = now().add(const Duration(hours: 5));
    final data = await _toolData(app, token, 'create_event', {
      'title': 'Visible event',
      'start': iso(start),
      'end': iso(start.add(const Duration(hours: 1))),
    });
    final id = (data['event'] as Map)['event_id'] as String;

    await feed.waitForData('{"cursor":1}');

    final pullResponse = await _request(
      app.handler,
      'GET',
      '/sync/pull?cursor=0',
      token: token,
    );
    final pull = await _json(pullResponse);
    final changes = pull['changes'] as List;
    expect(changes, hasLength(1));
    final change = changes.first as Map<String, dynamic>;
    expect(change['id'], id);
    expect(change['payload']['summary'], 'Visible event');

    final page = await queryRecords(app.db, userId: userId);
    expect(page.records.map((r) => r.id), contains(id));
    await feed.cancel();
  });

  test('structured recurrence round-trips through the RFC payload and expands',
      () async {
    final start = now().add(const Duration(days: 2));
    final created = await _toolData(app, token, 'create_event', {
      'title': 'Weekly review',
      'start': iso(start),
      'end': iso(start.add(const Duration(hours: 1))),
      'recurrence': {
        'freq': 'WEEKLY',
        'interval': 1,
        'until': iso(now().add(const Duration(days: 30))),
      },
    });
    final id = (created['event'] as Map)['event_id'] as String;

    final row = await _row(app, userId, id);
    final payload = jsonDecode(row!.payloadJson) as Map<String, dynamic>;
    final rruleString = payload['rrule'] as String;
    expect(rruleString, contains('FREQ=WEEKLY'));
    expect(rruleString, contains('INTERVAL=1'));

    final parsed = parseRruleStructured(
      {
        'freq': 'WEEKLY',
        'interval': 1,
        'until': iso(now().add(const Duration(days: 30))),
      },
      'recurrence',
    );
    expect(parsed, rruleString,
        reason: 'structured object must serialize deterministically');

    final events = await _toolData(app, token, 'get_events', {
      'from': iso(now()),
      'to': iso(now().add(const Duration(days: 30))),
      'limit': 200,
    });
    final instances = (events['events'] as List)
        .where((e) => e['event_id'] == id)
        .toList();
    expect(instances.length, greaterThanOrEqualTo(2),
        reason: 'weekly rule expands inside the window');
    final starts = instances
        .map((e) => DateTime.parse((e as Map)['start'] as String))
        .toList();
    for (var i = 1; i < starts.length; i++) {
      expect(
        starts[i].difference(starts[i - 1]),
        const Duration(days: 7),
        reason: 'WEEKLY interval 1 steps by seven days',
      );
    }
  });

  group('update_event', () {
    test('PATCH only the provided fields', () async {
      await _seed(
        app,
        userId,
        'ev-patch',
        type: RecordType.event,
        fields: {
          'summary': 'Keep me',
          'description': null,
          'location': null,
          'startDt': iso(now().add(const Duration(days: 1))),
          'endDt': iso(now().add(const Duration(days: 1, hours: 1))),
          'isAllDay': false,
          'rrule': null,
          'deletedAt': null,
        },
      );
      final data = await _toolData(app, token, 'update_event', {
        'event_id': 'ev-patch',
        'description': 'patched',
      });
      final event = data['event'] as Map<String, dynamic>;
      expect(event['title'], 'Keep me');
      expect(event['description'], 'patched');
      expect(event['start'], matches(RegExp(r'Z$')));

      final row = await _row(app, userId, 'ev-patch');
      expect(row!.rev, 2);
    });

    test('missing event reports EVENT_NOT_FOUND', () async {
      final payload = await _toolError(app, token, 'update_event', {
        'event_id': 'missing-event',
        'title': 'x',
      });
      expect(payload['code'], 'EVENT_NOT_FOUND');
      expect(payload['hint'], contains('get_events'));
    });
  });

  group('trash_event', () {
    test('soft-deletes via payload deletedAt, not a tombstone', () async {
      await _seed(
        app,
        userId,
        'ev-trash-me',
        type: RecordType.event,
        fields: {
          'summary': 'Bye',
          'startDt': iso(now().add(const Duration(days: 4))),
          'endDt': iso(now().add(const Duration(days: 4, hours: 1))),
          'isAllDay': false,
          'rrule': null,
          'deletedAt': null,
        },
      );
      final data = await _toolData(
        app,
        token,
        'trash_event',
        {'event_id': 'ev-trash-me'},
      );
      expect((data['event'] as Map)['trashed'], isTrue);
      expect(data['trashed'], true);

      final live = await _liveIds(app.db, userId: userId);
      expect(live, isNot(contains('ev-trash-me')));
      final trashed =
          await _liveIds(app.db, userId: userId, trashedOnly: true);
      expect(trashed, contains('ev-trash-me'));

      final row = await _row(app, userId, 'ev-trash-me');
      expect(row!.deleted, isFalse,
          reason: 'trash is soft (deletedAt), not a device tombstone');
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['deletedAt'], matches(RegExp(r'Z$')));
      expect(payload['summary'], 'Bye',
          reason: 'payload body survives for recycle-bin restore');
    });

    test('missing event reports EVENT_NOT_FOUND', () async {
      final payload = await _toolError(
        app,
        token,
        'trash_event',
        {'event_id': 'absent'},
      );
      expect(payload['code'], 'EVENT_NOT_FOUND');
      expect(payload['hint'], isNotEmpty);
    });
  });

  group('create_task', () {
    test('creates a task with due, priority and tags', () async {
      final due = now().add(const Duration(hours: 4));
      final data = await _toolData(app, token, 'create_task', {
        'title': 'AI task',
        'due': iso(due),
        'priority': 3,
        'description': 'from MCP',
        'tags': ['home', 'ai'],
      });
      final task = data['task'] as Map<String, dynamic>;
      final id = task['task_id'] as String;
      expect(task['title'], 'AI task');
      expect(task['priority'], 3);
      expect(task['tags'], ['home', 'ai']);

      final row = await _row(app, userId, id);
      final payload = jsonDecode(row!.payloadJson) as Map<String, dynamic>;
      expect(payload['status'], 'NEEDS-ACTION');
      expect(payload['percentComplete'], 0);
      expect(payload['dueDate'], matches(RegExp(r'\.\d{6}Z$')));
      expect(payload['tags'], ['home', 'ai']);
      expect(payload['completedAt'], isNull);
    });

    test('rejects a naive due datetime', () async {
      final payload = await _toolError(app, token, 'create_task', {
        'title': 'Naive due',
        'due': '2026-09-23 10:00:00',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('timezone offset or Z'));
    });

    test('rejects an empty title', () async {
      final payload =
          await _toolError(app, token, 'create_task', {'title': '   '});
      expect(payload['code'], 'VALIDATION');
      expect(payload['message'], contains('title'));
    });
  });

  group('idempotency_key', () {
    test('same key with the same body replays the original result', () async {
      final args = <String, Object?>{
        'title': 'Idempotent',
        'due': iso(now().add(const Duration(days: 1))),
        'idempotency_key': 'ai-key-1',
      };
      final first = await _toolData(app, token, 'create_task', args);
      final second = await _toolData(app, token, 'create_task', args);

      final firstTask = first['task'] as Map<String, dynamic>;
      final secondTask = second['task'] as Map<String, dynamic>;
      expect(secondTask['task_id'], firstTask['task_id']);
      expect(secondTask, firstTask);
      expect((second['op'] as Map)['rev'], (first['op'] as Map)['rev']);

      final page = await queryRecords(
        app.db,
        userId: userId,
        type: RecordType.todo,
      );
      expect(page.records, hasLength(1),
          reason: 'replay must not create a second record');
    });

    test('same key with a different body is rejected as VALIDATION', () async {
      final first = await _toolData(app, token, 'create_task', {
        'title': 'Original',
        'idempotency_key': 'ai-key-2',
      });
      final payload = await _toolError(app, token, 'create_task', {
        'title': 'Different',
        'idempotency_key': 'ai-key-2',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['message'], contains('idempotency_key'));
      expect(payload['hint'], contains('idempotency_key'));

      final page = await queryRecords(
        app.db,
        userId: userId,
        type: RecordType.todo,
      );
      expect(page.records, hasLength(1),
          reason: 'the conflicting call must not write');
      expect(
        (first['task'] as Map)['title'],
        'Original',
      );
    });
  });

  group('update_task', () {
    test('PATCH only the provided fields', () async {
      await _seed(
        app,
        userId,
        'td-patch',
        type: RecordType.todo,
        fields: {
          'summary': 'Original title',
          'dueDate': null,
          'priority': 1,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'deletedAt': null,
        },
      );
      final data = await _toolData(app, token, 'update_task', {
        'task_id': 'td-patch',
        'priority': 5,
      });
      final task = data['task'] as Map<String, dynamic>;
      expect(task['title'], 'Original title');
      expect(task['priority'], 5);
      expect(task['status'], 'NEEDS-ACTION');
    });

    test('missing task reports TASK_NOT_FOUND', () async {
      final payload = await _toolError(app, token, 'update_task', {
        'task_id': 'absent-task',
        'title': 'x',
      });
      expect(payload['code'], 'TASK_NOT_FOUND');
      expect(payload['hint'], contains('list_tasks'));
    });
  });

  group('complete_task', () {
    test('marks the task completed with completedAt and percentComplete',
        () async {
      await _seed(
        app,
        userId,
        'td-finish',
        type: RecordType.todo,
        fields: {
          'summary': 'Finish it',
          'dueDate': null,
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'completedAt': null,
          'deletedAt': null,
        },
      );
      final data = await _toolData(
        app,
        token,
        'complete_task',
        {'task_id': 'td-finish'},
      );
      final task = data['task'] as Map<String, dynamic>;
      expect(task['status'], 'COMPLETED');
      expect(task['completed_at'], matches(RegExp(r'Z$')));
      expect(task['percent'], 100);

      final row = await _row(app, userId, 'td-finish');
      final payload = jsonDecode(row!.payloadJson) as Map<String, dynamic>;
      expect(payload['status'], 'COMPLETED');
      expect(payload['percentComplete'], 100);
      expect(payload['completedAt'], isNotNull);
    });

    test('missing task reports TASK_NOT_FOUND', () async {
      final payload = await _toolError(
        app,
        token,
        'complete_task',
        {'task_id': 'nope'},
      );
      expect(payload['code'], 'TASK_NOT_FOUND');
      expect(payload['hint'], contains('list_tasks'));
    });
  });

  group('reopen_task', () {
    test('reopens a completed task', () async {
      await _seed(
        app,
        userId,
        'td-reopen',
        type: RecordType.todo,
        fields: {
          'summary': 'Done before',
          'dueDate': null,
          'priority': 0,
          'status': 'COMPLETED',
          'percentComplete': 100,
          'completedAt': iso(now().subtract(const Duration(hours: 1))),
          'deletedAt': null,
        },
      );
      final data = await _toolData(
        app,
        token,
        'reopen_task',
        {'task_id': 'td-reopen'},
      );
      final task = data['task'] as Map<String, dynamic>;
      expect(task['status'], 'NEEDS-ACTION');
      expect(task['completed_at'], isNull);
      expect(task['percent'], 0);
    });

    test('missing task reports TASK_NOT_FOUND', () async {
      final payload = await _toolError(
        app,
        token,
        'reopen_task',
        {'task_id': 'nope'},
      );
      expect(payload['code'], 'TASK_NOT_FOUND');
      expect(payload['hint'], isNotEmpty);
    });
  });

  group('snooze_task', () {
    test('defers the task due date to the snooze instant', () async {
      await _seed(
        app,
        userId,
        'td-snooze',
        type: RecordType.todo,
        fields: {
          'summary': 'Later please',
          'dueDate': iso(now().add(const Duration(hours: 1))),
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'completedAt': null,
          'deletedAt': null,
        },
      );
      final until = now().add(const Duration(hours: 6));
      final data = await _toolData(app, token, 'snooze_task', {
        'task_id': 'td-snooze',
        'until': iso(until),
      });
      final task = data['task'] as Map<String, dynamic>;
      expect(
        DateTime.parse(task['due'] as String),
        until,
        reason: 'snooze moves the synced due instant',
      );

      final row = await _row(app, userId, 'td-snooze');
      final payload = jsonDecode(row!.payloadJson) as Map<String, dynamic>;
      expect(payload['dueDate'], iso(until));
      expect(payload['status'], 'NEEDS-ACTION',
          reason: 'snooze never touches completion state');
      expect(payload['completedAt'], isNull);
    });

    test('rejects a naive until datetime', () async {
      await _seed(
        app,
        userId,
        'td-snooze-naive',
        type: RecordType.todo,
        fields: {
          'summary': 'x',
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
        },
      );
      final payload = await _toolError(app, token, 'snooze_task', {
        'task_id': 'td-snooze-naive',
        'until': '2026-09-24T09:00:00',
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['hint'], contains('timezone offset or Z'));
    });

    test('missing task reports TASK_NOT_FOUND', () async {
      final payload = await _toolError(app, token, 'snooze_task', {
        'task_id': 'ghost',
        'until': iso(now().add(const Duration(days: 1))),
      });
      expect(payload['code'], 'TASK_NOT_FOUND');
      expect(payload['hint'], contains('list_tasks'));
    });
  });

  group('trash_task', () {
    test('soft-deletes the task into the trash view', () async {
      await _seed(
        app,
        userId,
        'td-trash-me',
        type: RecordType.todo,
        fields: {
          'summary': 'Trash me',
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'deletedAt': null,
        },
      );
      final data = await _toolData(
        app,
        token,
        'trash_task',
        {'task_id': 'td-trash-me'},
      );
      expect((data['task'] as Map)['trashed'], isTrue);

      final live = await _liveIds(app.db, userId: userId);
      expect(live, isNot(contains('td-trash-me')));
      final trash =
          await _liveIds(app.db, userId: userId, trashedOnly: true);
      expect(trash, contains('td-trash-me'));

      final row = await _row(app, userId, 'td-trash-me');
      expect(row!.deleted, isFalse);
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['deletedAt'], matches(RegExp(r'Z$')));
      expect(payload['summary'], 'Trash me');
    });

    test('missing task reports TASK_NOT_FOUND', () async {
      final payload = await _toolError(
        app,
        token,
        'trash_task',
        {'task_id': 'absent'},
      );
      expect(payload['code'], 'TASK_NOT_FOUND');
      expect(payload['hint'], contains('list_tasks'));
    });
  });

  group('batch_create_tasks', () {
    test('creates every task in one call', () async {
      final data = await _toolData(app, token, 'batch_create_tasks', {
        'tasks': [
          {'title': 'Batch one'},
          {
            'title': 'Batch two',
            'due': iso(now().add(const Duration(days: 2))),
            'priority': 2,
          },
        ],
      });
      expect(data['created'], 2);
      expect(data['failed'], 0);
      final results = data['results'] as List;
      expect(results, hasLength(2));
      expect(
        results.map((r) => (r as Map)['status']),
        ['applied', 'applied'],
      );

      final page = await queryRecords(
        app.db,
        userId: userId,
        type: RecordType.todo,
      );
      expect(page.records, hasLength(2));
    });

    test('an invalid item fails the batch with a validation error', () async {
      final payload = await _toolError(app, token, 'batch_create_tasks', {
        'tasks': [
          {'title': 'ok'},
          {'priority': 1},
        ],
      });
      expect(payload['code'], 'VALIDATION');
      expect(payload['message'], contains('tasks'));
      expect(payload['hint'], isNotEmpty);

      final page = await queryRecords(
        app.db,
        userId: userId,
        type: RecordType.todo,
      );
      expect(page.records, isEmpty,
          reason: 'schema validation runs before any write');
    });
  });
}
