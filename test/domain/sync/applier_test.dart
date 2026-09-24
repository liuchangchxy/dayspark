import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_bus.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/sync/sync_applier.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import 'sync_test_support.dart';

void main() {
  late AppDatabase db;
  late SyncApplier applier;
  late int calendarId;
  late List<List<RecordChange>> batches;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    applier = SyncApplier(db);
    // onCreate seeds exactly one Personal calendar.
    calendarId = (await db.select(db.calendars).getSingle()).id;
    batches = <List<RecordChange>>[];
    final subscription = RecordBus.of(db).changes.listen(batches.add);
    addTearDown(subscription.cancel);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> applyRecord(SyncRecord record) =>
      RecordScope.run(db, (tx) => applier.apply(record, tx));

  Map<String, Object?> eventPayload({
    String summary = 'Server event',
    int calendarId = 1,
    String? startDt = '2026-09-24T10:00:00.000Z',
    String? endDt = '2026-09-24T11:00:00.000Z',
    String? deletedAt,
  }) =>
      <String, Object?>{
        'calendarId': calendarId,
        'summary': summary,
        'startDt': startDt,
        'endDt': endDt,
        'isAllDay': false,
        'description': null,
        'location': null,
        'rrule': null,
        'deletedAt': deletedAt,
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-22T00:00:00.000Z',
      };

  test('server record overwrites the matching local row (server wins LWW)',
      () async {
    final localId = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Local edit',
            startDt: DateTime(2026, 9, 24, 10),
            endDt: DateTime(2026, 9, 24, 11),
            syncId: const Value('rec-1'),
            serverRev: const Value(2),
          ),
        );

    final applied = await applyRecord(SyncRecord(
      id: 'rec-1',
      type: RecordType.event,
      payload: eventPayload(summary: 'Server wins'),
      rev: 9,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));
    expect(applied, true);

    final row =
        await (db.select(db.events)..where((t) => t.id.equals(localId)))
            .getSingle();
    expect(row.summary, 'Server wins');
    expect(row.serverRev, 9);
    expect(row.syncId, 'rec-1');
    expect(row.startDt.toUtc(), DateTime.utc(2026, 9, 24, 10));
  });

  test('unknown record is inserted with its syncId', () async {
    await applyRecord(SyncRecord(
      id: 'rec-new',
      type: RecordType.event,
      payload: eventPayload(summary: 'From other device'),
      rev: 1,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));

    final row = await (db.select(db.events)).getSingle();
    expect(row.summary, 'From other device');
    expect(row.syncId, 'rec-new');
    expect(row.serverRev, 1);
    expect(row.calendarId, calendarId);
  });

  test('payload calendarId that does not exist locally falls back', () async {
    await applyRecord(SyncRecord(
      id: 'rec-cal',
      type: RecordType.event,
      payload: eventPayload(calendarId: 999),
      rev: 1,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));

    final row = await (db.select(db.events)).getSingle();
    expect(row.calendarId, calendarId);
  });

  test('tombstone soft-deletes the local row instead of dropping it',
      () async {
    final localId = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Trashed remotely',
            startDt: DateTime(2026, 9, 24, 10),
            endDt: DateTime(2026, 9, 24, 11),
            syncId: const Value('rec-del'),
          ),
        );
    final serverTs = DateTime.utc(2026, 9, 23, 9);

    final applied = await applyRecord(SyncRecord(
      id: 'rec-del',
      type: RecordType.event,
      payload: const {},
      rev: 4,
      deleted: true,
      serverTs: serverTs,
    ));
    expect(applied, true);

    final row =
        await (db.select(db.events)..where((t) => t.id.equals(localId)))
            .getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.deletedAt!.toUtc(), serverTs);
    expect(row.serverRev, 4);
  });

  test('tombstone for an unknown record is a no-op', () async {
    final applied = await applyRecord(SyncRecord(
      id: 'rec-ghost',
      type: RecordType.event,
      payload: const {},
      rev: 1,
      deleted: true,
      serverTs: DateTime.utc(2026, 9, 23, 9),
    ));
    expect(applied, false);
    expect(await (db.select(db.events)).get(), isEmpty);
  });

  test('todo parentSyncId resolves to the local parent row', () async {
    final parentId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Parent',
            syncId: const Value('parent-sync'),
          ),
        );

    await applyRecord(SyncRecord(
      id: 'child-sync',
      type: RecordType.todo,
      payload: <String, Object?>{
        'calendarId': calendarId,
        'summary': 'Child',
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
        'updatedAt': '2026-09-22T00:00:00.000Z',
        'sortOrder': 0,
        'parentSyncId': 'parent-sync',
      },
      rev: 2,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));

    final child = await (db.select(db.todos)
          ..where((t) => t.syncId.equals('child-sync')))
        .getSingle();
    expect(child.parentId, parentId);
    expect(child.serverRev, 2);
  });

  test('todo with a parentSyncId unknown locally stays top-level', () async {
    await applyRecord(SyncRecord(
      id: 'child-orphan',
      type: RecordType.todo,
      payload: <String, Object?>{
        'calendarId': calendarId,
        'summary': 'Orphan child',
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
        'updatedAt': '2026-09-22T00:00:00.000Z',
        'sortOrder': 0,
        'parentSyncId': 'missing-parent',
      },
      rev: 1,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));

    final child = await (db.select(db.todos)
          ..where((t) => t.syncId.equals('child-orphan')))
        .getSingle();
    expect(child.parentId, isNull);
  });

  test('malformed payload is skipped, not thrown', () async {
    final applied = await applyRecord(SyncRecord(
      id: 'rec-bad',
      type: RecordType.event,
      payload: const {'summary': 'no dates'},
      rev: 1,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));
    expect(applied, false);
    expect(await (db.select(db.events)).get(), isEmpty);
  });

  test('applier 登记 applied 时携带写前参考时间（重排器的位移基准）', () async {
    final start = DateTime(2026, 6, 10, 9);
    final localId = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: '本机旧值',
            startDt: start,
            endDt: start.add(const Duration(hours: 1)),
            syncId: const Value('rec-ref'),
          ),
        );

    await applyRecord(SyncRecord(
      id: 'rec-ref',
      type: RecordType.event,
      payload: eventPayload(
        summary: '远端改期',
        startDt: DateTime(2026, 6, 10, 11).toUtc().toIso8601String(),
        endDt: DateTime(2026, 6, 10, 12).toUtc().toIso8601String(),
      ),
      rev: 5,
      deleted: false,
      serverTs: DateTime.utc(2026, 9, 23, 8),
    ));

    await waitUntil(() => batches.length == 1, reason: '提交后必须发布一批');
    final applied = batches.single.single as RecordApplied;
    expect(applied.type, RecordType.event);
    expect(applied.localId, localId);
    expect(
      applied.previousReference,
      start,
      reason: '必须是写前那一行的 startDt —— 提交后就再也读不回来了',
    );
  });

  test('applier 落地远端 tombstone：登记 removed + 该记录全部 reminder id', () async {
    final start = DateTime(2026, 6, 10, 9);
    final localId = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: '远端要删',
            startDt: start,
            endDt: start.add(const Duration(hours: 1)),
            syncId: const Value('rec-del'),
          ),
        );
    final first = await db.into(db.reminders).insert(
          RemindersCompanion.insert(
            parentType: 'event',
            parentId: localId,
            triggerTime: DateTime(2026, 6, 10, 8),
          ),
        );
    final second = await db.into(db.reminders).insert(
          RemindersCompanion.insert(
            parentType: 'event',
            parentId: localId,
            triggerTime: DateTime(2026, 6, 10, 7),
          ),
        );

    await applyRecord(SyncRecord(
      id: 'rec-del',
      type: RecordType.event,
      payload: const {},
      rev: 6,
      deleted: true,
      serverTs: DateTime.utc(2026, 9, 23, 9),
    ));

    await waitUntil(() => batches.length == 1, reason: '提交后必须发布一批');
    final removed = batches.single.single as RecordRemoved;
    expect(removed.type, RecordType.event);
    expect(removed.localId, localId);
    expect(removed.reminderIds, [first, second]);
    expect(
      await (db.select(db.reminders)).get(),
      hasLength(2),
      reason: '远端删除不销毁本机数据：行留作惰性，OS 通知靠 removed 携带的 id 撤',
    );
    final row =
        await (db.select(db.events)..where((t) => t.id.equals(localId)))
            .getSingle();
    expect(row.deletedAt, isNotNull);
  });

  test('enqueue assigns syncId so later applies can find the row', () async {
    final localId = await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Enqueue me',
            startDt: DateTime(2026, 9, 24, 10),
            endDt: DateTime(2026, 9, 24, 11),
          ),
        );
    await SyncOutbox.enqueueUpsert(db, RecordType.event, localId);
    final row =
        await (db.select(db.events)..where((t) => t.id.equals(localId)))
            .getSingle();
    expect(row.syncId, isNotNull);
    final op = await (db.select(db.syncOutbox)).getSingle();
    expect(op.recordId, row.syncId);
    expect(op.baseRev, 0);
  });
}
