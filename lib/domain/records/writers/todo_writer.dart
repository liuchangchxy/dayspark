import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final class TodoWriter {
  const TodoWriter._();

  static Future<void> updateTodo(
    AppDatabase db,
    RecordScope tx,
    int id,
    TodosCompanion data, {
    RecurrenceSpec? recurrenceSpec,
    bool replaceRecurrence = false,
  }) async {
    final existing = await _row(db, id);
    if (existing == null) throw StateError('Todo $id does not exist.');
    final recurrence = TodoRecurrence.fromTodo(existing);
    final touchesChangedProjection =
        (data.rrule.present && data.rrule.value != existing.rrule) ||
        (data.startDate.present &&
            data.startDate.value != existing.startDate) ||
        (data.dueDate.present && data.dueDate.value != existing.dueDate);
    if (recurrenceSpec != null && !replaceRecurrence) {
      throw ArgumentError('recurrenceSpec requires replaceRecurrence=true.');
    }
    if (!replaceRecurrence &&
        touchesChangedProjection &&
        recurrence.spec != null) {
      throw StateError(
        'Recurring Todo fields must be updated as one RecurrenceSpec.',
      );
    }
    if (!replaceRecurrence &&
        touchesChangedProjection &&
        recurrence.isUnknownLegacy) {
      throw StateError(
        'Unknown legacy recurrence must be confirmed before editing recurrence fields.',
      );
    }
    if (!replaceRecurrence &&
        data.rrule.present &&
        data.rrule.value != existing.rrule) {
      throw StateError('RRULE changes require a complete RecurrenceSpec.');
    }
    final unchanged =
        recurrence.spec == null &&
        recurrenceSpec == null &&
        recurrence.legacyState == null;
    final sameSpec =
        recurrence.spec != null &&
        recurrenceSpec != null &&
        _sameSpec(recurrence.spec!, recurrenceSpec);
    final nextRevision = (unchanged || sameSpec)
        ? recurrence.revision
        : recurrence.revision + 1;
    final effective = replaceRecurrence
        ? _withRecurrence(data, recurrenceSpec, revision: nextRevision)
        : data;
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(effective);
    await _invalidateAllocationsAfterCompletion(db, tx, id);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id, previousReference: existing.dueDate);
  }

  static Future<int> create(
    AppDatabase db,
    RecordScope tx,
    TodosCompanion data, {
    RecurrenceSpec? recurrenceSpec,
  }) async {
    if (data.rrule.present &&
        data.rrule.value != null &&
        recurrenceSpec == null) {
      throw StateError(
        'Recurring Todo creation requires a complete RecurrenceSpec.',
      );
    }
    final id = await db
        .into(db.todos)
        .insert(
          recurrenceSpec == null
              ? data
              : _withRecurrence(data, recurrenceSpec, revision: 1),
        );
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id);
    return id;
  }

  static Future<void> confirmLegacyRecurrence(
    AppDatabase db,
    RecordScope tx, {
    required int todoId,
    required String chosenTimeZone,
    required RecurrenceAnchor interpretation,
    required String validatedRRule,
  }) async {
    final todo = await _row(db, todoId);
    if (todo == null ||
        todo.rrule == null ||
        TodoRecurrence.fromTodo(todo).legacyState !=
            TodoRecurrenceLegacyState.unknownLegacy) {
      throw StateError('Todo is not an unknownLegacy recurring Todo.');
    }
    final spec = RecurrenceSpec.parse(
      anchor: interpretation,
      timeZone: chosenTimeZone,
      rrule: validatedRRule,
    );
    final canonicalSpec = RecurrenceSpec.parse(
      anchor: interpretation,
      timeZone: chosenTimeZone,
      rrule: todo.rrule!,
    );
    if (canonicalSpec.rule.canonical != spec.rule.canonical) {
      throw StateError('Confirmed RRULE must match the legacy Todo RRULE.');
    }
    final recurrence = TodoRecurrence.known(
      spec,
      revision: todo.recurrenceRevision + 1,
    );
    await (db.update(
      db.todos,
    )..where((row) => row.id.equals(todoId))).write(recurrence.toCompanion());
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, todoId);
    tx.applied(RecordType.todo, todoId, previousReference: todo.dueDate);
  }

  static TodosCompanion _withRecurrence(
    TodosCompanion data,
    RecurrenceSpec? spec, {
    required int revision,
  }) {
    final recurrence = spec == null
        ? TodoRecurrence.none(revision: revision)
        : TodoRecurrence.known(spec, revision: revision);
    final fields = recurrence.toCompanion();
    return data.copyWith(
      rrule: fields.rrule,
      recurrenceAnchorSource: fields.recurrenceAnchorSource,
      recurrenceValueType: fields.recurrenceValueType,
      recurrenceAnchorValue: fields.recurrenceAnchorValue,
      recurrenceTimeZone: fields.recurrenceTimeZone,
      recurrenceRule: fields.recurrenceRule,
      recurrenceLegacyState: fields.recurrenceLegacyState,
      recurrenceRevision: fields.recurrenceRevision,
    );
  }

  static bool _sameSpec(RecurrenceSpec left, RecurrenceSpec right) =>
      left.anchor.source == right.anchor.source &&
      left.anchor.valueType == right.anchor.valueType &&
      left.anchor.value.canonical == right.anchor.value.canonical &&
      left.timeZone == right.timeZone &&
      left.rule.canonical == right.rule.canonical;

  // ICS 导入用：仍是裸 insert（outbox 与 syncId 回填属 P2.5#2，不在本次）。
  static Future<int> importRow(
    AppDatabase db,
    RecordScope tx,
    TodosCompanion data, {
    RecurrenceSpec? recurrenceSpec,
    LegacyRecurrenceEvidence? recurrenceEvidence,
  }) async {
    final legacyRecurring = data.rrule.present && data.rrule.value != null;
    final TodosCompanion importData;
    if (recurrenceSpec != null) {
      importData = _withRecurrence(data, recurrenceSpec, revision: 1);
    } else if (legacyRecurring) {
      importData = data.copyWith(
        recurrenceLegacyState: const Value('unknownLegacy'),
        recurrenceRevision: const Value(0),
        recurrenceEvidence: Value(recurrenceEvidence?.encode()),
      );
    } else {
      importData = data;
    }
    final id = await db.into(db.todos).insert(importData);
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
    await _invalidateAllocationsAfterCompletion(db, tx, id);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    tx.applied(RecordType.todo, id, previousReference: existing?.dueDate);
  }

  static Future<void> softDelete(AppDatabase db, RecordScope tx, int id) async {
    final children = await (db.select(
      db.todos,
    )..where((t) => t.parentId.equals(id) & t.deletedAt.isNull())).get();
    final ids = <int>[id, ...children.map((c) => c.id)];
    final previous = await _dueDates(db, ids);
    final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
    final now = DateTime.now();
    // Soft delete parent and direct children with the same timestamp so no
    // orphan rows keep showing up in lists or as ghost reminders.
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (db.update(db.todos)
          ..where((t) => t.parentId.equals(id) & t.deletedAt.isNull()))
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
    await (db.update(
      db.todos,
    )..where((t) => t.parentId.equals(id) & t.deletedAt.isNotNull())).write(
      TodosCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
    );
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
    final todos = await (db.select(
      db.todos,
    )..where((t) => t.id.isIn(ids))).get();
    final todoSyncIds = todos
        .map((todo) => todo.syncId)
        .whereType<String>()
        .toList();
    final reminderIds = await ReminderWriter.idsByParent(db, 'todo', ids);
    final allocations = await _allocationsForTodos(db, ids, todoSyncIds);
    final allocationTargets = await SyncOutbox.captureDeletes(
      db,
      RecordType.taskAllocation,
      allocations.map((row) => row.id).toList(),
    );
    final targets = await SyncOutbox.captureDeletes(
      db,
      RecordType.todo,
      ids,
      hardDelete: true,
    );
    await SyncOutbox.enqueueDeletes(db, allocationTargets);
    await SyncOutbox.enqueueDeletes(db, targets);
    // FK-safe delete order (mirrors emptyTrash): child-rows first, todo rows
    // last, all in one transaction.
    for (final tid in ids) {
      await (db.delete(db.todoTags)..where((t) => t.todoId.equals(tid))).go();
    }
    await (db.delete(
      db.attachments,
    )..where((t) => t.parentType.equals('todo') & t.parentId.isIn(ids))).go();
    await (db.delete(
      db.reminders,
    )..where((t) => t.parentType.equals('todo') & t.parentId.isIn(ids))).go();
    await _deleteTaskAllocations(db, tx, ids, todoSyncIds);
    await (db.delete(db.todos)..where((t) => t.id.isIn(ids))).go();
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
    final todoSyncIds = deleted
        .map((todo) => todo.syncId)
        .whereType<String>()
        .toList();
    final reminderIds = await ReminderWriter.idsByParent(db, 'todo', ids);
    final allocations = await _allocationsForTodos(db, ids, todoSyncIds);
    final allocationTargets = await SyncOutbox.captureDeletes(
      db,
      RecordType.taskAllocation,
      allocations.map((row) => row.id).toList(),
    );
    final targets = await SyncOutbox.captureDeletes(
      db,
      RecordType.todo,
      ids,
      hardDelete: true,
    );
    await SyncOutbox.enqueueDeletes(db, allocationTargets);
    await SyncOutbox.enqueueDeletes(db, targets);
    await _deleteTaskAllocations(db, tx, ids, todoSyncIds);
    await db.todosDao.emptyTrash();
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
    await db
        .update(db.todos)
        .write(
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
    required TodoRecurrence recurrence,
    required DateTime? previousReference,
  }) async {
    final recurrenceData = recurrence.recurrenceColumns();
    final legacyEvidence =
        recurrence.isUnknownLegacy && !data.recurrenceEvidence.present
        ? Value(
            const LegacyRecurrenceEvidence(
              source: 'sync',
              timeSemantic: 'unknown',
            ).encode(),
          )
        : data.recurrenceEvidence;
    final effective = data.copyWith(
      recurrenceAnchorSource: recurrenceData.recurrenceAnchorSource,
      recurrenceValueType: recurrenceData.recurrenceValueType,
      recurrenceAnchorValue: recurrenceData.recurrenceAnchorValue,
      recurrenceTimeZone: recurrenceData.recurrenceTimeZone,
      recurrenceRule: recurrenceData.recurrenceRule,
      recurrenceLegacyState: recurrenceData.recurrenceLegacyState,
      recurrenceRevision: recurrenceData.recurrenceRevision,
      recurrenceEvidence: legacyEvidence,
    );
    if (existingId == null) {
      final id = await db.into(db.todos).insert(effective);
      await _resolveTaskAllocations(db, tx, id);
      tx.applied(RecordType.todo, id);
      return;
    }
    await (db.update(
      db.todos,
    )..where((t) => t.id.equals(existingId))).write(effective);
    await _invalidateAllocationsAfterCompletion(
      db,
      tx,
      existingId,
      queueSync: false,
    );
    await _resolveTaskAllocations(db, tx, existingId);
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

  static Future<bool> applyRemoteHardDelete(
    AppDatabase db,
    RecordScope tx, {
    required String syncId,
    required int? localId,
  }) async {
    final allocations =
        await (db.select(db.taskAllocations)..where(
              (row) =>
                  row.todoSyncId.equals(syncId) |
                  (localId == null
                      ? const Constant(false)
                      : row.todoId.equals(localId)),
            ))
            .get();
    if (allocations.isNotEmpty) {
      final ids = allocations.map((row) => row.id).toList();
      await (db.delete(
        db.taskAllocations,
      )..where((row) => row.id.isIn(ids))).go();
      for (final allocation in allocations) {
        tx.taskAllocationChanged(allocation.id);
      }
    }
    if (localId == null) return allocations.isNotEmpty;
    final reminderIds = await ReminderWriter.idsOfParent(db, 'todo', localId);
    await (db.delete(
      db.todoTags,
    )..where((row) => row.todoId.equals(localId))).go();
    await (db.delete(db.attachments)..where(
          (row) => row.parentType.equals('todo') & row.parentId.equals(localId),
        ))
        .go();
    await (db.delete(db.reminders)..where(
          (row) => row.parentType.equals('todo') & row.parentId.equals(localId),
        ))
        .go();
    await (db.delete(db.todos)..where((row) => row.id.equals(localId))).go();
    tx.removed(RecordType.todo, localId, reminderIds: reminderIds);
    return true;
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
    return (db.select(
      db.todos,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
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

  static Future<void> _deleteTaskAllocations(
    AppDatabase db,
    RecordScope tx,
    List<int> todoIds,
    List<String> todoSyncIds,
  ) async {
    final allocations = await _allocationsForTodos(db, todoIds, todoSyncIds);
    if (allocations.isEmpty) return;
    final allocationIds = allocations.map((row) => row.id).toList();
    await (db.delete(
      db.taskAllocations,
    )..where((row) => row.id.isIn(allocationIds))).go();
    for (final allocation in allocations) {
      tx.taskAllocationChanged(allocation.id);
    }
  }

  static Future<List<TaskAllocation>> _allocationsForTodos(
    AppDatabase db,
    List<int> todoIds,
    List<String> todoSyncIds,
  ) {
    if (todoIds.isEmpty && todoSyncIds.isEmpty) {
      return Future.value(const <TaskAllocation>[]);
    }
    return (db.select(db.taskAllocations)..where(
          (row) =>
              (todoIds.isEmpty
                  ? const Constant(false)
                  : row.todoId.isIn(todoIds)) |
              (todoSyncIds.isEmpty
                  ? const Constant(false)
                  : row.todoSyncId.isIn(todoSyncIds)),
        ))
        .get();
  }

  static Future<void> _resolveTaskAllocations(
    AppDatabase db,
    RecordScope tx,
    int todoId,
  ) async {
    final todo = await _row(db, todoId);
    final syncId = todo?.syncId;
    if (todo == null || syncId == null) return;
    final allocations =
        await (db.select(db.taskAllocations)..where(
              (row) => row.todoSyncId.equals(syncId) & row.todoId.isNull(),
            ))
            .get();
    for (final allocation in allocations) {
      final invalidated =
          todo.status == 'COMPLETED' &&
          todo.completedAt != null &&
          allocation.state == 'active' &&
          allocation.startAt.toUtc().millisecondsSinceEpoch >=
              todo.completedAt!.toUtc().millisecondsSinceEpoch;
      await (db.update(
        db.taskAllocations,
      )..where((row) => row.id.equals(allocation.id))).write(
        TaskAllocationsCompanion(
          todoId: Value(todoId),
          state: invalidated
              ? const Value('invalidatedByCompletion')
              : const Value.absent(),
        ),
      );
      tx.taskAllocationChanged(allocation.id);
    }
  }

  static Future<void> _invalidateAllocationsAfterCompletion(
    AppDatabase db,
    RecordScope tx,
    int todoId, {
    bool queueSync = true,
  }) async {
    final todo = await _row(db, todoId);
    final completedAt = todo?.completedAt;
    if (todo == null || todo.status != 'COMPLETED' || completedAt == null) {
      return;
    }
    final completionMs = completedAt.toUtc().millisecondsSinceEpoch;
    final allocations = await (db.select(
      db.taskAllocations,
    )..where((a) => a.todoId.equals(todoId) & a.state.equals('active'))).get();
    final now = DateTime.now();
    for (final allocation in allocations) {
      if (allocation.startAt.toUtc().millisecondsSinceEpoch < completionMs) {
        continue;
      }
      await (db.update(
        db.taskAllocations,
      )..where((a) => a.id.equals(allocation.id))).write(
        TaskAllocationsCompanion(
          state: const Value('invalidatedByCompletion'),
          updatedAt: Value(now),
        ),
      );
      if (queueSync) {
        await SyncOutbox.enqueueUpsert(
          db,
          RecordType.taskAllocation,
          allocation.id,
        );
      }
      tx.taskAllocationChanged(allocation.id);
    }
  }
}
