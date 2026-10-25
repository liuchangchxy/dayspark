import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
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

  // 事件软删与待办侧对称：父行只置 deletedAt，reminder 行**保留**为惰性——进
  // 回收站不是"记录已不存在"（行还在，恢复时同一批 id 要被重新调度）；若连带
  // 删行，恢复后就没有任何行可重挂、也没有任何重读路径能让消费端撤掉已交给 OS
  // 的通知。通知改由重排器按父行 inactive 档撤销（`_readParent` 的
  // `deletedAt != null`），登记 applied 而非 removed——removed 的语义是"记录已
  // 不存在"，与"行仍在回收站里"相左。硬删路径（hardDeleteWithChildren /
  // emptyTrash）仍必须硬删行：永久删除后留下的惰性行就是垃圾。
  static Future<void> softDelete(AppDatabase db, RecordScope tx, int id) async {
    final existing = await _row(db, id);
    final now = DateTime.now();
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await SyncOutbox.enqueueDelete(db, RecordType.event, id);
    tx.applied(RecordType.event, id, previousReference: existing?.startDt);
  }

  static Future<void> restore(AppDatabase db, RecordScope tx, int id) async {
    final existing = await _row(db, id);
    await db.eventsDao.restoreEvent(id);
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    tx.applied(RecordType.event, id, previousReference: existing?.startDt);
  }

  /// Excludes one occurrence of a recurring event, leaving the series alone.
  ///
  /// This is the RFC 5545 answer to "delete just this one": the row keeps its
  /// RRULE and gains an EXDATE. The whole-series delete stays [softDelete].
  static Future<void> excludeOccurrence(
    AppDatabase db,
    RecordScope tx,
    int id,
    DateTime occurrenceStart,
  ) async {
    final existing = await _row(db, id);
    if (existing == null) throw StateError('Event $id does not exist.');
    if (existing.rrule == null || existing.rrule!.isEmpty) {
      throw StateError('Only recurring events have occurrences to exclude.');
    }
    final exdates = parseExdates(existing.exdates)..add(occurrenceStart);
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        exdates: Value(encodeExdates(exdates)),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    tx.applied(RecordType.event, id, previousReference: existing.startDt);
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

  // ICS 导入用：upsert by icsUid if present, insert otherwise; enqueue outbox (DS-005, DS-007).
  static Future<int> importRow(
    AppDatabase db,
    RecordScope tx,
    EventsCompanion data,
  ) async {
    final uid = data.icsUid.present ? data.icsUid.value : null;
    if (uid != null && uid.isNotEmpty) {
      final existing = await (db.select(
        db.events,
      )..where((e) => e.icsUid.equals(uid))).getSingleOrNull();
      if (existing != null) {
        await (db.update(
          db.events,
        )..where((e) => e.id.equals(existing.id))).write(
          data.copyWith(
            id: Value(existing.id),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await SyncOutbox.enqueueUpsert(db, RecordType.event, existing.id);
        tx.applied(RecordType.event, existing.id);
        return existing.id;
      }
    }
    final id = await db.into(db.events).insert(data);
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
    tx.applied(RecordType.event, id);
    return id;
  }

  // 身份切换的全表元数据重写：只清同步标识，参考时间与父状态都没变，所以
  // 不逐 id 登记——一条粗粒度 bulkChanged 让消费端自行决定要不要重读。
  static Future<void> clearSyncState(AppDatabase db, RecordScope tx) async {
    await db
        .update(db.events)
        .write(
          EventsCompanion(serverRev: const Value(0), syncId: const Value(null)),
        );
    tx.bulkChanged(RecordType.event, reason: 'identity-reset');
  }

  // 远端真值落地（同步 applier）：只写行 + 登记，不回灌 outbox——回灌会让
  // 服务端权威值回声成一次本地推送（改期回声、tombstone 回声删除）。
  // previousReference 取写前旧值（applier 在写之前读到的那一行）。
  static Future<void> applyRemote(
    AppDatabase db,
    RecordScope tx, {
    required int? existingId,
    required EventsCompanion data,
    required DateTime? previousReference,
  }) async {
    if (existingId == null) {
      final id = await db.into(db.events).insert(data);
      tx.applied(RecordType.event, id);
      return;
    }
    await (db.update(
      db.events,
    )..where((t) => t.id.equals(existingId))).write(data);
    tx.applied(
      RecordType.event,
      existingId,
      previousReference: previousReference,
    );
  }

  // 远端 tombstone：父行进回收站、reminder 行**保留**为惰性（与本地软删的
  // "保留行"一致；两侧差别只在登记格：远端删除不是用户在本机做过的动作，也不
  // 知道本机有哪些行，故按父级整体携带删前的 id 走 removed 撤销通知，而本地
  // 软删按父行 inactive 档判定）。恢复事件时同一批 id 可被重新调度。
  static Future<void> applyRemoteTombstone(
    AppDatabase db,
    RecordScope tx,
    int id, {
    required DateTime serverTs,
    required int rev,
  }) async {
    final reminderIds = await ReminderWriter.idsOfParent(db, 'event', id);
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        deletedAt: Value(serverTs),
        updatedAt: Value(serverTs),
        serverRev: Value(rev),
      ),
    );
    tx.removed(RecordType.event, id, reminderIds: reminderIds);
  }

  // 只推进 rev：参考时间与父状态都没变，登记反而会在冷启动账本上触发一次
  // 多余的 schedule（Δ=0），所以有意空登记。
  static Future<void> applyRemoteRev(
    AppDatabase db,
    RecordScope tx,
    int id,
    int rev,
  ) async {
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(serverRev: Value(rev)),
    );
  }

  static Future<Event?> _row(AppDatabase db, int id) {
    return (db.select(
      db.events,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
