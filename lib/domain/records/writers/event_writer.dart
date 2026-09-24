import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final class EventWriter {
  const EventWriter._();

  static Future<int> create(
    AppDatabase db,
    RecordScope tx,
    EventsCompanion data,
  ) async {
    final id = await db.into(db.events).insert(data);
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    tx.applied(RecordType.event, id);
    return id;
  }

  static Future<void> update(
    AppDatabase db,
    RecordScope tx,
    int id,
    EventsCompanion data,
  ) async {
    final existing = await _row(db, id);
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(data);
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    tx.applied(RecordType.event, id, previousReference: existing?.startDt);
  }

  // 事件软删连带硬删 reminder 行（既有产品语义，本次不改）：行没了就没有任何
  // 重读路径能让消费端撤销已交给 OS 的通知，因此必须随事件携带删前的 id
  // （CONSTRAINTS 清单第 6 条"进回收站 → 提醒不响"）。
  static Future<void> softDelete(AppDatabase db, RecordScope tx, int id) async {
    final reminderIds = await ReminderWriter.idsOfParent(db, 'event', id);
    await (db.delete(db.reminders)..where(
          (t) => t.parentType.equals('event') & t.parentId.equals(id),
        ))
        .go();
    final now = DateTime.now();
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await SyncOutbox.enqueueDelete(db, RecordType.event, id);
    tx.removed(RecordType.event, id, reminderIds: reminderIds);
  }

  static Future<void> restore(AppDatabase db, RecordScope tx, int id) async {
    final existing = await _row(db, id);
    await db.eventsDao.restoreEvent(id);
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    tx.applied(RecordType.event, id, previousReference: existing?.startDt);
  }

  static Future<void> hardDeleteWithChildren(
    AppDatabase db,
    RecordScope tx,
    int id,
  ) async {
    final reminderIds = await ReminderWriter.idsOfParent(db, 'event', id);
    final targets = await SyncOutbox.captureDeletes(db, RecordType.event, [id]);
    await db.eventsDao.hardDeleteEventWithChildren(id);
    await SyncOutbox.enqueueDeletes(db, targets);
    tx.removed(RecordType.event, id, reminderIds: reminderIds);
  }

  static Future<void> emptyTrash(AppDatabase db, RecordScope tx) async {
    final deleted = await (db.select(
      db.events,
    )..where((t) => t.deletedAt.isNotNull())).get();
    final ids = deleted.map((e) => e.id).toList();
    final reminderIds = await ReminderWriter.idsByParent(db, 'event', ids);
    final targets = await SyncOutbox.captureDeletes(db, RecordType.event, ids);
    await db.eventsDao.emptyEventTrash();
    await SyncOutbox.enqueueDeletes(db, targets);
    for (final id in ids) {
      tx.removed(
        RecordType.event,
        id,
        reminderIds: reminderIds[id] ?? const <int>[],
      );
    }
  }

  // ICS 导入用：仍是裸 insert（outbox 与 syncId 回填属 P2.5#2，不在本次），
  // 只补一条 applied——导入行不回看旧值。
  static Future<int> importRow(
    AppDatabase db,
    RecordScope tx,
    EventsCompanion data,
  ) async {
    final id = await db.into(db.events).insert(data);
    tx.applied(RecordType.event, id);
    return id;
  }

  // 身份切换的全表元数据重写：只清同步标识，参考时间与父状态都没变，所以
  // 不逐 id 登记——一条粗粒度 bulkChanged 让消费端自行决定要不要重读。
  static Future<void> clearSyncState(AppDatabase db, RecordScope tx) async {
    await db.update(db.events).write(
      EventsCompanion(serverRev: const Value(0), syncId: const Value(null)),
    );
    tx.bulkChanged(RecordType.event, reason: 'identity-reset');
  }

  static Future<Event?> _row(AppDatabase db, int id) {
    return (db.select(db.events)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}
