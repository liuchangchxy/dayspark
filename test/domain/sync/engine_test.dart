import 'dart:async';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/records/record_bus.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark/domain/records/reminder_reconciler.dart';
import 'package:dayspark/domain/sync/sse_listener.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import 'sync_test_support.dart';

class _MockNotificationService extends Mock implements NotificationService {}

/// Arms a write failure on the Nth `UPDATE "events"` inside the round, so a
/// pull batch can be made to blow up *after* its first record already wrote.
class _EventWriteFault extends QueryInterceptor {
  bool armed = false;
  int updates = 0;

  void arm() {
    armed = true;
    updates = 0;
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed && statement.contains('events')) {
      updates++;
      if (updates >= 2) throw StateError('injected event write failure');
    }
    return super.runUpdate(executor, statement, args);
  }
}

/// Remote record helper. The payload carries the UTC ISO form of [startDt],
/// exactly like the server does — the local row holds the same instant.
SyncRecord remoteEvent({
  required String id,
  required DateTime startDt,
  int rev = 2,
  String summary = 'remote',
}) =>
    SyncRecord(
      id: id,
      type: RecordType.event,
      payload: <String, Object?>{
        'calendarId': 1,
        'summary': summary,
        'startDt': startDt.toUtc().toIso8601String(),
        'endDt': startDt.add(const Duration(hours: 1)).toUtc().toIso8601String(),
        'isAllDay': false,
        'description': null,
        'location': null,
        'rrule': null,
        'deletedAt': null,
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-22T00:00:00.000Z',
      },
      rev: rev,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    );

SyncRecord remoteTombstone({
  required String id,
  RecordType type = RecordType.event,
  int rev = 4,
}) =>
    SyncRecord(
      id: id,
      type: type,
      payload: const {},
      rev: rev,
      deleted: true,
      serverTs: DateTime.utc(2026, 9, 23, 9),
    );

SyncRecord remoteTodo({
  required String id,
  required DateTime dueDate,
  int rev = 2,
  String summary = 'remote todo',
}) =>
    SyncRecord(
      id: id,
      type: RecordType.todo,
      payload: <String, Object?>{
        'calendarId': 1,
        'summary': summary,
        'dueDate': dueDate.toUtc().toIso8601String(),
        'startDate': null,
        'priority': 0,
        'status': 'NEEDS-ACTION',
        'description': null,
        'rrule': null,
        'completedAt': null,
        'percentComplete': 0,
        'deletedAt': null,
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-22T00:00:00.000Z',
        'sortOrder': 0,
        'parentSyncId': null,
      },
      rev: rev,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      Reminder(
        id: 0,
        parentType: 'event',
        parentId: 0,
        triggerTime: DateTime(2020),
        isTriggered: false,
      ),
    );
  });

  late AppDatabase db;
  late FakeSyncApiClient api;
  late MemoryCursorStore cursors;
  late MemoryTokenStore tokens;
  late MemorySnapshotStore snapshots;
  late SyncEngine engine;
  late int calendarId;
  late _EventWriteFault fault;

  setUp(() async {
    SharedPreferences.setMockInitialValues({appLocalePrefKey: 'en'});
    fault = _EventWriteFault();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(fault));
    api = FakeSyncApiClient();
    cursors = MemoryCursorStore();
    tokens = MemoryTokenStore(access: 'access-1', refresh: 'refresh-1');
    snapshots = MemorySnapshotStore();
    calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
  });

  tearDown(() async {
    await engine.stop();
    await api.cursorController.close();
    await db.close();
  });

  SyncEngine buildEngine() {
    engine = SyncEngine(
      db: db,
      api: api,
      cursorStore: cursors,
      tokenStore: tokens,
      snapshots: snapshots,
      deviceId: 'device-under-test',
    );
    return engine;
  }

  Future<int> insertEvent(String summary) => db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calendarId,
          summary: summary,
          startDt: DateTime(2026, 9, 24, 10),
          endDt: DateTime(2026, 9, 24, 11),
        ),
      );

  // Hand-picked clock so every reminder expectation below is an absolute,
  // hand-computed literal (2026-06-01 12:00 is before every fixture date).
  final now = DateTime(2026, 6, 1, 12);

  Future<int> insertEventWithReminder({
    required DateTime startDt,
    required DateTime triggerTime,
    String? syncId,
    List<DateTime> extraTriggerTimes = const [],
  }) async {
    final id = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'seam fixture',
            startDt: startDt,
            endDt: startDt.add(const Duration(hours: 1)),
            syncId: Value(syncId),
          ),
        );
    for (final trigger in <DateTime>[triggerTime, ...extraTriggerTimes]) {
      await db.into(db.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: id,
              triggerTime: trigger,
            ),
          );
    }
    return id;
  }

  Future<int> insertTodoWithReminder({
    required DateTime dueDate,
    required DateTime triggerTime,
    String? syncId,
    List<DateTime> extraTriggerTimes = const [],
  }) async {
    final id = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'seam todo fixture',
            dueDate: Value(dueDate),
            status: const Value('NEEDS-ACTION'),
            syncId: Value(syncId),
          ),
        );
    for (final trigger in <DateTime>[triggerTime, ...extraTriggerTimes]) {
      await db.into(db.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: id,
              triggerTime: trigger,
            ),
          );
    }
    return id;
  }

  // Wires the production consumer chain (RecordBus → ReminderReconciler) onto
  // the engine's database and records the platform calls it makes.
  ({
    List<Reminder> schedules,
    List<int> cancels,
    List<List<RecordChange>> batches,
    ReminderReconciler reconciler,
  }) attachReconciler() {
    final notif = _MockNotificationService();
    final schedules = <Reminder>[];
    final cancels = <int>[];
    when(() => notif.cancel(captureAny())).thenAnswer((inv) async {
      cancels.add(inv.positionalArguments.first as int);
    });
    when(
      () => notif.scheduleFromReminder(
        captureAny(),
        eventReminderTitle: any(named: 'eventReminderTitle'),
        todoReminderTitle: any(named: 'todoReminderTitle'),
        eventReminderBody: any(named: 'eventReminderBody'),
        todoReminderBody: any(named: 'todoReminderBody'),
      ),
    ).thenAnswer((inv) async {
      schedules.add(inv.positionalArguments.first as Reminder);
    });
    final batches = <List<RecordChange>>[];
    final reconciler = ReminderReconciler(
      db: db,
      notifications: notif,
      clock: () => now,
    );
    final subscription = RecordBus.of(db).changes.listen((batch) {
      batches.add(batch);
      unawaited(reconciler.handle(batch));
    });
    addTearDown(subscription.cancel);
    return (
      schedules: schedules,
      cancels: cancels,
      batches: batches,
      reconciler: reconciler,
    );
  }

  Future<List<Reminder>> reminderRows(int parentId) =>
      (db.select(db.reminders)..where((t) => t.parentId.equals(parentId)))
          .get();

  Future<Reminder> reminderRow(int parentId) async =>
      (await reminderRows(parentId)).single;

  test('round: drain outbox → push → pull → cursor stored', () async {
    cursors.value = 7;
    final id = await insertEvent('offline edit');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    final pending = await (db.select(db.syncOutbox)).getSingle();

    api.onPush = (request) {
      expect(request.cursor, 7, reason: 'push piggybacks the stored cursor');
      expect(request.deviceId, 'device-under-test');
      expect(request.ops, hasLength(1));
      final op = request.ops.single;
      expect(op.opId, pending.opId);
      expect(op.op, OpType.upsert);
      expect(op.recordId, pending.recordId);
      expect(op.fields!['summary'], 'offline edit');
      expect(op.baseRev, 0);
      return PushResponse(
        results: [
          OpResult(
            opId: op.opId,
            status: OpStatus.applied,
            serverRecord: SyncRecord(
              id: op.recordId,
              type: RecordType.event,
              payload: op.fields!,
              rev: 1,
              deleted: false,
              serverTs: DateTime.utc(2026, 9, 23, 10),
            ),
          ),
        ],
        piggyback: [
          SyncRecord(
            id: 'other-remote',
            type: RecordType.todo,
            payload: {
              'calendarId': calendarId,
              'summary': 'remote todo',
              'dueDate': null,
              'startDate': null,
              'priority': 0,
              'status': 'NEEDS-ACTION',
              'description': null,
              'rrule': null,
              'completedAt': null,
              'percentComplete': 0,
              'deletedAt': null,
              'createdAt': '2026-09-01T00:00:00.000Z',
              'updatedAt': '2026-09-01T00:00:00.000Z',
              'sortOrder': 0,
              'parentSyncId': null,
            },
            rev: 12,
            deleted: false,
            serverTs: DateTime.utc(2026, 9, 23, 10),
          ),
        ],
        cursor: 12,
      );
    };
    api.onPull = (cursor) {
      expect(cursor, 12, reason: 'pull starts at the push watermark');
      return PullResponse(
        changes: [
          SyncRecord(
            id: 'pulled-event',
            type: RecordType.event,
            payload: {
              'calendarId': calendarId,
              'summary': 'pulled',
              'startDt': '2026-09-25T09:00:00.000Z',
              'endDt': '2026-09-25T10:00:00.000Z',
              'isAllDay': false,
              'description': null,
              'location': null,
              'rrule': null,
              'deletedAt': null,
              'createdAt': '2026-09-01T00:00:00.000Z',
              'updatedAt': '2026-09-01T00:00:00.000Z',
            },
            rev: 3,
            deleted: false,
            serverTs: DateTime.utc(2026, 9, 23, 11),
          ),
        ],
        nextCursor: 30,
        hasMore: false,
      );
    };

    await buildEngine().start();

    expect(api.pushCalls, hasLength(1));
    expect(api.pullCalls, [12]);
    expect(cursors.value, 30);
    expect(await (db.select(db.syncOutbox)).get(), isEmpty,
        reason: 'applied op dropped from outbox');
    final pulled = await (db.select(db.events)
          ..where((t) => t.syncId.equals('pulled-event')))
        .getSingle();
    expect(pulled.summary, 'pulled');
    expect(pulled.serverRev, 3);
    final piggybacked = await (db.select(db.todos)
          ..where((t) => t.syncId.equals('other-remote')))
        .getSingle();
    expect(piggybacked.summary, 'remote todo');
    expect(engine.status.phase, SyncPhase.idle);
    expect(engine.status.lastSyncAt, isNotNull);
    expect(engine.status.lastError, isNull);
  });

  test('pull keeps paging while hasMore', () async {
    cursors.value = 0;
    api.onPull = (cursor) {
      if (cursor == 0) {
        return PullResponse(
          changes: const [],
          nextCursor: 20,
          hasMore: true,
        );
      }
      return PullResponse(changes: const [], nextCursor: 40, hasMore: false);
    };

    await buildEngine().start();

    expect(api.pullCalls, [0, 20]);
    expect(cursors.value, 40);
    expect(engine.status.phase, SyncPhase.idle);
  });

  test('conflict: serverRecord overwrites local row and drops pending op',
      () async {
    cursors.value = 0;
    final id = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'local newer edit',
            startDt: DateTime(2026, 9, 24, 10),
            endDt: DateTime(2026, 9, 24, 11),
            serverRev: const Value(3),
          ),
        );
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    final row =
        await (db.select(db.events)..where((t) => t.id.equals(id))).getSingle();
    final recordId = row.syncId!;

    api.onPush = (request) {
      final op = request.ops.single;
      expect(op.baseRev, 3, reason: 'baseRev read from live serverRev');
      return PushResponse(
        results: [
          OpResult(
            opId: op.opId,
            status: OpStatus.conflict,
            code: 'conflict',
            serverRecord: SyncRecord(
              id: op.recordId,
              type: RecordType.event,
              payload: {
                'calendarId': calendarId,
                'summary': 'server wins',
                'startDt': '2026-09-24T10:00:00.000Z',
                'endDt': '2026-09-24T11:00:00.000Z',
                'isAllDay': false,
                'description': null,
                'location': null,
                'rrule': null,
                'deletedAt': null,
                'createdAt': '2026-09-01T00:00:00.000Z',
                'updatedAt': '2026-09-20T00:00:00.000Z',
              },
              rev: 9,
              deleted: false,
              serverTs: DateTime.utc(2026, 9, 23, 10),
            ),
          ),
        ],
        piggyback: const [],
        cursor: 0,
      );
    };

    await buildEngine().start();

    final after =
        await (db.select(db.events)..where((t) => t.id.equals(id))).getSingle();
    expect(after.summary, 'server wins');
    expect(after.serverRev, 9);
    expect(after.syncId, recordId);
    expect(await (db.select(db.syncOutbox)).get(), isEmpty,
        reason: 'conflicting pending op dropped');
    expect(engine.status.phase, SyncPhase.idle);
  });

  test('rejected: op dropped and code surfaced in status', () async {
    cursors.value = 0;
    final id = await insertEvent('bad op');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);

    api.onPush = (request) => PushResponse(
          results: [
            OpResult(
              opId: request.ops.single.opId,
              status: OpStatus.rejected,
              code: 'validation',
            ),
          ],
          piggyback: const [],
          cursor: 0,
        );

    await buildEngine().start();

    expect(await (db.select(db.syncOutbox)).get(), isEmpty);
    expect(engine.status.phase, SyncPhase.idle);
    expect(engine.status.lastRejected, ['validation']);
  });

  test('remote cursor above stored watermark triggers a pull round',
      () async {
    cursors.value = 10;
    final sse = SseListener(
      open: api.openCursorStream,
      onCursor: (cursor) => unawaited(engine.notifyRemoteCursor(cursor)),
    );
    sse.start();
    addTearDown(sse.stop);

    await buildEngine().start();
    expect(api.pullCalls, hasLength(1));

    api.cursorController.add(50);
    await waitUntil(() => api.pullCalls.length >= 2,
        reason: 'SSE cursor signal should kick a round');

    expect(api.pushCalls.length, greaterThanOrEqualTo(2),
        reason: 'each round pushes first');
    expect(cursors.value! >= 10, true);
  });

  test(
      'SSE initial head below stored cursor rewinds the watermark '
      '(restore self-heal); later signals never rewind', () async {
    cursors.value = 50;
    await buildEngine().start();
    expect(cursors.value, 50);

    // Mirrors the provider wiring: initial head → adoptServerHead,
    // every signal → notifyRemoteCursor.
    final sse = SseListener(
      open: api.openCursorStream,
      onCursor: (cursor) => unawaited(engine.notifyRemoteCursor(cursor)),
      onInitialCursor: (head) => unawaited(engine.adoptServerHead(head)),
    );
    sse.start();
    addTearDown(sse.stop);

    // Initial event of the connection: server was restored to head 30
    // while this client sits at 50 — cursor must rewind to 30 and a
    // round must pull from there (otherwise pull(>50) is empty forever).
    api.cursorController.add(30);
    await waitUntil(() => cursors.value == 30,
        reason: 'initial head below stored cursor rewinds the watermark');
    await waitUntil(() => api.pullCalls.contains(30),
        reason: 'rewound cursor round pulls from the restored head');

    // A later signal below the stored cursor is NOT an initial head —
    // it must never rewind (only serverHead < stored on the FIRST event
    // of a connection is a restore).
    api.cursorController.add(20);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cursors.value, 30,
        reason: 'only the initial head of a connection may rewind');
    expect(api.pullCalls.contains(20), isFalse);
  });

  test('unconfigured tokens: start is a no-op', () async {
    tokens.access = null;
    tokens.refresh = null;
    cursors.value = 0;
    final id = await insertEvent('never pushed');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);

    await buildEngine().start();

    expect(api.pushCalls, isEmpty);
    expect(api.pullCalls, isEmpty);
    expect(await (db.select(db.syncOutbox)).get(), hasLength(1));
    expect(engine.status.phase, SyncPhase.idle);
  });

  test('baseline sweep queues pre-existing rows on first configure',
      () async {
    // cursor never written → first round treats this as first configure.
    await insertEvent('legacy event');
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'legacy todo',
          ),
        );
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'legacy trash',
            deletedAt: Value(DateTime(2026, 9, 1)),
          ),
        );

    await buildEngine().start();

    expect(api.pushCalls, hasLength(1));
    final ops = api.pushCalls.single.ops;
    expect(ops, hasLength(2),
        reason: 'live rows queued, trashed-but-never-synced row skipped');
    expect(ops.map((o) => o.type).toSet(), {RecordType.event, RecordType.todo});
    expect(cursors.value, isNotNull);
    expect(await (db.select(db.syncOutbox)).get(), isEmpty);
  });

  test('push after an applied round sends only fields dirty vs last '
      'server truth', () async {
    cursors.value = 0;
    final id = await insertEvent('v1');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    var pushes = 0;
    Map<String, dynamic>? firstPayload;

    api.onPush = (request) {
      pushes++;
      final op = request.ops.single;
      if (pushes == 1) {
        expect(op.fields!['summary'], 'v1');
        firstPayload = op.fields!;
        return PushResponse(
          results: [
            OpResult(
              opId: op.opId,
              status: OpStatus.applied,
              serverRecord: SyncRecord(
                id: op.recordId,
                type: RecordType.event,
                payload: op.fields!,
                rev: 1,
                deleted: false,
                serverTs: DateTime.utc(2026, 9, 23, 10),
              ),
            ),
          ],
          piggyback: const [],
          cursor: request.cursor ?? 0,
        );
      }
      // Second round: only summary + updatedAt changed locally — the op
      // must not resend keys this device never touched, or the server's
      // field-level LWW would clobber another device's concurrent edits.
      expect(op.baseRev, 1);
      expect(op.fields!.keys.toSet(), {'summary', 'updatedAt'},
          reason: 'dirty-fields-only push');
      expect(op.fields!['summary'], 'v2');
      return PushResponse(
        results: [
          OpResult(
            opId: op.opId,
            status: OpStatus.applied,
            serverRecord: SyncRecord(
              id: op.recordId,
              type: RecordType.event,
              payload: {...firstPayload!, ...op.fields!},
              rev: 2,
              deleted: false,
              serverTs: DateTime.utc(2026, 9, 23, 11),
            ),
          ),
        ],
        piggyback: const [],
        cursor: request.cursor ?? 0,
      );
    };

    await buildEngine().start();
    expect(pushes, 1);

    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        summary: const Value('v2'),
        updatedAt: Value(DateTime.utc(2030, 1, 1)),
      ),
    );
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    await engine.requestRound();

    expect(pushes, 2);
    expect(await (db.select(db.syncOutbox)).get(), isEmpty);
    expect(engine.status.phase, SyncPhase.idle);
    expect(engine.status.lastError, isNull);
  });

  group('远端写入必须驱动本机派生态（记录缝）', () {
    test('pull 改期 → 本机该记录的提醒按新时间重排（P2.5#1 的红）', () async {
      final seam = attachReconciler();
      final id = await insertEventWithReminder(
        syncId: 'rec-shift',
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteEvent(id: 'rec-shift', startDt: DateTime(2026, 6, 10, 11)),
            ],
            nextCursor: 5,
            hasMore: false,
          );

      await buildEngine().start();

      await waitUntil(
        () => seam.schedules.length == 1,
        reason: '远端改期必须重挂本机提醒（旧实现把它留在旧时间）',
      );
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));
      expect(seam.cancels, isEmpty);
      expect(
        (await reminderRow(id)).triggerTime,
        DateTime(2026, 6, 10, 10),
        reason: '物化回写：行内值是下一次位移的锚',
      );
    });

    test('pull tombstone → cancel 该记录全部提醒 id（幽灵响铃的红）', () async {
      final seam = attachReconciler();
      final id = await insertEventWithReminder(
        syncId: 'rec-gone',
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
        extraTriggerTimes: [DateTime(2026, 6, 10, 8, 30)],
      );
      final reminderIds =
          (await (db.select(db.reminders)
                    ..where((t) => t.parentId.equals(id)))
                  .get())
              .map((r) => r.id)
              .toList()
            ..sort();
      api.onPull = (cursor) => PullResponse(
            changes: [remoteTombstone(id: 'rec-gone')],
            nextCursor: 4,
            hasMore: false,
          );

      await buildEngine().start();

      await waitUntil(
        () => seam.cancels.length == 2,
        reason: '幽灵响铃：远端删除必须撤掉已排队的通知 id',
      );
      expect(seam.cancels..sort(), reminderIds);
      expect(seam.schedules, isEmpty, reason: 'tombstone 不得顺手再排一条');
    });

    test('pull 改 dueDate → 待办侧提醒按新时间重排（P2.5#1 的 todo 半边）', () async {
      final seam = attachReconciler();
      final id = await insertTodoWithReminder(
        syncId: 'rec-todo-shift',
        dueDate: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteTodo(
                id: 'rec-todo-shift',
                dueDate: DateTime(2026, 6, 10, 11),
              ),
            ],
            nextCursor: 5,
            hasMore: false,
          );

      await buildEngine().start();

      await waitUntil(
        () => seam.schedules.length == 1,
        reason: '远端改 dueDate 必须重挂本机提醒（todo 半边不能只靠 event 的证据）',
      );
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));
      expect(seam.cancels, isEmpty);
      expect(
        (await reminderRow(id)).triggerTime,
        DateTime(2026, 6, 10, 10),
        reason: '物化回写：行内值是下一次位移的锚',
      );
    });

    test('pull todo tombstone → cancel 该待办的具体 reminder id', () async {
      final seam = attachReconciler();
      final id = await insertTodoWithReminder(
        syncId: 'rec-todo-gone',
        dueDate: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
        extraTriggerTimes: [DateTime(2026, 6, 10, 8, 30)],
      );
      final reminderIds =
          (await reminderRows(id)).map((r) => r.id).toList()..sort();
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteTombstone(id: 'rec-todo-gone', type: RecordType.todo),
            ],
            nextCursor: 4,
            hasMore: false,
          );

      await buildEngine().start();

      await waitUntil(
        () => seam.cancels.length == 2,
        reason: 'todo tombstone 必须撤掉该待办已排队的全部通知 id',
      );
      expect(seam.cancels..sort(), reminderIds);
      expect(seam.schedules, isEmpty, reason: 'tombstone 不得顺手再排一条');
    });

    test('push conflict 走 serverRecord 落地 → 同样重排', () async {
      final seam = attachReconciler();
      final id = await insertEventWithReminder(
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );
      await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
      final row =
          await (db.select(db.events)..where((t) => t.id.equals(id)))
              .getSingle();

      api.onPush = (request) => PushResponse(
            results: [
              OpResult(
                opId: request.ops.single.opId,
                status: OpStatus.conflict,
                code: 'conflict',
                serverRecord: remoteEvent(
                  id: row.syncId!,
                  startDt: DateTime(2026, 6, 10, 11),
                  rev: 9,
                ),
              ),
            ],
            piggyback: const [],
            cursor: 0,
          );

      await buildEngine().start();

      await waitUntil(
        () => seam.schedules.length == 1,
        reason: 'conflict 分支的 serverRecord 也走 applier，必须一样重排',
      );
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));
      expect(seam.cancels, isEmpty);
    });

    test('push piggyback 应用 → 同样重排', () async {
      final seam = attachReconciler();
      final id = await insertEventWithReminder(
        syncId: 'rec-piggy',
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );
      api.onPush = (request) => PushResponse(
            results: const [],
            piggyback: [
              remoteEvent(id: 'rec-piggy', startDt: DateTime(2026, 6, 10, 11)),
            ],
            cursor: 8,
          );

      await buildEngine().start();

      await waitUntil(
        () => seam.schedules.length == 1,
        reason: 'piggyback 分支必须与 pull 同一条缝',
      );
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));
      expect((await reminderRow(id)).triggerTime, DateTime(2026, 6, 10, 10));
      expect(seam.cancels, isEmpty);
    });

    test('批次中途抛 → 整批回滚、零平台调用（发布边界 = 事务提交）', () async {
      final seam = attachReconciler();
      final first = await insertEventWithReminder(
        syncId: 'rec-one',
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );

      // 前置相位：先证明这条链真的会排——否则下面的"零调用"是空转断言。
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteEvent(id: 'rec-one', startDt: DateTime(2026, 6, 10, 11)),
            ],
            nextCursor: 2,
            hasMore: false,
          );
      await buildEngine().start();
      await waitUntil(
        () => seam.schedules.length == 1,
        reason: '前置相位必须真的排出一次',
      );
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));
      seam.schedules.clear();
      seam.cancels.clear();
      seam.batches.clear();

      // 第二相位：同批第二条的写入失败 → 第一条虽已写进事务也必须回滚。
      final second = await insertEventWithReminder(
        syncId: 'rec-two',
        startDt: DateTime(2026, 6, 11, 9),
        triggerTime: DateTime(2026, 6, 11, 8),
      );
      fault.arm();
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteEvent(id: 'rec-two', startDt: DateTime(2026, 6, 11, 11)),
              remoteEvent(
                id: 'rec-one',
                startDt: DateTime(2026, 6, 10, 13),
                rev: 3,
              ),
            ],
            nextCursor: 3,
            hasMore: false,
          );
      await engine.requestRound();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seam.batches, isEmpty, reason: '引擎事务是发布边界：回滚 = 零发布');
      expect(seam.schedules, isEmpty, reason: '未提交的登记不得触达平台');
      expect(seam.cancels, isEmpty);
      final rolledBack =
          await (db.select(db.events)..where((t) => t.id.equals(second)))
              .getSingle();
      expect(
        rolledBack.startDt,
        DateTime(2026, 6, 11, 9),
        reason: '批内第一条已写进事务，第二条抛后整批必须回滚',
      );
      expect((await reminderRow(second)).triggerTime, DateTime(2026, 6, 11, 8));
      final untouched =
          await (db.select(db.events)..where((t) => t.id.equals(first)))
              .getSingle();
      expect(untouched.startDt, DateTime(2026, 6, 10, 11));
    });

    test('同一批次被重复投递 → 位移只施加一次（幂等）', () async {
      final seam = attachReconciler();
      final id = await insertEventWithReminder(
        syncId: 'rec-dup',
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteEvent(id: 'rec-dup', startDt: DateTime(2026, 6, 10, 11)),
            ],
            nextCursor: 6,
            hasMore: false,
          );
      await buildEngine().start();
      await waitUntil(() => seam.schedules.length == 1, reason: '前置相位必须真的排出一次');
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));

      // 重放同一批（总线重复投递 / 上游重试）：位移只能发生一次。
      await seam.reconciler.handle(seam.batches.single);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seam.schedules, hasLength(1), reason: '重复投递不得二次位移');
      expect(seam.cancels, isEmpty);
      expect(
        (await reminderRow(id)).triggerTime,
        DateTime(2026, 6, 10, 10),
        reason: '行内值被叠加两次位移就会漂到 12:00',
      );
    });

    test('baseline sweep 只回填身份 → 零调度调用（身份写不动派生态）', () async {
      final seam = attachReconciler();
      await insertEventWithReminder(
        syncId: 'rec-live',
        startDt: DateTime(2026, 6, 10, 9),
        triggerTime: DateTime(2026, 6, 10, 8),
      );

      // 前置相位：同一条链在真实写入下确实会排（防空转）。
      api.onPull = (cursor) => PullResponse(
            changes: [
              remoteEvent(id: 'rec-live', startDt: DateTime(2026, 6, 10, 11)),
            ],
            nextCursor: 2,
            hasMore: false,
          );
      await buildEngine().start();
      await waitUntil(
        () => seam.schedules.length == 1,
        reason: '前置相位必须真的排出一次',
      );
      expect(seam.schedules.single.triggerTime, DateTime(2026, 6, 10, 10));
      seam.schedules.clear();
      seam.cancels.clear();
      seam.batches.clear();

      // 第二相位：一条从未同步过的记录（syncId 为 NULL）等待身份回填。
      final legacy = await insertEventWithReminder(
        startDt: DateTime(2026, 6, 12, 9),
        triggerTime: DateTime(2026, 6, 12, 8),
      );
      cursors.value = null;
      api.onPull = (cursor) =>
          PullResponse(changes: const [], nextCursor: 0, hasMore: false);
      await engine.requestRound();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final swept =
          await (db.select(db.events)..where((t) => t.id.equals(legacy)))
              .getSingle();
      expect(
        swept.syncId,
        isNotNull,
        reason: '这一轮必须真的跑过 baseline sweep，否则零调用无意义',
      );
      expect(seam.batches, isEmpty, reason: '身份回填不发领域事件');
      expect(seam.schedules, isEmpty, reason: '身份写不动派生态');
      expect(seam.cancels, isEmpty);
    });
  });
}
