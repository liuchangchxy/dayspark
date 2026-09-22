import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/sync/sync_applier.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

void main() {
  late AppDatabase db;
  late SyncApplier applier;
  late int calendarId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    applier = SyncApplier(db);
    // onCreate seeds exactly one Personal calendar.
    calendarId = (await db.select(db.calendars).getSingle()).id;
  });

  tearDown(() async {
    await db.close();
  });

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

    final applied = await applier.apply(SyncRecord(
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
    await applier.apply(SyncRecord(
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
    await applier.apply(SyncRecord(
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

    final applied = await applier.apply(SyncRecord(
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
    final applied = await applier.apply(SyncRecord(
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

    await applier.apply(SyncRecord(
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
    await applier.apply(SyncRecord(
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
    final applied = await applier.apply(SyncRecord(
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
