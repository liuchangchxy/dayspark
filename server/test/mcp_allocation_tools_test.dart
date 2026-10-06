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
  final response = await _request(
    app.handler,
    'POST',
    '/auth/register',
    body: {'email': email, 'password': 'password123'},
  );
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
  expect(result['isError'], isNot(true), reason: '${result['content']}');
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
  expect(
    result['isError'],
    true,
    reason: 'expected isError for $name ${result['content']}',
  );
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
  expect(
    result.status,
    OpStatus.applied,
    reason: 'seed $id must apply: ${result.code}',
  );
}

Future<RecordRow?> _row(AppServer app, String userId, String id) {
  return (app.db.select(
    app.db.records,
  )..where((t) => t.userId.equals(userId) & t.id.equals(id))).getSingleOrNull();
}

void main() {
  late AppServer app;
  late String token;
  late String userId;

  setUp(() async {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
    final reg = await _register(app, 'alloc-mcp@example.com');
    userId = reg['userId']!;
    token = reg['token']!;
  });

  tearDown(() async {
    await app.close();
  });

  final base = DateTime.utc(2026, 10, 10, 10, 0, 0);

  group('schedule_task', () {
    test('schedules ordinary task into free slot without touching dueDate or creating Event', () async {
      await _seed(
        app,
        userId,
        'task-ord-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Ordinary Task',
          'dueDate': '2026-10-15T18:00:00.000Z',
          'priority': 1,
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final start = '2026-10-11T09:00:00.000Z';
      final end = '2026-10-11T10:00:00.000Z';
      final data = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-ord-1',
        'start': start,
        'end': end,
      });

      expect(data['allocation'], isNotNull);
      final alloc = data['allocation'] as Map<String, dynamic>;
      expect(alloc['task_id'], 'task-ord-1');
      expect(alloc['start'], isoZ(DateTime.parse(start)));
      expect(alloc['end'], isoZ(DateTime.parse(end)));
      expect(alloc['occurrence_id'], isNull);
      expect(alloc['state'], 'active');
      expect(data['op']['status'], 'applied');

      // Invariant checks:
      // 1. Task dueDate is untouched
      final taskRow = await _row(app, userId, 'task-ord-1');
      final taskPayload = jsonDecode(taskRow!.payloadJson) as Map<String, dynamic>;
      expect(taskPayload['dueDate'], '2026-10-15T18:00:00.000Z');

      // 2. Zero Event records created
      final events = await queryRecords(app.db, userId: userId, type: RecordType.event);
      expect(events.records, isEmpty);
    });

    test('rejects ordinary task when occurrence_id is mistakenly provided', () async {
      await _seed(
        app,
        userId,
        'task-ord-2',
        type: RecordType.todo,
        fields: {
          'summary': 'Ordinary Task 2',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-ord-2',
        'start': '2026-10-11T09:00:00.000Z',
        'end': '2026-10-11T10:00:00.000Z',
        'occurrence_id': 'task-ord-2:20261011T090000Z',
      });
      expect(err['code'], 'VALIDATION');
      expect(err['message'], contains('ordinary task cannot specify occurrence_id'));
    });

    test('rejects recurring task when occurrence_id is omitted, hints list_task_occurrences', () async {
      await _seed(
        app,
        userId,
        'task-rec-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Daily Standup Task',
          'status': 'NEEDS-ACTION',
          'rrule': 'FREQ=DAILY;COUNT=5',
          'recurrenceSpec': {
            'anchor': {
              'source': 'start',
              'valueType': 'dateTime',
              'value': '2026-10-11T09:00:00',
            },
            'timeZone': 'UTC',
            'rrule': 'FREQ=DAILY;COUNT=5',
          },
          'recurrenceRevision': 1,
          'recurrenceLegacyState': 'knownZoned',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-rec-1',
        'start': '2026-10-11T09:00:00.000Z',
        'end': '2026-10-11T10:00:00.000Z',
      });
      expect(err['code'], 'VALIDATION');
      expect(err['message'], contains('requires an explicit occurrence_id'));
      expect(err['hint'], contains('list_task_occurrences'));
    });

    test('rejects recurring task with mismatched or invalid occurrence_id', () async {
      await _seed(
        app,
        userId,
        'task-rec-2',
        type: RecordType.todo,
        fields: {
          'summary': 'Daily Exercise',
          'status': 'NEEDS-ACTION',
          'rrule': 'FREQ=DAILY;COUNT=5',
          'recurrenceSpec': {
            'anchor': {
              'source': 'start',
              'valueType': 'dateTime',
              'value': '2026-10-11T09:00:00',
            },
            'timeZone': 'UTC',
            'rrule': 'FREQ=DAILY;COUNT=5',
          },
          'recurrenceRevision': 1,
          'recurrenceLegacyState': 'knownZoned',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-rec-2',
        'start': '2026-10-11T09:00:00.000Z',
        'end': '2026-10-11T10:00:00.000Z',
        'occurrence_id': 'invalid-occ-id',
      });
      expect(err['code'], 'VALIDATION');
      expect(err['message'], contains('does not belong to the recurring series'));
    });

    test('schedules recurring task with exact valid canonical occurrence_id', () async {
      await _seed(
        app,
        userId,
        'task-rec-3',
        type: RecordType.todo,
        fields: {
          'summary': 'Recurring Task 3',
          'status': 'NEEDS-ACTION',
          'rrule': 'FREQ=DAILY;COUNT=5',
          'recurrenceSpec': {
            'anchor': {
              'source': 'start',
              'valueType': 'dateTime',
              'value': '2026-10-11T09:00:00',
            },
            'timeZone': 'UTC',
            'rrule': 'FREQ=DAILY;COUNT=5',
          },
          'recurrenceRevision': 1,
          'recurrenceLegacyState': 'knownZoned',
        },
      );

      final occRead = await _toolData(app, token, 'list_task_occurrences', {
        'task_id': 'task-rec-3',
        'from': '2026-10-11T00:00:00Z',
        'to': '2026-10-12T00:00:00Z',
      });
      final occurrences = occRead['occurrences'] as List;
      expect(occurrences, isNotEmpty);
      final occurrenceId = occurrences.first['occurrence_id'] as String;

      final start = '2026-10-11T09:00:00.000Z';
      final end = '2026-10-11T10:00:00.000Z';
      final data = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-rec-3',
        'start': start,
        'end': end,
        'occurrence_id': occurrenceId,
      });

      final alloc = data['allocation'] as Map<String, dynamic>;
      expect(alloc['task_id'], 'task-rec-3');
      expect(alloc['occurrence_id'], occurrenceId);
      expect(alloc['state'], 'active');
    });

    test('rejects completed or skipped occurrence', () async {
      await _seed(
        app,
        userId,
        'task-rec-done',
        type: RecordType.todo,
        fields: {
          'summary': 'Done Recurring Task',
          'status': 'NEEDS-ACTION',
          'rrule': 'FREQ=DAILY;COUNT=5',
          'recurrenceSpec': {
            'anchor': {
              'source': 'start',
              'valueType': 'dateTime',
              'value': '2026-10-11T09:00:00',
            },
            'timeZone': 'UTC',
            'rrule': 'FREQ=DAILY;COUNT=5',
          },
          'recurrenceRevision': 1,
          'recurrenceLegacyState': 'knownZoned',
        },
      );

      final occRead = await _toolData(app, token, 'list_task_occurrences', {
        'task_id': 'task-rec-done',
        'from': '2026-10-11T00:00:00Z',
        'to': '2026-10-12T00:00:00Z',
      });
      final occurrences = occRead['occurrences'] as List;
      final occurrenceId = occurrences.first['occurrence_id'] as String;

      // Complete this occurrence via complete_task
      await _toolData(app, token, 'complete_task', {
        'task_id': 'task-rec-done',
        'occurrence_id': occurrenceId,
      });

      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-rec-done',
        'start': '2026-10-11T09:00:00.000Z',
        'end': '2026-10-11T10:00:00.000Z',
        'occurrence_id': occurrenceId,
      });
      expect(err['code'], 'VALIDATION');
      expect(err['message'], contains('cannot schedule a completed occurrence'));
    });
  });

  group('safe conflict policy & TOCTOU defense', () {
    test('default schedule_task rejects conflict with Event and provides structured conflict refs', () async {
      await _seed(
        app,
        userId,
        'evt-1',
        type: RecordType.event,
        fields: {
          'summary': 'Busy Meeting',
          'startDt': '2026-10-12T09:00:00.000Z',
          'endDt': '2026-10-12T10:30:00.000Z',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      await _seed(
        app,
        userId,
        'task-conflict-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Task during meeting',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      // Overlaps 09:30-10:15
      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-conflict-1',
        'start': '2026-10-12T09:30:00.000Z',
        'end': '2026-10-12T10:15:00.000Z',
      });
      expect(err['code'], 'CONFLICT');
      expect(err['message'], contains('conflicts with existing busy intervals'));
      expect(err['hint'], contains('allow_conflicts: true'));
      expect(err['conflicts'], isNotNull);
      final conflicts = err['conflicts'] as List;
      expect(conflicts, isNotEmpty);
      final sources = (conflicts.first as Map<String, dynamic>)['sources'] as List;
      expect(sources, isNotEmpty);
      expect((sources.first as Map<String, dynamic>)['type'], 'event');
      expect((sources.first as Map<String, dynamic>)['id'], 'evt-1');
    });

    test('allow_conflicts: true explicitly allows overlapping schedule_task', () async {
      await _seed(
        app,
        userId,
        'evt-2',
        type: RecordType.event,
        fields: {
          'summary': 'Meeting 2',
          'startDt': '2026-10-12T14:00:00.000Z',
          'endDt': '2026-10-12T15:00:00.000Z',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      await _seed(
        app,
        userId,
        'task-allow-conflict',
        type: RecordType.todo,
        fields: {
          'summary': 'Task allowed to overlap',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final data = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-allow-conflict',
        'start': '2026-10-12T14:30:00.000Z',
        'end': '2026-10-12T15:30:00.000Z',
        'allow_conflicts': true,
      });
      expect(data['allocation'], isNotNull);
      final alloc = data['allocation'] as Map<String, dynamic>;
      expect(alloc['start'], isoZ(DateTime.parse('2026-10-12T14:30:00.000Z')));
      expect(alloc['end'], isoZ(DateTime.parse('2026-10-12T15:30:00.000Z')));
    });

    test('TOCTOU simulation: find_free_time sees free slot -> race event inserted -> schedule_task rejected', () async {
      await _seed(
        app,
        userId,
        'task-toctou',
        type: RecordType.todo,
        fields: {
          'summary': 'TOCTOU Task',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      // Step 1: Agent calls find_free_time
      final freeData = await _toolData(app, token, 'find_free_time', {
        'from': '2026-10-13T09:00:00.000Z',
        'to': '2026-10-13T12:00:00.000Z',
        'duration_minutes': 60,
        'timezone': 'UTC',
        'working_hours_start': '09:00',
        'working_hours_end': '12:00',
      });
      final slots = freeData['slots'] as List;
      expect(slots, isNotEmpty);
      final chosenStart = slots.first['start'] as String;
      final chosenEnd = slots.first['end'] as String;

      // Step 2: Race condition! Another client inserts an Event in that slot
      await _seed(
        app,
        userId,
        'race-event',
        type: RecordType.event,
        fields: {
          'summary': 'Intervening Event',
          'startDt': chosenStart,
          'endDt': chosenEnd,
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      // Step 3: schedule_task without allow_conflicts is safely rejected
      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-toctou',
        'start': chosenStart,
        'end': chosenEnd,
      });
      expect(err['code'], 'CONFLICT');
      expect(err['conflicts'], isNotEmpty);

      // Step 4: With explicit allow_conflicts: true, write succeeds
      final ok = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-toctou',
        'start': chosenStart,
        'end': chosenEnd,
        'allow_conflicts': true,
      });
      expect(ok['allocation']['start'], chosenStart);
    });
  });

  group('reschedule_task_allocation', () {
    test('reschedule modifies interval and excludes self from conflict check', () async {
      await _seed(
        app,
        userId,
        'task-resched-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Task to Reschedule',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final initial = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-resched-1',
        'start': '2026-10-14T09:00:00.000Z',
        'end': '2026-10-14T10:00:00.000Z',
      });
      final allocId = initial['allocation']['allocation_id'] as String;

      // Move from 09:00-10:00 to 09:30-10:30 (overlaps original self).
      // Self-exclusion ensures this succeeds and does not report CONFLICT with itself.
      final rescheduled = await _toolData(app, token, 'reschedule_task_allocation', {
        'allocation_id': allocId,
        'start': '2026-10-14T09:30:00.000Z',
        'end': '2026-10-14T10:30:00.000Z',
      });

      final alloc = rescheduled['allocation'] as Map<String, dynamic>;
      expect(alloc['allocation_id'], allocId);
      expect(alloc['start'], isoZ(DateTime.parse('2026-10-14T09:30:00.000Z')));
      expect(alloc['end'], isoZ(DateTime.parse('2026-10-14T10:30:00.000Z')));
      expect(alloc['state'], 'active');
    });

    test('reschedule rejects conflict with other allocations without allow_conflicts: true', () async {
      await _seed(
        app,
        userId,
        'task-resched-a',
        type: RecordType.todo,
        fields: {
          'summary': 'Task A',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );
      await _seed(
        app,
        userId,
        'task-resched-b',
        type: RecordType.todo,
        fields: {
          'summary': 'Task B',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-resched-a',
        'start': '2026-10-14T14:00:00.000Z',
        'end': '2026-10-14T15:00:00.000Z',
      });
      final b = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-resched-b',
        'start': '2026-10-14T15:00:00.000Z',
        'end': '2026-10-14T16:00:00.000Z',
      });

      final bId = b['allocation']['allocation_id'] as String;

      // Try rescheduling B into A's interval (14:30-15:30)
      final err = await _toolError(app, token, 'reschedule_task_allocation', {
        'allocation_id': bId,
        'start': '2026-10-14T14:30:00.000Z',
        'end': '2026-10-14T15:30:00.000Z',
      });
      expect(err['code'], 'CONFLICT');

      // With allow_conflicts: true, succeeds
      final ok = await _toolData(app, token, 'reschedule_task_allocation', {
        'allocation_id': bId,
        'start': '2026-10-14T14:30:00.000Z',
        'end': '2026-10-14T15:30:00.000Z',
        'allow_conflicts': true,
      });
      expect(ok['allocation']['start'], isoZ(DateTime.parse('2026-10-14T14:30:00.000Z')));
    });

    test('missing allocation returns ALLOCATION_NOT_FOUND', () async {
      final err = await _toolError(app, token, 'reschedule_task_allocation', {
        'allocation_id': 'nonexistent-alloc',
        'start': '2026-10-14T14:30:00.000Z',
        'end': '2026-10-14T15:30:00.000Z',
      });
      expect(err['code'], 'ALLOCATION_NOT_FOUND');
    });
  });

  group('cancel_task_allocation', () {
    test('cancels active allocation to cancelledByUser without physically deleting or modifying task', () async {
      await _seed(
        app,
        userId,
        'task-cancel-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Task with allocation to cancel',
          'status': 'pending',
          'dueDate': '2026-10-20T12:00:00.000Z',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final data = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-cancel-1',
        'start': '2026-10-15T09:00:00.000Z',
        'end': '2026-10-15T10:00:00.000Z',
      });
      final allocId = data['allocation']['allocation_id'] as String;

      final cancelRes = await _toolData(app, token, 'cancel_task_allocation', {
        'allocation_id': allocId,
      });
      expect(cancelRes['cancelled'], isTrue);
      expect(cancelRes['allocation']['state'], 'cancelledByUser');

      // Allocation still physically exists in DB with cancelledByUser
      final row = await _row(app, userId, allocId);
      expect(row, isNotNull);
      final payload = jsonDecode(row!.payloadJson) as Map<String, dynamic>;
      expect(payload['state'], 'cancelledByUser');

      // Todo status & dueDate remain untouched
      final taskRow = await _row(app, userId, 'task-cancel-1');
      final taskPayload = jsonDecode(taskRow!.payloadJson) as Map<String, dynamic>;
      expect(taskPayload['status'], 'pending');
      expect(taskPayload['dueDate'], '2026-10-20T12:00:00.000Z');
    });

    test('cancelling non-active allocation fails with validation error', () async {
      await _seed(
        app,
        userId,
        'task-cancel-2',
        type: RecordType.todo,
        fields: {
          'summary': 'Task 2',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final data = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-cancel-2',
        'start': '2026-10-15T11:00:00.000Z',
        'end': '2026-10-15T12:00:00.000Z',
      });
      final allocId = data['allocation']['allocation_id'] as String;

      // Cancel first time
      await _toolData(app, token, 'cancel_task_allocation', {
        'allocation_id': allocId,
      });

      // Cancel second time without idempotency key -> validation error
      final err = await _toolError(app, token, 'cancel_task_allocation', {
        'allocation_id': allocId,
      });
      expect(err['code'], 'VALIDATION');
      expect(err['message'], contains('only active task allocations can be cancelled'));
    });
  });

  group('list_task_allocations & multi-allocation co-existence', () {
    test('schedules multiple allocations for same task; rescheduling/cancelling one leaves other intact', () async {
      await _seed(
        app,
        userId,
        'task-multi-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Long Project Task',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final a1 = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-multi-1',
        'start': '2026-10-16T09:00:00.000Z',
        'end': '2026-10-16T11:00:00.000Z',
      });
      final id1 = a1['allocation']['allocation_id'] as String;

      final a2 = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-multi-1',
        'start': '2026-10-16T14:00:00.000Z',
        'end': '2026-10-16T16:00:00.000Z',
      });
      final id2 = a2['allocation']['allocation_id'] as String;

      // list_task_allocations returns both
      final list1 = await _toolData(app, token, 'list_task_allocations', {
        'task_id': 'task-multi-1',
      });
      final allocs1 = (list1['allocations'] as List).cast<Map<String, dynamic>>();
      expect(allocs1, hasLength(2));
      expect(allocs1.map((a) => a['allocation_id']).toSet(), {id1, id2});

      // Cancel first allocation
      await _toolData(app, token, 'cancel_task_allocation', {
        'allocation_id': id1,
      });

      // List active only
      final listActive = await _toolData(app, token, 'list_task_allocations', {
        'task_id': 'task-multi-1',
        'state': 'active',
      });
      final allocsActive = (listActive['allocations'] as List).cast<Map<String, dynamic>>();
      expect(allocsActive, hasLength(1));
      expect(allocsActive.first['allocation_id'], id2);
      expect(allocsActive.first['state'], 'active');
    });
  });

  group('idempotency priority order', () {
    test('schedule_task replay returns previous result even though interval is occupied by first allocation', () async {
      await _seed(
        app,
        userId,
        'task-idem-1',
        type: RecordType.todo,
        fields: {
          'summary': 'Idempotent Schedule Task',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final args = {
        'task_id': 'task-idem-1',
        'start': '2026-10-17T09:00:00.000Z',
        'end': '2026-10-17T10:00:00.000Z',
        'idempotency_key': 'key-schedule-1',
      };

      // First call succeeds
      final first = await _toolData(app, token, 'schedule_task', args);
      final firstAllocId = first['allocation']['allocation_id'];
      expect(first['op']['status'], 'applied');

      // Second identical call with same idempotency_key must return same result without failing conflict check
      final second = await _toolData(app, token, 'schedule_task', args);
      expect(second['allocation']['allocation_id'], firstAllocId);
      expect(second['op']['status'], 'applied');
    });

    test('cancel_task_allocation replay returns previous result even though allocation is already cancelled', () async {
      await _seed(
        app,
        userId,
        'task-idem-2',
        type: RecordType.todo,
        fields: {
          'summary': 'Idempotent Cancel Task',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      final created = await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-idem-2',
        'start': '2026-10-17T11:00:00.000Z',
        'end': '2026-10-17T12:00:00.000Z',
      });
      final allocId = created['allocation']['allocation_id'] as String;

      final cancelArgs = {
        'allocation_id': allocId,
        'idempotency_key': 'key-cancel-1',
      };

      // First cancel succeeds
      final first = await _toolData(app, token, 'cancel_task_allocation', cancelArgs);
      expect(first['cancelled'], isTrue);
      expect(first['allocation']['state'], 'cancelledByUser');

      // Second identical cancel returns replay without failing active check
      final second = await _toolData(app, token, 'cancel_task_allocation', cancelArgs);
      expect(second['cancelled'], isTrue);
      expect(second['allocation']['state'], 'cancelledByUser');
    });

    test('reusing idempotency_key with mismatched payload fails', () async {
      await _seed(
        app,
        userId,
        'task-idem-3',
        type: RecordType.todo,
        fields: {
          'summary': 'Idempotent Mismatch Task',
          'status': 'pending',
          'createdAt': iso(base),
          'updatedAt': iso(base),
        },
      );

      await _toolData(app, token, 'schedule_task', {
        'task_id': 'task-idem-3',
        'start': '2026-10-17T14:00:00.000Z',
        'end': '2026-10-17T15:00:00.000Z',
        'idempotency_key': 'key-shared-mismatch',
      });

      // Re-use key with different start time
      final err = await _toolError(app, token, 'schedule_task', {
        'task_id': 'task-idem-3',
        'start': '2026-10-17T15:00:00.000Z',
        'end': '2026-10-17T16:00:00.000Z',
        'idempotency_key': 'key-shared-mismatch',
      });
      expect(err['code'], 'VALIDATION');
      expect(err['message'], contains('reused with a different request body'));
      expect(err['hint'], contains('idempotency_key was already used'));
    });
  });
}
