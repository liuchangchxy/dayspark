import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

void main() {
  late AppDatabase db;
  late int calendarId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEvent(String summary) => db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calendarId,
          summary: summary,
          startDt: DateTime(2026, 9, 23, 10),
          endDt: DateTime(2026, 9, 23, 11),
        ),
      );

  Future<List<SyncOutboxEntry>> allOps() =>
      (db.select(db.syncOutbox)).get();

  /// Pins the pending op's createdAt so the keep-oldest rule is observable.
  Future<void> pinCreatedAt(String recordId, DateTime when) async {
    await (db.update(db.syncOutbox)..where((t) => t.recordId.equals(recordId)))
        .write(SyncOutboxCompanion(createdAt: Value(when)));
  }

  test('successive upserts collapse to newest payload, keep oldest createdAt',
      () async {
    final id = await insertEvent('first');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    final first = (await allOps()).single;
    final pinned = DateTime(2020, 1, 1);
    await pinCreatedAt(first.recordId, pinned);

    await (db.update(db.events)..where((t) => t.id.equals(id)))
        .write(const EventsCompanion(summary: Value('second')));
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);

    final ops = await allOps();
    expect(ops, hasLength(1));
    expect(ops.single.recordId, first.recordId);
    expect(ops.single.op, OpType.upsert.name);
    expect(ops.single.payloadJson, contains('second'));
    expect(ops.single.createdAt, pinned);
    // Fresh opId per enqueue: the replaced op may already be in flight.
    expect(ops.single.opId, isNot(first.opId));
  });

  test('delete clears the record\'s pending upserts', () async {
    final id = await insertEvent('doomed');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    final upsert = (await allOps()).single;
    final pinned = DateTime(2020, 1, 1);
    await pinCreatedAt(upsert.recordId, pinned);

    await SyncOutbox.enqueueDelete(db, RecordType.event, id);

    final ops = await allOps();
    expect(ops, hasLength(1));
    expect(ops.single.op, OpType.delete.name);
    expect(ops.single.recordId, upsert.recordId);
    expect(ops.single.payloadJson, isNull);
    expect(ops.single.createdAt, pinned);
  });

  test('upsert after pending delete replaces the delete (resurrect)', () async {
    final id = await insertEvent('phoenix');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    final upsert = (await allOps()).single;
    final pinned = DateTime(2020, 1, 1);
    await pinCreatedAt(upsert.recordId, pinned);

    await SyncOutbox.enqueueDelete(db, RecordType.event, id);
    expect((await allOps()).single.op, OpType.delete.name);

    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);

    final ops = await allOps();
    expect(ops, hasLength(1));
    expect(ops.single.op, OpType.upsert.name);
    expect(ops.single.payloadJson, contains('phoenix'));
    expect(ops.single.createdAt, pinned);
  });

  test('ops for different records stay independent', () async {
    final a = await insertEvent('event-a');
    final b = await insertEvent('event-b');
    await SyncOutbox.enqueueUpsert(db, RecordType.event, a);
    await SyncOutbox.enqueueUpsert(db, RecordType.event, b);
    await SyncOutbox.enqueueDelete(db, RecordType.event, a);

    final ops = await allOps();
    expect(ops, hasLength(2));
    final byRecord = {for (final op in ops) op.recordId: op};
    expect(byRecord, hasLength(2));
    final deleted = ops.singleWhere((op) => op.op == OpType.delete.name);
    final upsert = ops.singleWhere((op) => op.op == OpType.upsert.name);
    expect(deleted.recordId, isNot(upsert.recordId));
    expect(upsert.payloadJson, contains('event-b'));
  });
}
