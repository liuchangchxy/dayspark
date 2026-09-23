import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/sync/sse_listener.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import 'sync_test_support.dart';

void main() {
  late AppDatabase db;
  late FakeSyncApiClient api;
  late MemoryCursorStore cursors;
  late MemoryTokenStore tokens;
  late MemorySnapshotStore snapshots;
  late SyncEngine engine;
  late int calendarId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
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
}
