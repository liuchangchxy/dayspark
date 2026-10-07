import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/task_instance_writer.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:dayspark_server/server.dart' as srv;
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../domain/sync/sync_test_support.dart';

class _Device {
  _Device(this.name, String baseUrl) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = DioSyncTransport(baseUrl: baseUrl);
    tokens = MemoryTokenStore();
    cursors = MemoryCursorStore();
    snapshots = MemorySnapshotStore();
    api = AuthSyncApiClient(transport: transport, tokens: tokens);
    engine = SyncEngine(
      db: db,
      api: api,
      cursorStore: cursors,
      tokenStore: tokens,
      snapshots: snapshots,
      deviceId: 'device-$name',
    );
  }

  final String name;
  late final AppDatabase db;
  late final SyncTransport transport;
  late final MemoryTokenStore tokens;
  late final MemoryCursorStore cursors;
  late final MemorySnapshotStore snapshots;
  late final AuthSyncApiClient api;
  late final SyncEngine engine;
  late int calendarId;

  Future<void> dispose() async {
    await engine.stop();
    await db.close();
  }
}

Future<void> _round(
  _Device d, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final before = d.cursors.value ?? 0;
  await d.engine.requestRound();
  var stable = 0;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = d.engine.status;
    final idle = status.phase == SyncPhase.idle && status.lastError == null;
    stable = idle ? stable + 1 : 0;
    if (stable >= 4) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final status = d.engine.status;
  expect(
    status.phase == SyncPhase.idle && status.lastError == null,
    isTrue,
    reason:
        '${d.name} round must settle idle (phase=${status.phase}, '
        'error=${status.lastError})',
  );
  expect(
    d.cursors.value ?? 0,
    greaterThanOrEqualTo(before),
    reason: '${d.name} cursor must be monotonic',
  );
}

Future<int> _seedCalendar(AppDatabase db) =>
    db.into(db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));

Future<Map<String, dynamic>> _callMcpTool(
  srv.AppServer app,
  String token,
  String name,
  Map<String, Object?> args,
) async {
  final response = await app.handler(
    srv.Request(
      'POST',
      Uri.parse('http://localhost/mcp'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args},
      }),
    ),
  );
  expect(response.statusCode, 200);
  final text = await response.readAsString();
  final body = jsonDecode(text) as Map<String, dynamic>;
  expect(body['error'], isNull, reason: text);
  final result = body['result'] as Map<String, dynamic>;
  expect(result['isError'], isNot(isTrue), reason: text);
  final content = result['content'] as List<dynamic>;
  final textContent = content.first as Map<String, dynamic>;
  return jsonDecode(textContent['text'] as String) as Map<String, dynamic>;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late srv.AppServer app;
  late HttpServer http;
  late Directory tempDir;
  late String baseUrl;
  late _Device a;
  late String userToken;
  var registerSeq = 0;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dayspark_mcp_vertical_');
    app = srv.AppServer(
      srv.Config(
        dbPath: '${tempDir.path}/server.db',
        port: 0,
        jwtSecret: 'mcp-vertical-secret',
      ),
    );
    http = await app.serve();
    baseUrl = 'http://127.0.0.1:${http.port}';

    a = _Device('A', baseUrl);
    a.calendarId = await _seedCalendar(a.db);

    final session = await a.api.register(
      email: 'vertical-${registerSeq++}@dayspark.test',
      password: 'password123',
    );
    userToken = session.accessToken;
    await a.tokens.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    await a.engine.start();
    await _round(a);
  });

  tearDown(() async {
    await a.dispose();
    await http.close(force: true);
    await app.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('ordinary Todo: MCP schedule_task -> sync pull -> client calendar/action projection -> completion', () async {
    final due = DateTime.utc(2026, 10, 25, 18, 0);
    final todoId = await RecordScope.run(
      a.db,
      (tx) => TodoWriter.create(
        a.db,
        tx,
        TodosCompanion.insert(
          calendarId: a.calendarId,
          summary: 'Prepare Launch Brief',
          dueDate: Value(due),
          priority: const Value(1),
        ),
      ),
    );

    // Push Todo from Device A to server
    await _round(a);

    final localTodo = await (a.db.select(a.db.todos)..where((t) => t.id.equals(todoId))).getSingle();
    final todoSyncId = localTodo.syncId;
    expect(todoSyncId, isNotNull);

    // Call MCP schedule_task on server
    final schedResult = await _callMcpTool(
      app,
      userToken,
      'schedule_task',
      {
        'task_id': todoSyncId,
        'start': '2026-10-21T10:00:00Z',
        'end': '2026-10-21T11:00:00Z',
      },
    );
    expect(schedResult['allocation'], isNotNull);
    final allocJson = schedResult['allocation'] as Map<String, dynamic>;
    expect(allocJson['state'], 'active');
    expect(allocJson['occurrence_id'], isNull);

    // Device A syncs down the new allocation from server
    await _round(a);

    // 1. Client DB has active TaskAllocation
    final allocations = await (a.db.select(a.db.taskAllocations)..where((t) => t.todoId.equals(todoId))).get();
    expect(allocations, hasLength(1));
    final alloc = allocations.first;
    expect(alloc.state, 'active');
    expect(alloc.occurrenceId, isNull);
    expect(alloc.startAt, DateTime.utc(2026, 10, 21, 10, 0));
    expect(alloc.endAt, DateTime.utc(2026, 10, 21, 11, 0));

    // 2. Calendar / Action projection
    final projectedItems = await fetchTaskAllocationsInDateRange(
      a.db,
      DateTime.utc(2026, 10, 21, 0, 0),
      DateTime.utc(2026, 10, 22, 0, 0),
    );
    expect(projectedItems, hasLength(1));
    expect(projectedItems.first.todo.summary, 'Prepare Launch Brief');
    expect(projectedItems.first.allocation.startAt, alloc.startAt);
    expect(projectedItems.first.allocation.endAt, alloc.endAt);

    // 3. Complete Todo on client
    await RecordScope.run(
      a.db,
      (tx) => TodoWriter.updateTodo(
        a.db,
        tx,
        todoId,
        TodosCompanion(
          status: const Value('COMPLETED'),
          completedAt: Value(DateTime.utc(2026, 10, 21, 9, 0)),
        ),
      ),
    );

    // 4. Invariants check:
    // - allocation transitioned to invalidatedByCompletion
    final allocAfter = await (a.db.select(a.db.taskAllocations)..where((t) => t.id.equals(alloc.id))).getSingle();
    expect(allocAfter.state, 'invalidatedByCompletion');

    // - dueDate remains untouched
    final todoAfter = await (a.db.select(a.db.todos)..where((t) => t.id.equals(todoId))).getSingle();
    expect(todoAfter.dueDate!.toUtc(), due);

    // - zero Event rows created
    final events = await a.db.select(a.db.events).get();
    expect(events, isEmpty);
  });

  test('recurring Todo: MCP schedule_task with occurrence_id -> sync pull -> client projection -> instance completion', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(2026, 10, 20),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=5',
    );

    final todoId = await RecordScope.run(
      a.db,
      (tx) => TodoWriter.create(
        a.db,
        tx,
        TodosCompanion.insert(
          calendarId: a.calendarId,
          summary: 'Daily Sync',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    await _round(a);

    final localTodo = await (a.db.select(a.db.todos)..where((t) => t.id.equals(todoId))).getSingle();
    final todoSyncId = localTodo.syncId;
    expect(todoSyncId, isNotNull);

    // List occurrences via MCP
    final occListResult = await _callMcpTool(
      app,
      userToken,
      'list_task_occurrences',
      {
        'task_id': todoSyncId,
        'from': '2026-10-20T00:00:00Z',
        'to': '2026-10-25T00:00:00Z',
      },
    );
    final occurrences = occListResult['occurrences'] as List<dynamic>;
    expect(occurrences, isNotEmpty);
    final canonicalOccId = occurrences.first['occurrence_id'] as String;
    expect(canonicalOccId, 'v2:DATE:2026-10-20');

    // Schedule the occurrence via MCP
    final schedResult = await _callMcpTool(
      app,
      userToken,
      'schedule_task',
      {
        'task_id': todoSyncId,
        'occurrence_id': canonicalOccId,
        'start': '2026-10-20T09:00:00Z',
        'end': '2026-10-20T09:30:00Z',
      },
    );
    expect(schedResult['allocation'], isNotNull);
    final allocJson = schedResult['allocation'] as Map<String, dynamic>;
    expect(allocJson['state'], 'active');
    expect(allocJson['occurrence_id'], canonicalOccId);

    // Sync down to Client A
    await _round(a);

    // Verify client DB
    final allocations = await (a.db.select(a.db.taskAllocations)..where((t) => t.todoId.equals(todoId))).get();
    expect(allocations, hasLength(1));
    final alloc = allocations.first;
    expect(alloc.state, 'active');
    expect(alloc.occurrenceId, canonicalOccId);

    // Verify Calendar / Action projection
    final projectedItems = await fetchTaskAllocationsInDateRange(
      a.db,
      DateTime.utc(2026, 10, 20, 0, 0),
      DateTime.utc(2026, 10, 21, 0, 0),
    );
    expect(projectedItems, hasLength(1));
    expect(projectedItems.first.todo.summary, 'Daily Sync');
    expect(projectedItems.first.allocation.occurrenceId, canonicalOccId);

    // Complete that instance on client
    await RecordScope.run(
      a.db,
      (tx) => TaskInstanceWriter.setCompletion(
        a.db,
        tx,
        todoId: todoId,
        occurrenceId: canonicalOccId,
        completed: true,
      ),
    );

    // Allocation invalidated by completion
    final allocAfter = await (a.db.select(a.db.taskAllocations)..where((t) => t.id.equals(alloc.id))).getSingle();
    expect(allocAfter.state, 'invalidatedByCompletion');

    // Series dueDate untouched (null)
    final todoAfter = await (a.db.select(a.db.todos)..where((t) => t.id.equals(todoId))).getSingle();
    expect(todoAfter.dueDate, isNull);

    // Zero Event rows created
    final events = await a.db.select(a.db.events).get();
    expect(events, isEmpty);
  });
}
