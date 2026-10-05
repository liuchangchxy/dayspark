import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/task_allocation_writer.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:dayspark_server/server.dart' as srv;
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../domain/sync/sync_test_support.dart';

/// Two-device e2e matrix against a REAL server:
///
/// * the server is `srv.AppServer` booted in-process on an ephemeral port
///   with a temp-file SQLite db (real shelf HTTP, real auth, real LWW);
/// * each "device" is its own engine stack — private in-memory Drift db,
///   private outbox/cursor/token stores, private Dio transport — driving
///   rounds explicitly via `requestRound()` (no sleep-based sync).
///
/// Architecture choice (see task-7 report): two engine instances rather
/// than two ProviderContainers — the provider graph pulls in platform
/// channels (secure storage, connectivity, prefs singletons) that the
/// container would only need mocked, while the engine instances exercise
/// the exact production sync path end to end.
class _Device {
  _Device(this.name, String baseUrl) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = _GatedTransport(DioSyncTransport(baseUrl: baseUrl));
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
  late final _GatedTransport transport;
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

/// Blocks every request while "offline" — the engine round then fails with
/// a transport error exactly like a dead network would.
class _GatedTransport implements SyncTransport {
  _GatedTransport(this._inner);

  final SyncTransport _inner;
  bool online = true;
  bool legacyClient = false;

  @override
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    if (!online) return Future.error(const SyncTransportException(0));
    var requestPath = path;
    var requestBody = body;
    if (legacyClient && method == 'GET' && path.startsWith('/sync/pull?')) {
      requestPath = path.replaceAll(
        RegExp(r'capabilities=[^&]*'),
        'capabilities=task_allocation_v1',
      );
    }
    if (legacyClient &&
        method == 'POST' &&
        path == '/sync/push' &&
        body is String) {
      final request = jsonDecode(body) as Map<String, dynamic>;
      final capabilities = request['capabilities'];
      if (capabilities is List) {
        request['capabilities'] = capabilities
            .where((value) => value != 'todo_recurrence_v1')
            .toList();
      }
      final ops = request['ops'];
      if (ops is List) {
        for (final op in ops.whereType<Map<String, dynamic>>()) {
          final fields = op['fields'];
          if (fields is Map) {
            fields.remove('recurrenceSpec');
            fields.remove('recurrenceRevision');
            fields.remove('recurrenceLegacyState');
          }
        }
      }
      requestBody = jsonEncode(request);
    }
    final response = await _inner.send(
      method: method,
      path: requestPath,
      headers: headers,
      body: requestBody,
    );
    if (!legacyClient) return response;
    if (method == 'GET' && path == '/sync/capabilities') {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final capabilities = payload['capabilities'];
      if (capabilities is List) {
        payload['capabilities'] = capabilities
            .where((value) => value != 'todo_recurrence_v1')
            .toList();
      }
      return SyncHttpResponse(
        statusCode: response.statusCode,
        body: jsonEncode(payload),
      );
    }
    if ((method == 'POST' && path == '/sync/push') ||
        (method == 'GET' && path.startsWith('/sync/pull?'))) {
      final payload = jsonDecode(response.body);
      _stripRecurrenceGroup(payload);
      return SyncHttpResponse(
        statusCode: response.statusCode,
        body: jsonEncode(payload),
      );
    }
    return response;
  }

  void _stripRecurrenceGroup(Object? value) {
    if (value is Map) {
      value.remove('recurrenceSpec');
      value.remove('recurrenceRevision');
      value.remove('recurrenceLegacyState');
      for (final child in value.values) {
        _stripRecurrenceGroup(child);
      }
    } else if (value is List) {
      for (final child in value) {
        _stripRecurrenceGroup(child);
      }
    }
  }

  @override
  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  }) {
    if (!online) return Future.error(const SyncTransportException(0));
    return _inner.openStream(path: path, headers: headers);
  }
}

/// Explicit round driver: requestRound() + wait until the engine is
/// stably idle (several consecutive polls) so a coalesced follow-up round
/// cannot still be in flight when assertions run. Also pins cursor
/// monotonicity on every driven round.
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

Future<int> _createEvent(
  _Device d, {
  required String summary,
  required DateTime start,
  required DateTime end,
  String? description,
}) {
  return d.db.transaction(() async {
    final id = await d.db
        .into(d.db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: d.calendarId,
            summary: summary,
            startDt: start,
            endDt: end,
            description: Value(description),
          ),
        );
    await SyncOutbox.enqueueUpsert(d.db, RecordType.event, id);
    return id;
  });
}

Future<void> _editEvent(
  _Device d,
  int localId, {
  String? summary,
  DateTime? start,
  DateTime? end,
  String? description,
}) {
  return d.db.transaction(() async {
    await (d.db.update(d.db.events)..where((t) => t.id.equals(localId))).write(
      EventsCompanion(
        summary: summary == null ? const Value.absent() : Value(summary),
        startDt: start == null ? const Value.absent() : Value(start),
        endDt: end == null ? const Value.absent() : Value(end),
        description: description == null
            ? const Value.absent()
            : Value(description),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncOutbox.enqueueUpsert(d.db, RecordType.event, localId);
  });
}

Future<void> _deleteEvent(_Device d, int localId) {
  return d.db.transaction(() async {
    final now = DateTime.now();
    await (d.db.update(d.db.events)..where((t) => t.id.equals(localId))).write(
      EventsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await SyncOutbox.enqueueDelete(d.db, RecordType.event, localId);
  });
}

Future<Event> _eventBySyncId(AppDatabase db, String syncId) async {
  final row = await (db.select(
    db.events,
  )..where((t) => t.syncId.equals(syncId))).getSingleOrNull();
  expect(row, isNotNull, reason: 'record $syncId must exist');
  return row!;
}

Future<String> _syncIdOf(AppDatabase db, int localId) async {
  final row = await (db.select(
    db.events,
  )..where((t) => t.id.equals(localId))).getSingle();
  expect(row.syncId, isNotNull, reason: 'row must be enqueued at least once');
  return row.syncId!;
}

void _expectConverged(Event x, Event y, {required String reason}) {
  expect(y.summary, x.summary, reason: '$reason: summary');
  expect(y.startDt, x.startDt, reason: '$reason: startDt');
  expect(y.endDt, x.endDt, reason: '$reason: endDt');
  expect(y.description, x.description, reason: '$reason: description');
  expect(y.location, x.location, reason: '$reason: location');
  expect(y.isAllDay, x.isAllDay, reason: '$reason: isAllDay');
  expect(y.rrule, x.rrule, reason: '$reason: rrule');
  expect(y.deletedAt, x.deletedAt, reason: '$reason: deletedAt');
  expect(y.createdAt, x.createdAt, reason: '$reason: createdAt');
  expect(y.updatedAt, x.updatedAt, reason: '$reason: updatedAt');
  expect(y.serverRev, x.serverRev, reason: '$reason: serverRev');
  expect(y.syncId, x.syncId, reason: '$reason: syncId');
  expect(y.calendarId, x.calendarId, reason: '$reason: calendarId');
}

void main() {
  // Two devices = two intentional AppDatabase instances per test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late srv.AppServer app;
  late HttpServer http;
  late Directory tempDir;
  late String baseUrl;
  late _Device a;
  late _Device b;
  var registerSeq = 0;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dayspark_e2e_');
    app = srv.AppServer(
      srv.Config(
        dbPath: '${tempDir.path}/server.db',
        port: 0,
        jwtSecret: 'e2e-secret',
      ),
    );
    http = await app.serve();
    baseUrl = 'http://127.0.0.1:${http.port}';

    a = _Device('A', baseUrl);
    b = _Device('B', baseUrl);
    a.calendarId = await _seedCalendar(a.db);
    b.calendarId = await _seedCalendar(b.db);

    // Same user, two devices: register once on A, hand the token pair to
    // both token stores (protocol is per-user; each device keeps its own
    // stores/engine/cursor).
    final session = await a.api.register(
      email: 'e2e-${registerSeq++}@dayspark.test',
      password: 'password123',
    );
    await a.tokens.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await b.tokens.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    await a.engine.start();
    await b.engine.start();
    await _round(a);
    await _round(b);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await http.close(force: true);
    await app.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('create on A appears on B after both rounds', () async {
    final localId = await _createEvent(
      a,
      summary: 'standup',
      start: DateTime(2026, 9, 24, 10),
      end: DateTime(2026, 9, 24, 11),
      description: 'daily sync',
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);
    expect(onB.summary, 'standup');
    expect(onB.startDt, DateTime(2026, 9, 24, 10));
    expect(onB.serverRev, 1);
    expect(onA.serverRev, 1);
    _expectConverged(onA, onB, reason: 'case 1 create');
  });

  test(
    'recurring instance completion syncs without changing sibling instance',
    () async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2035, 5, 1, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=2',
      );
      final todoId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'series',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );
      await _round(a);
      await _round(b);
      final todoA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final firstOccurrence = OccurrenceId.forNominal(
        spec.anchor.value,
        spec.timeZone,
      ).value;
      final secondOccurrence = OccurrenceId.forNominal(
        LocalDateTime(2035, 5, 2, 9, 0, 0),
        spec.timeZone,
      ).value;
      final firstAllocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: todoId,
          occurrenceId: firstOccurrence,
          startAt: DateTime.utc(2035, 5, 3, 1),
          endAt: DateTime.utc(2035, 5, 3, 2),
        ),
      );
      final secondAllocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: todoId,
          occurrenceId: secondOccurrence,
          startAt: DateTime.utc(2035, 5, 4, 1),
          endAt: DateTime.utc(2035, 5, 4, 2),
        ),
      );
      await _round(a);
      await _round(b);
      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.setCompletion(
          a.db,
          tx,
          todoId,
          isCompleted: true,
          occurrenceId: firstOccurrence,
        ),
      );
      await _round(a);
      await _round(b);

      final todoB = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(todoA.syncId!))).getSingle();
      final firstAllocationB = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.occurrenceId.equals(firstOccurrence))).getSingle();
      final secondAllocationB = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.occurrenceId.equals(secondOccurrence))).getSingle();
      final instanceStateB = await (b.db.select(
        b.db.taskInstanceStates,
      )..where((row) => row.occurrenceId.equals(firstOccurrence))).getSingle();
      expect(todoB.status, 'NEEDS-ACTION');
      expect(instanceStateB.status, 'completed');
      expect(firstAllocationB.state, 'invalidatedByCompletion');
      expect(secondAllocationB.state, 'active');

      await RecordScope.run(
        b.db,
        (tx) => TodoWriter.setCompletion(
          b.db,
          tx,
          todoB.id,
          isCompleted: false,
          occurrenceId: firstOccurrence,
        ),
      );
      await _round(b);
      await _round(a);
      final reopenedA = await (a.db.select(
        a.db.taskInstanceStates,
      )..where((row) => row.occurrenceId.equals(firstOccurrence))).getSingle();
      final stillInvalidatedA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(firstAllocationId))).getSingle();
      final stillActiveA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(secondAllocationId))).getSingle();
      expect(reopenedA.status, 'pending');
      expect(stillInvalidatedA.state, 'invalidatedByCompletion');
      expect(stillActiveA.state, 'active');
    },
  );

  test(
    'occurrence allocation round trips its series and occurrence ids',
    () async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2035, 5, 1, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=WEEKLY;COUNT=2',
      );
      final todoId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'occurrence sync',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );
      final todo = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final occurrenceId = OccurrenceId.forNominal(
        spec.anchor.value,
        spec.timeZone,
      ).value;
      final allocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: todoId,
          occurrenceId: occurrenceId,
          startAt: DateTime.utc(2035, 4, 30, 20),
          endAt: DateTime.utc(2035, 4, 30, 21),
        ),
      );
      await _round(a);
      await _round(b);
      final allocationA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(allocationId))).getSingle();
      final todoB = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(todo.syncId!))).getSingle();
      final allocationB = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.syncId.equals(allocationA.syncId!))).getSingle();
      expect(todoB.syncId, todo.syncId);
      expect(allocationB.todoSyncId, todo.syncId);
      expect(allocationB.occurrenceId, occurrenceId);
    },
  );

  test(
    'R4 real sync path covers series edits, confirmations, and removal',
    () async {
      RecurrenceSpec spec(String zone, String rule) => RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2035, 5, 1, 9, 0, 0),
        ),
        timeZone: zone,
        rrule: rule,
      );

      Future<Todo> todoBySyncId(AppDatabase db, String syncId) async =>
          (await (db.select(
            db.todos,
          )..where((row) => row.syncId.equals(syncId))).getSingle());

      Future<TaskAllocation> allocationBySyncId(
        AppDatabase db,
        String syncId,
      ) async => (await (db.select(
        db.taskAllocations,
      )..where((row) => row.syncId.equals(syncId))).getSingle());

      Future<int> createLegacy(String summary) =>
          RecordScope.run(a.db, (tx) async {
            final id = await a.db
                .into(a.db.todos)
                .insert(
                  TodosCompanion.insert(
                    calendarId: a.calendarId,
                    summary: summary,
                    startDate: Value(DateTime.utc(2035, 5, 1, 9)),
                    rrule: const Value('FREQ=WEEKLY;COUNT=4'),
                    recurrenceLegacyState: const Value('unknownLegacy'),
                    recurrenceEvidence: Value(
                      const LegacyRecurrenceEvidence(
                        source: 'ics',
                        timeSemantic: 'floating',
                      ).encode(),
                    ),
                  ),
                );
            await SyncOutbox.enqueueUpsert(a.db, RecordType.todo, id);
            tx.applied(RecordType.todo, id);
            return id;
          });

      final initialSpec = spec('Asia/Shanghai', 'FREQ=WEEKLY;COUNT=4');
      final seriesId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'R4 series',
            rrule: Value(initialSpec.rule.canonical),
          ),
          recurrenceSpec: initialSpec,
        ),
      );
      final seriesA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(seriesId))).getSingle();
      final syncId = seriesA.syncId!;
      await _round(a);
      await _round(b);
      var seriesB = await todoBySyncId(b.db, syncId);
      final seriesSpecB = TodoRecurrence.fromTodo(seriesB).spec!;
      expect(seriesSpecB.timeZone, 'Asia/Shanghai');
      final initialWindow = InstantWindow(
        startInclusive: DateTime.utc(2035, 5, 1),
        endExclusive: DateTime.utc(2035, 6, 1),
      );
      expect(
        const RecurrenceEngine()
            .expand(initialSpec, window: initialWindow, limit: 10)
            .map((item) => item.occurrenceId.value),
        const RecurrenceEngine()
            .expand(seriesSpecB, window: initialWindow, limit: 10)
            .map((item) => item.occurrenceId.value),
      );

      final secondNominal = (initialSpec.anchor.value as LocalDateTime)
          .addCalendarDays(7);
      final oldId = OccurrenceId.forNominal(
        secondNominal,
        initialSpec.timeZone,
      ).value;
      final firstAllocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: seriesId,
          occurrenceId: oldId,
          startAt: DateTime.utc(2035, 5, 8, 1),
          endAt: DateTime.utc(2035, 5, 8, 2),
        ),
      );
      await _round(a);
      await _round(b);
      final firstAllocationA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(firstAllocationId))).getSingle();
      final firstAllocationB = await allocationBySyncId(
        b.db,
        firstAllocationA.syncId!,
      );
      expect(firstAllocationB.occurrenceId, oldId);

      final zoneEdited = spec('Asia/Tokyo', 'FREQ=WEEKLY;COUNT=4');
      await RecordScope.run(
        b.db,
        (tx) => TodoWriter.updateTodo(
          b.db,
          tx,
          seriesB.id,
          TodosCompanion(updatedAt: Value(DateTime.now())),
          recurrenceSpec: zoneEdited,
          replaceRecurrence: true,
        ),
      );
      await _round(b);
      await _round(a);
      final afterZoneA = await todoBySyncId(a.db, syncId);
      seriesB = await todoBySyncId(b.db, syncId);
      expect(TodoRecurrence.fromTodo(afterZoneA).spec!.timeZone, 'Asia/Tokyo');
      expect(isOccurrenceStillValidForSeries(afterZoneA, oldId), isFalse);
      expect(isOccurrenceStillValidForSeries(seriesB, oldId), isFalse);
      final unchangedFirstA = await allocationBySyncId(
        a.db,
        firstAllocationA.syncId!,
      );
      final unchangedFirstB = await allocationBySyncId(
        b.db,
        firstAllocationA.syncId!,
      );
      expect(unchangedFirstA.startAt, firstAllocationA.startAt);
      expect(unchangedFirstA.endAt, firstAllocationA.endAt);
      expect(unchangedFirstA.occurrenceId, oldId);
      expect(unchangedFirstB.startAt, firstAllocationB.startAt);
      expect(unchangedFirstB.endAt, firstAllocationB.endAt);
      expect(unchangedFirstB.occurrenceId, oldId);

      final tokyoSecondId = OccurrenceId.forNominal(
        secondNominal,
        'Asia/Tokyo',
      ).value;
      final secondAllocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: afterZoneA.id,
          occurrenceId: tokyoSecondId,
          startAt: DateTime.utc(2035, 5, 8, 3),
          endAt: DateTime.utc(2035, 5, 8, 4),
        ),
      );
      await _round(a);
      await _round(b);
      final secondAllocationA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(secondAllocationId))).getSingle();
      final monthly = spec('Asia/Tokyo', 'FREQ=MONTHLY;COUNT=3');
      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.updateTodo(
          a.db,
          tx,
          afterZoneA.id,
          TodosCompanion(updatedAt: Value(DateTime.now())),
          recurrenceSpec: monthly,
          replaceRecurrence: true,
        ),
      );
      await _round(a);
      await _round(b);
      final afterRuleB = await todoBySyncId(b.db, syncId);
      expect(
        TodoRecurrence.fromTodo(afterRuleB).spec!.rule.canonical,
        'FREQ=MONTHLY;COUNT=3',
      );
      expect(
        isOccurrenceStillValidForSeries(afterRuleB, tokyoSecondId),
        isFalse,
      );
      final unchangedSecondB = await allocationBySyncId(
        b.db,
        secondAllocationA.syncId!,
      );
      expect(unchangedSecondB.startAt, secondAllocationA.startAt);
      expect(unchangedSecondB.endAt, secondAllocationA.endAt);
      expect(unchangedSecondB.occurrenceId, tokyoSecondId);

      final legacyId = await createLegacy('Confirmed from A');
      await _round(a);
      final legacyA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(legacyId))).getSingle();
      await _round(b);
      final legacyB = await todoBySyncId(b.db, legacyA.syncId!);
      expect(legacyB.recurrenceLegacyState, 'unknownLegacy');
      final syncedEvidence = LegacyRecurrenceEvidence.decode(
        legacyB.recurrenceEvidence,
      );
      expect(syncedEvidence?.source, 'sync');
      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.confirmLegacyRecurrence(
          a.db,
          tx,
          todoId: legacyA.id,
          chosenTimeZone: 'Asia/Tokyo',
          interpretation: RecurrenceAnchor(
            source: RecurrenceAnchorSource.start,
            value: LocalDateTime(2035, 5, 1, 9, 0, 0),
          ),
          validatedRRule: legacyA.rrule!,
        ),
      );
      await _round(a);
      await _round(b);
      final confirmedA = await todoBySyncId(a.db, legacyA.syncId!);
      final confirmedB = await todoBySyncId(b.db, legacyA.syncId!);
      final confirmedSpecA = TodoRecurrence.fromTodo(confirmedA).spec!;
      final confirmedSpecB = TodoRecurrence.fromTodo(confirmedB).spec!;
      expect(confirmedSpecA.timeZone, 'Asia/Tokyo');
      expect(confirmedSpecA.timeZone, confirmedSpecB.timeZone);
      expect(confirmedSpecA.rule.canonical, confirmedSpecB.rule.canonical);
      final recurrenceWindow = InstantWindow(
        startInclusive: DateTime.utc(2035, 5, 1),
        endExclusive: DateTime.utc(2035, 7, 1),
      );
      expect(
        const RecurrenceEngine()
            .expand(confirmedSpecA, window: recurrenceWindow, limit: 10)
            .map((row) => row.occurrenceId.value),
        const RecurrenceEngine()
            .expand(confirmedSpecB, window: recurrenceWindow, limit: 10)
            .map((row) => row.occurrenceId.value),
      );

      final conflictId = await createLegacy('Concurrent confirmations');
      await _round(a);
      final conflictA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(conflictId))).getSingle();
      await _round(b);
      final conflictB = await todoBySyncId(b.db, conflictA.syncId!);
      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.confirmLegacyRecurrence(
          a.db,
          tx,
          todoId: conflictA.id,
          chosenTimeZone: 'America/New_York',
          interpretation: RecurrenceAnchor(
            source: RecurrenceAnchorSource.start,
            value: LocalDateTime(2035, 5, 1, 9, 0, 0),
          ),
          validatedRRule: conflictA.rrule!,
        ),
      );
      await RecordScope.run(
        b.db,
        (tx) => TodoWriter.confirmLegacyRecurrence(
          b.db,
          tx,
          todoId: conflictB.id,
          chosenTimeZone: 'Asia/Tokyo',
          interpretation: RecurrenceAnchor(
            source: RecurrenceAnchorSource.start,
            value: LocalDateTime(2035, 5, 1, 9, 0, 0),
          ),
          validatedRRule: conflictB.rrule!,
        ),
      );
      await _round(a);
      await _round(b);
      await _round(a);
      final conflictFinalA = await todoBySyncId(a.db, conflictA.syncId!);
      final conflictFinalB = await todoBySyncId(b.db, conflictA.syncId!);
      final conflictSpecA = TodoRecurrence.fromTodo(conflictFinalA).spec!;
      final conflictSpecB = TodoRecurrence.fromTodo(conflictFinalB).spec!;
      expect(conflictSpecA.timeZone, conflictSpecB.timeZone);
      expect(conflictSpecA.rule.canonical, conflictSpecB.rule.canonical);
      expect(
        conflictFinalA.recurrenceRevision,
        conflictFinalB.recurrenceRevision,
      );

      final removeSpec = spec('Asia/Shanghai', 'FREQ=WEEKLY;COUNT=3');
      final removeId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'Remove recurrence',
            rrule: Value(removeSpec.rule.canonical),
          ),
          recurrenceSpec: removeSpec,
        ),
      );
      final removeA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(removeId))).getSingle();
      final removeOccurrenceId = OccurrenceId.forNominal(
        removeSpec.anchor.value,
        removeSpec.timeZone,
      ).value;
      final removeAllocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: removeId,
          occurrenceId: removeOccurrenceId,
          startAt: DateTime.utc(2035, 5, 1, 1),
          endAt: DateTime.utc(2035, 5, 1, 2),
        ),
      );
      await _round(a);
      await _round(b);
      final removeAllocationA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(removeAllocationId))).getSingle();
      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.updateTodo(
          a.db,
          tx,
          removeId,
          TodosCompanion(updatedAt: Value(DateTime.now())),
          replaceRecurrence: true,
        ),
      );
      await _round(a);
      await _round(b);
      final removedB = await todoBySyncId(b.db, removeA.syncId!);
      final retainedAllocationB = await allocationBySyncId(
        b.db,
        removeAllocationA.syncId!,
      );
      expect(TodoRecurrence.fromTodo(removedB).spec, isNull);
      expect(retainedAllocationB.occurrenceId, removeOccurrenceId);
      expect(
        isOccurrenceStillValidForSeries(removedB, removeOccurrenceId),
        isFalse,
      );
    },
  );

  test(
    'old-client projection preserves RecurrenceSpec and capability recovery backfills',
    () async {
      b.transport.legacyClient = true;
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2036, 2, 2, 10, 0, 0),
        ),
        timeZone: 'America/New_York',
        rrule: 'FREQ=WEEKLY;COUNT=6',
      );
      final recurringId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'New recurring Todo',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );
      final ordinaryId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'Ordinary Todo',
          ),
        ),
      );
      final eventId = await _createEvent(
        a,
        summary: 'Ordinary Event',
        start: DateTime.utc(2036, 2, 2, 12),
        end: DateTime.utc(2036, 2, 2, 13),
      );
      await _round(a);
      await _round(b);
      final recurringA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(recurringId))).getSingle();
      final recurringB = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(recurringA.syncId!))).getSingle();
      final ordinaryA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(ordinaryId))).getSingle();
      final ordinaryB = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(ordinaryA.syncId!))).getSingle();
      final eventA = await (a.db.select(
        a.db.events,
      )..where((row) => row.id.equals(eventId))).getSingle();
      final eventB = await (b.db.select(
        b.db.events,
      )..where((row) => row.syncId.equals(eventA.syncId!))).getSingle();
      expect(ordinaryB.summary, 'Ordinary Todo');
      expect(eventB.summary, 'Ordinary Event');
      expect(recurringB.rrule, spec.rule.canonical);
      expect(recurringB.recurrenceLegacyState, 'unknownLegacy');
      expect(TodoRecurrence.fromTodo(recurringB).spec, isNull);
      final oldCursor = b.cursors.value!;

      await b.db.transaction(() async {
        await (b.db.update(
          b.db.todos,
        )..where((row) => row.id.equals(recurringB.id))).write(
          TodosCompanion(
            summary: const Value('Edited by old client'),
            description: const Value('Old notes'),
            rrule: const Value('FREQ=DAILY;COUNT=9'),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await SyncOutbox.enqueueUpsert(b.db, RecordType.todo, recurringB.id);
      });
      await _round(b);
      await _round(a);
      final preservedA = await (a.db.select(
        a.db.todos,
      )..where((row) => row.syncId.equals(recurringA.syncId!))).getSingle();
      final preservedSpec = TodoRecurrence.fromTodo(preservedA).spec!;
      expect(preservedA.summary, 'Edited by old client');
      expect(preservedA.description, 'Old notes');
      expect(preservedA.rrule, spec.rule.canonical);
      expect(preservedSpec.timeZone, spec.timeZone);
      expect(preservedSpec.rule.canonical, spec.rule.canonical);
      expect(b.cursors.value, greaterThan(oldCursor));

      b.transport.legacyClient = false;
      final beforeRecovery = b.cursors.value!;
      await _round(b);
      final recovered = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(recurringA.syncId!))).getSingle();
      expect(b.cursors.value, greaterThanOrEqualTo(beforeRecovery));
      expect(TodoRecurrence.fromTodo(recovered).spec!.timeZone, spec.timeZone);
      expect(
        TodoRecurrence.fromTodo(recovered).spec!.rule.canonical,
        spec.rule.canonical,
      );
    },
  );

  test(
    'TaskAllocation create and completion invalidation converge over sync',
    () async {
      final todoId = await RecordScope.run(
        a.db,
        (tx) => TodoWriter.create(
          a.db,
          tx,
          TodosCompanion.insert(
            calendarId: a.calendarId,
            summary: 'focus block',
          ),
        ),
      );
      final todo = await (a.db.select(
        a.db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final allocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: todoId,
          startAt: DateTime.utc(2035, 5, 1, 10),
          endAt: DateTime.utc(2035, 5, 1, 11),
        ),
      );
      await _round(a);
      final allocationA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(allocationId))).getSingle();
      expect(todo.syncId, isNotNull);
      expect(allocationA.syncId, isNotNull);
      await _round(b);

      final remoteTodo = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(todo.syncId!))).getSingle();
      final remoteAllocation = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.syncId.equals(allocationA.syncId!))).getSingle();
      expect(remoteAllocation.todoId, remoteTodo.id);
      expect(remoteAllocation.state, 'active');

      // A moves the interval while B is offline. B then cancels from its
      // older snapshot; the server must merge both independent field edits.
      b.transport.online = false;
      await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.reschedule(
          a.db,
          tx,
          id: allocationId,
          startAt: DateTime.utc(2035, 5, 1, 12),
          endAt: DateTime.utc(2035, 5, 1, 13),
        ),
      );
      await _round(a);
      final rescheduledB = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.syncId.equals(allocationA.syncId!))).getSingle();
      expect(rescheduledB.startAt, DateTime.utc(2035, 5, 1, 10));

      await RecordScope.run(
        b.db,
        (tx) => TaskAllocationWriter.cancel(b.db, tx, rescheduledB.id),
      );
      await b.engine.requestRound();
      expect(b.engine.status.phase, SyncPhase.error);
      b.transport.online = true;
      await _round(b);
      await _round(a);
      final cancelledA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(allocationId))).getSingle();
      expect(cancelledA.state, 'cancelledByUser');
      expect(cancelledA.startAt, DateTime.utc(2035, 5, 1, 12));

      final futureAllocationId = await RecordScope.run(
        a.db,
        (tx) => TaskAllocationWriter.create(
          a.db,
          tx,
          todoId: todoId,
          startAt: DateTime.utc(2035, 5, 2, 10),
          endAt: DateTime.utc(2035, 5, 2, 11),
        ),
      );
      await _round(a);
      await _round(b);
      final futureA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(futureAllocationId))).getSingle();

      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.setCompletion(a.db, tx, todoId, isCompleted: true),
      );
      await _round(a);
      await _round(b);
      final completedA = await (a.db.select(
        a.db.taskAllocations,
      )..where((row) => row.id.equals(futureAllocationId))).getSingle();
      final completedB = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.syncId.equals(futureA.syncId!))).getSingle();
      expect(completedA.state, 'invalidatedByCompletion');
      expect(completedB.state, 'invalidatedByCompletion');

      await RecordScope.run(
        a.db,
        (tx) => TodoWriter.permanentDelete(a.db, tx, todoId),
      );
      await _round(a);
      await _round(b);
      expect(
        await (b.db.select(
          b.db.todos,
        )..where((row) => row.syncId.equals(todo.syncId!))).get(),
        isEmpty,
      );
      expect(
        await (b.db.select(
          b.db.taskAllocations,
        )..where((row) => row.todoSyncId.equals(todo.syncId!))).get(),
        isEmpty,
      );
      expect(await (a.db.select(a.db.syncOutbox)).get(), isEmpty);
      expect(await (b.db.select(b.db.syncOutbox)).get(), isEmpty);
    },
  );

  test(
    'Allocation arriving before its Todo remains unresolved and later binds',
    () async {
      const todoSyncId = 'remote-parent-before-todo';
      const allocationSyncId = 'remote-allocation-before-todo';
      final allocationPayload = <String, dynamic>{
        'todoSyncId': todoSyncId,
        'occurrenceId': null,
        'startAt': '2035-06-01T10:00:00.000Z',
        'endAt': '2035-06-01T11:00:00.000Z',
        'state': 'active',
        'createdAt': '2035-01-01T00:00:00.000Z',
        'updatedAt': '2035-01-01T00:00:00.000Z',
      };
      final allocationResult = await b.api.push(
        PushRequest(
          deviceId: 'device-B',
          capabilities: const [SyncCapability.taskAllocationV1],
          ops: [
            PushOp(
              opId: 'push-orphan-allocation',
              op: OpType.upsert,
              recordId: allocationSyncId,
              type: RecordType.taskAllocation,
              fields: allocationPayload,
              baseRev: 0,
            ),
          ],
        ),
      );
      expect(allocationResult.results.single.status, OpStatus.applied);
      await _round(b);
      final unresolved = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.syncId.equals(allocationSyncId))).getSingle();
      expect(unresolved.todoId, isNull);
      expect(unresolved.todoSyncId, todoSyncId);

      final todoResult = await b.api.push(
        PushRequest(
          deviceId: 'device-B',
          ops: [
            PushOp(
              opId: 'push-parent-todo',
              op: OpType.upsert,
              recordId: todoSyncId,
              type: RecordType.todo,
              fields: {
                'calendarId': b.calendarId,
                'summary': 'Late parent',
                'dueDate': null,
                'startDate': null,
                'priority': 0,
                'status': 'NEEDS-ACTION',
                'description': null,
                'rrule': null,
                'completedAt': null,
                'percentComplete': 0,
                'deletedAt': null,
                'createdAt': '2035-01-01T00:00:00.000Z',
                'updatedAt': '2035-01-01T00:00:00.000Z',
                'sortOrder': 0,
                'parentSyncId': null,
              },
              baseRev: 0,
            ),
          ],
        ),
      );
      expect(todoResult.results.single.status, OpStatus.applied);
      await _round(b);
      final resolvedTodo = await (b.db.select(
        b.db.todos,
      )..where((row) => row.syncId.equals(todoSyncId))).getSingle();
      final resolvedAllocation = await (b.db.select(
        b.db.taskAllocations,
      )..where((row) => row.syncId.equals(allocationSyncId))).getSingle();
      expect(resolvedAllocation.todoId, resolvedTodo.id);
      expect(resolvedAllocation.state, 'active');
      expect(await (b.db.select(b.db.syncOutbox)).get(), isEmpty);
    },
  );

  test(
    'edit title+time on A converges to the same merged truth on B',
    () async {
      final localId = await _createEvent(
        a,
        summary: 'planning',
        start: DateTime(2026, 9, 25, 9),
        end: DateTime(2026, 9, 25, 10),
      );
      await _round(a);
      final syncId = await _syncIdOf(a.db, localId);
      await _round(b);

      await _editEvent(
        a,
        localId,
        summary: 'planning (moved)',
        start: DateTime(2026, 9, 25, 14),
        end: DateTime(2026, 9, 25, 15, 30),
      );
      await _round(a);
      await _round(b);

      final onA = await _eventBySyncId(a.db, syncId);
      final onB = await _eventBySyncId(b.db, syncId);
      expect(onB.summary, 'planning (moved)');
      expect(onB.startDt, DateTime(2026, 9, 25, 14));
      expect(onB.endDt, DateTime(2026, 9, 25, 15, 30));
      expect(onB.serverRev, 2, reason: 'edit bumps rev once');
      _expectConverged(onA, onB, reason: 'case 2 edit');
    },
  );

  test('delete on A tombstones the record on B', () async {
    final localId = await _createEvent(
      a,
      summary: 'cancelled meeting',
      start: DateTime(2026, 9, 26, 13),
      end: DateTime(2026, 9, 26, 14),
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);

    await _deleteEvent(a, localId);
    await _round(a);
    await _round(b);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);
    expect(onA.deletedAt, isNotNull, reason: 'A trashes locally');
    expect(onB.deletedAt, isNotNull, reason: 'B mirrors the tombstone');
    expect(onB.serverRev, 2);
    _expectConverged(onA, onB, reason: 'case 3 delete');
  });

  test('offline edit on B + concurrent edit on A → server truth wins, '
      'both devices converge', () async {
    final localId = await _createEvent(
      a,
      summary: 'shared note',
      start: DateTime(2026, 9, 27, 9),
      end: DateTime(2026, 9, 27, 10),
      description: 'original',
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);
    final localB = (await _eventBySyncId(b.db, syncId)).id;

    // --- B goes offline: every transport call is refused. ---
    b.transport.online = false;
    await _editEvent(
      b,
      localB,
      summary: 'B offline title',
      start: DateTime(2026, 9, 27, 11),
      end: DateTime(2026, 9, 27, 12),
    );
    // A edits the same record meanwhile (disjoint field: description).
    await _editEvent(a, localId, description: 'A online description');
    await _round(a);

    // A round while offline must fail cleanly and keep the pending op.
    await b.engine.requestRound();
    expect(
      b.engine.status.phase,
      SyncPhase.error,
      reason: 'offline round surfaces a transport error',
    );
    expect(
      await (b.db.select(b.db.syncOutbox)).get(),
      isNotEmpty,
      reason: 'failed round must not drop the pending op',
    );

    // --- B comes back online. ---
    b.transport.online = true;
    await _round(b);
    await _round(a);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);

    // Documented LWW (server/lib/src/sync/lww.dart): keys each op SET win
    // in op arrival order. B's offline push reached the server last, so it
    // owns summary/start/end; A set description only, so that key keeps
    // A's value — field-level merge, no lost update on either side.
    expect(onB.summary, 'B offline title');
    expect(onB.startDt, DateTime(2026, 9, 27, 11));
    expect(onB.description, 'A online description');
    expect(onB.serverRev, 3, reason: 'create + A edit + B edit = rev 3');
    _expectConverged(onA, onB, reason: 'case 4 offline conflict');
    expect(a.engine.status.lastRejected, isEmpty);
    expect(b.engine.status.lastRejected, isEmpty);
    expect(
      await (b.db.select(b.db.syncOutbox)).get(),
      isEmpty,
      reason: 'B outbox drained after reconnect',
    );
  });

  test(
    'two rounds of alternating edits converge; cursors stay monotonic',
    () async {
      final localId = await _createEvent(
        a,
        summary: 'round 0',
        start: DateTime(2026, 9, 28, 8),
        end: DateTime(2026, 9, 28, 9),
      );
      await _round(a);
      final syncId = await _syncIdOf(a.db, localId);
      await _round(b);
      final localB = (await _eventBySyncId(b.db, syncId)).id;

      final trace = <String, List<int>>{
        'A': [a.cursors.value ?? 0],
        'B': [b.cursors.value ?? 0],
      };

      // Round 1: A edits, B follows.
      await _editEvent(a, localId, summary: 'round 1 (A)');
      await _round(a);
      trace['A']!.add(a.cursors.value ?? 0);
      await _round(b);
      trace['B']!.add(b.cursors.value ?? 0);
      var onA = await _eventBySyncId(a.db, syncId);
      var onB = await _eventBySyncId(b.db, syncId);
      expect(onB.summary, 'round 1 (A)');
      _expectConverged(onA, onB, reason: 'alternating round 1');

      // Round 2: B edits back, A follows.
      await _editEvent(
        b,
        localB,
        summary: 'round 2 (B)',
        start: DateTime(2026, 9, 28, 18),
        end: DateTime(2026, 9, 28, 19),
      );
      await _round(b);
      trace['B']!.add(b.cursors.value ?? 0);
      await _round(a);
      trace['A']!.add(a.cursors.value ?? 0);
      onA = await _eventBySyncId(a.db, syncId);
      onB = await _eventBySyncId(b.db, syncId);
      expect(onA.summary, 'round 2 (B)');
      expect(onB.startDt, DateTime(2026, 9, 28, 18));
      _expectConverged(onA, onB, reason: 'alternating round 2');
      expect(onA.serverRev, 3);

      for (final entry in trace.entries) {
        final values = entry.value;
        for (var i = 1; i < values.length; i++) {
          expect(
            values[i],
            greaterThanOrEqualTo(values[i - 1]),
            reason: '${entry.key} cursor must never go backwards: $values',
          );
        }
        expect(
          values.last,
          greaterThan(values.first),
          reason:
              '${entry.key} cursor must advance across the rounds: '
              '$values',
        );
      }
    },
  );
}
