import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final class TodoWriter {
  const TodoWriter._();

  static Future<void> updateTodo(
    AppDatabase db,
    RecordScope tx,
    int id,
    TodosCompanion data,
  ) async {
    final existing = await _row(db, id);
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(data);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id, previousReference: existing?.dueDate);
  }

  static Future<int> create(
    AppDatabase db,
    RecordScope tx,
    TodosCompanion data,
  ) async {
    final id = await db.into(db.todos).insert(data);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id);
    return id;
  }

  // ICS 导入用：仍是裸 insert（outbox 与 syncId 回填属 P2.5#2，不在本次）。
  static Future<int> importRow(
    AppDatabase db,
    RecordScope tx,
    TodosCompanion data,
  ) async {
    final id = await db.into(db.todos).insert(data);
    tx.applied(RecordType.todo, id);
    return id;
  }

  static Future<void> setCompletion(
    AppDatabase db,
    RecordScope tx,
    int id, {
    required bool isCompleted,
  }) async {
    final existing = await _row(db, id);
    if (isCompleted) {
      await db.todosDao.markComplete(id);
    } else {
      await db.todosDao.markIncomplete(id);
    }
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id, previousReference: existing?.dueDate);
  }

  static Future<void> softDelete(AppDatabase db, RecordScope tx, int id) async {
    final children = await (db.select(db.todos)..where(
          (t) => t.parentId.equals(id) & t.deletedAt.isNull(),
        ))
        .get();
    final ids = <int>[id, ...children.map((c) => c.id)];
    final previous = await _dueDates(db, ids);
    final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
    final now = DateTime.now();
    // Soft delete parent and direct children with the same timestamp so no
    // orphan rows keep showing up in lists or as ghost reminders.
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (db.update(db.todos)..where(
          (t) => t.parentId.equals(id) & t.deletedAt.isNull(),
        ))
        .write(TodosCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await SyncOutbox.enqueueDeletes(db, targets);
    for (final tid in ids) {
      tx.applied(RecordType.todo, tid, previousReference: previous[tid]);
    }
  }

  static Future<List<int>> restore(
    AppDatabase db,
    RecordScope tx,
    int id,
  ) async {
    final row = await _row(db, id);
    // Restoring a child under a still-trashed parent would hide it in the
    // active lists — untrash the parent too. Single level: no recursion up.
    final parentRefId = row?.parentId;
    int? trashedParentId;
    if (parentRefId != null) {
      final parent = await _row(db, parentRefId);
      if (parent != null && parent.deletedAt != null) {
        trashedParentId = parent.id;
      }
    }
    final children = await (db.select(
      db.todos,
    )..where((t) => t.parentId.equals(id))).get();
    final restored = <int>[
      id,
      if (trashedParentId != null) trashedParentId,
      ...children.map((t) => t.id),
    ];
    final previous = await _dueDates(db, restored);
    final now = DateTime.now();
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
    );
    if (trashedParentId != null) {
      final untrashParentId = trashedParentId;
      await (db.update(
        db.todos,
      )..where((t) => t.id.equals(untrashParentId))).write(
        TodosCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
      );
    }
    // Mirror cascade-delete: restoring a parent must also pull its direct
    // children out of the trash, or they stay orphaned there.
    await (db.update(db.todos)..where(
          (t) => t.parentId.equals(id) & t.deletedAt.isNotNull(),
        ))
        .write(TodosCompanion(deletedAt: const Value(null), updatedAt: Value(now)));
    for (final tid in restored) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, tid);
    }
    for (final tid in restored) {
      tx.applied(RecordType.todo, tid, previousReference: previous[tid]);
    }
    return restored;
  }

  static Future<void> moveOverdueToToday(
    AppDatabase db,
    RecordScope tx,
    List<int> ids,
  ) async {
    final previous = await _dueDates(db, ids);
    await db.todosDao.moveOverdueToToday(ids);
    for (final id in ids) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
      tx.applied(RecordType.todo, id, previousReference: previous[id]);
    }
  }

  static Future<void> permanentDelete(
    AppDatabase db,
    RecordScope tx,
    int id,
  ) async {
    final children = await (db.select(
      db.todos,
    )..where((t) => t.parentId.equals(id))).get();
    final ids = <int>[id, ...children.map((c) => c.id)];
    final reminderIds = await ReminderWriter.idsByParent(db, 'todo', ids);
    final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
    // FK-safe delete order (mirrors emptyTrash): child-rows first, todo rows
    // last, all in one transaction.
    for (final tid in ids) {
      await (db.delete(db.todoTags)..where((t) => t.todoId.equals(tid))).go();
    }
    await (db.delete(db.attachments)..where(
          (t) => t.parentType.equals('todo') & t.parentId.isIn(ids),
        ))
        .go();
    await (db.delete(db.reminders)..where(
          (t) => t.parentType.equals('todo') & t.parentId.isIn(ids),
        ))
        .go();
    await (db.delete(db.todos)..where((t) => t.id.isIn(ids))).go();
    await SyncOutbox.enqueueDeletes(db, targets);
    for (final tid in ids) {
      tx.removed(
        RecordType.todo,
        tid,
        reminderIds: reminderIds[tid] ?? const <int>[],
      );
    }
  }

  static Future<void> emptyTrash(AppDatabase db, RecordScope tx) async {
    final deleted = await (db.select(
      db.todos,
    )..where((t) => t.deletedAt.isNotNull())).get();
    final ids = deleted.map((t) => t.id).toList();
    final reminderIds = await ReminderWriter.idsByParent(db, 'todo', ids);
    final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
    await db.todosDao.emptyTrash();
    await SyncOutbox.enqueueDeletes(db, targets);
    for (final id in ids) {
      tx.removed(
        RecordType.todo,
        id,
        reminderIds: reminderIds[id] ?? const <int>[],
      );
    }
  }

  // reorder / setParent 只改 sortOrder / parentId，不动任何派生态：
  // 事务仍走 RecordScope，但登记为空（空批被 publish 丢弃）。
  static Future<void> reorder(
    AppDatabase db,
    RecordScope tx,
    List<int> ids,
  ) async {
    await db.todosDao.updateSortOrders(ids);
    for (final id in ids) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    }
  }

  static Future<void> setParent(
    AppDatabase db,
    RecordScope tx,
    int todoId,
    int? parentId,
  ) async {
    await db.todosDao.setParent(todoId, parentId);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, todoId);
  }

  static Future<void> clearSyncState(AppDatabase db, RecordScope tx) async {
    await db.update(db.todos).write(
      TodosCompanion(serverRev: const Value(0), syncId: const Value(null)),
    );
    tx.bulkChanged(RecordType.todo, reason: 'identity-reset');
  }

  // 远端真值落地（同步 applier）：只写行 + 登记，不回灌 outbox（见 event_writer
  // 同名声明的 WHY）。
  static Future<void> applyRemote(
    AppDatabase db,
    RecordScope tx, {
    required int? existingId,
    required TodosCompanion data,
    required DateTime? previousReference,
  }) async {
    if (existingId == null) {
      final id = await db.into(db.todos).insert(data);
      tx.applied(RecordType.todo, id);
      return;
    }
    await (db.update(
      db.todos,
    )..where((t) => t.id.equals(existingId))).write(data);
    tx.applied(
      RecordType.todo,
      existingId,
      previousReference: previousReference,
    );
  }

  // 远端 tombstone：父行进回收站、reminder 行保留为惰性（同 event_writer 的
  // applyRemoteTombstone）。
  static Future<void> applyRemoteTombstone(
    AppDatabase db,
    RecordScope tx,
    int id, {
    required DateTime serverTs,
    required int rev,
  }) async {
    final reminderIds = await ReminderWriter.idsOfParent(db, 'todo', id);
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(
        deletedAt: Value(serverTs),
        updatedAt: Value(serverTs),
        serverRev: Value(rev),
      ),
    );
    tx.removed(RecordType.todo, id, reminderIds: reminderIds);
  }

  // 只推进 rev，有意空登记（同 event_writer 的 applyRemoteRev）。
  static Future<void> applyRemoteRev(
    AppDatabase db,
    RecordScope tx,
    int id,
    int rev,
  ) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(serverRev: Value(rev)),
    );
  }

  static Future<Todo?> _row(AppDatabase db, int id) {
    return (db.select(db.todos)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  static Future<Map<int, DateTime?>> _dueDates(
    AppDatabase db,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return <int, DateTime?>{};
    final rows = await (db.select(
      db.todos,
    )..where((t) => t.id.isIn(ids))).get();
    return <int, DateTime?>{for (final row in rows) row.id: row.dueDate};
  }
}
