import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final completedTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchCompleted();
});

final pendingTodosByTagsProvider =
    StreamProvider.autoDispose.family<List<Todo>, String>((ref, tagIdsKey) {
      final db = ref.watch(databaseProvider);
      if (tagIdsKey.isEmpty) {
        return db.todosDao.watchPending();
      }
      final tagIds = tagIdsKey.split(',').map(int.parse).toList();
      return db.todosDao.watchPendingByTags(tagIds);
    });

final inboxTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchInbox();
});

final deletedTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchDeleted();
});

final allTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchAllNotDeleted();
});

final moveOverdueToTodayProvider = Provider<Future<void> Function(List<int>)>((
  ref,
) {
  final db = ref.read(databaseProvider);
  return (List<int> ids) => db.transaction(() async {
    await db.todosDao.moveOverdueToToday(ids);
    for (final id in ids) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    }
  });
});

final createTodoProvider =
    Provider<
      Future<int> Function({
        required int calendarId,
        required String summary,
        required int priority,
        required String status,
        DateTime? dueDate,
        DateTime? startDate,
        String? description,
        String? rrule,
        int? parentId,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({
        required calendarId,
        required summary,
        required priority,
        required status,
        dueDate,
        startDate,
        description,
        rrule,
        parentId,
      }) {
        return db.transaction(() async {
          final id = await db
              .into(db.todos)
              .insert(
                TodosCompanion.insert(
                  calendarId: calendarId,
                  summary: summary,
                  priority: Value(priority),
                  status: Value(status),
                  dueDate: dueDate != null
                      ? Value(dueDate)
                      : const Value.absent(),
                  startDate: startDate != null
                      ? Value(startDate)
                      : const Value.absent(),
                  description: description != null
                      ? Value(description)
                      : const Value.absent(),
                  rrule: rrule != null ? Value(rrule) : const Value.absent(),
                  parentId: parentId != null
                      ? Value(parentId)
                      : const Value.absent(),
                ),
              );
          await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
          return id;
        });
      };
    });

final updateTodoProvider =
    Provider<Future<void> Function(int id, TodosCompanion data)>((ref) {
      final db = ref.read(databaseProvider);
      return (int id, TodosCompanion data) => RecordScope.run(
        db,
        (tx) => TodoWriter.updateTodo(db, tx, id, data),
      );
    });

final toggleTodoProvider =
    Provider<
      Future<void> Function({required int id, required bool isCompleted})
    >((ref) {
      final db = ref.read(databaseProvider);
      final notifService = ref.read(notificationServiceProvider);
      final scheduleReminder = ref.read(scheduleReminderProvider);
      return ({required int id, required bool isCompleted}) async {
        final reminders =
            await (db.select(db.reminders)..where(
                  (t) =>
                      t.parentType.equals('todo') & t.parentId.equals(id),
                ))
                .get();
        if (isCompleted) {
          for (final r in reminders) {
            await notifService.cancel(r.id);
          }
          return db.transaction(() async {
            await db.todosDao.markComplete(id);
            await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
          });
        } else {
          for (final r in reminders) {
            await scheduleReminder(r);
          }
          return db.transaction(() async {
            await db.todosDao.markIncomplete(id);
            await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
          });
        }
      };
    });

final deleteTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  final notifService = ref.read(notificationServiceProvider);
  return (int id) async {
    // Cancel scheduled notifications for the parent AND cascade-deleted
    // children (keep reminder rows for restore).
    final children =
        await (db.select(db.todos)..where(
              (t) => t.parentId.equals(id) & t.deletedAt.isNull(),
            ))
            .get();
    final ids = [id, ...children.map((c) => c.id)];
    final reminders =
        await (db.select(db.reminders)..where(
              (t) =>
                  t.parentType.equals('todo') & t.parentId.isIn(ids),
            ))
            .get();
    for (final r in reminders) {
      await notifService.cancel(r.id);
    }
    await db.transaction(() async {
      final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
      final now = DateTime.now();
      // Soft delete parent and direct children with the same timestamp so no
      // orphan rows keep showing up in lists or as ghost reminders.
      await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await (db.update(db.todos)
            ..where((t) => t.parentId.equals(id) & t.deletedAt.isNull()))
          .write(
        TodosCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await SyncOutbox.enqueueDeletes(db, targets);
    });
  };
});

final restoreTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  final scheduleReminder = ref.read(scheduleReminderProvider);
  return (int id) async {
    final row =
        await (db.select(db.todos)..where((t) => t.id.equals(id))).getSingleOrNull();
    // Restoring a child under a still-trashed parent would hide it in the
    // active lists — untrash the parent too. Single level: no recursion up.
    int? trashedParentId;
    final parentRefId = row?.parentId;
    if (parentRefId != null) {
      final parent =
          await (db.select(db.todos)..where((t) => t.id.equals(parentRefId)))
              .getSingleOrNull();
      if (parent != null && parent.deletedAt != null) {
        trashedParentId = parent.id;
      }
    }
    final restoredIds = await db.transaction(() async {
      final now = DateTime.now();
      // Mirror cascade-delete: restoring a parent must also pull its direct
      // children out of the trash, or they stay orphaned there.
      await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          // Value(null) is required: absent columns are skipped on update, and
          // Value.absent() previously left deletedAt untouched (restore no-op).
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
      if (trashedParentId != null) {
        final untrashParentId = trashedParentId;
        await (db.update(db.todos)..where((t) => t.id.equals(untrashParentId)))
            .write(
          TodosCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
      await (db.update(db.todos)
            ..where((t) => t.parentId.equals(id) & t.deletedAt.isNotNull()))
          .write(
        TodosCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
      final restoredChildren =
          await (db.select(db.todos)..where((t) => t.parentId.equals(id)))
              .get();
      final restored = <int>[
        id,
        if (trashedParentId != null) trashedParentId,
        ...restoredChildren.map((t) => t.id),
      ];
      for (final tid in restored) {
        await SyncOutbox.enqueueUpsert(db, RecordType.todo, tid);
      }
      return restored;
    });
    // Reschedule the reminder rows of the restored parent and children;
    // scheduleReminder skips triggers already in the past.
    final reminders =
        await (db.select(db.reminders)..where(
              (t) =>
                  t.parentType.equals('todo') & t.parentId.isIn(restoredIds),
            ))
            .get();
    for (final r in reminders) {
      await scheduleReminder(r);
    }
  };
});

final permanentDeleteTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  final notifService = ref.read(notificationServiceProvider);
  return (int id) async {
    final children =
        await (db.select(db.todos)..where((t) => t.parentId.equals(id))).get();
    final ids = [id, ...children.map((c) => c.id)];
    final reminders =
        await (db.select(db.reminders)..where(
              (t) =>
                  t.parentType.equals('todo') & t.parentId.isIn(ids),
            ))
            .get();
    for (final r in reminders) {
      await notifService.cancel(r.id);
    }
    // FK-safe delete order (mirrors emptyTrash): child-rows first, todo rows
    // last, all in one transaction; notifications cancelled above.
    await db.transaction(() async {
      final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
      for (final tid in ids) {
        await (db.delete(db.todoTags)..where((t) => t.todoId.equals(tid))).go();
      }
      await (db.delete(
        db.attachments,
      )..where((t) => t.parentType.equals('todo') & t.parentId.isIn(ids))).go();
      await (db.delete(
        db.reminders,
      )..where((t) => t.parentType.equals('todo') & t.parentId.isIn(ids))).go();
      await (db.delete(db.todos)..where((t) => t.id.isIn(ids))).go();
      await SyncOutbox.enqueueDeletes(db, targets);
    });
  };
});

final emptyTrashProvider = Provider<Future<void> Function()>((ref) {
  final db = ref.read(databaseProvider);
  final notifService = ref.read(notificationServiceProvider);
  return () async {
    final deleted =
        await (db.select(db.todos)..where((t) => t.deletedAt.isNotNull()))
            .get();
    final ids = deleted.map((t) => t.id).toList();
    if (ids.isNotEmpty) {
      final reminders =
          await (db.select(db.reminders)..where(
                (t) => t.parentType.equals('todo') & t.parentId.isIn(ids),
              ))
              .get();
      for (final r in reminders) {
        await notifService.cancel(r.id);
      }
    }
    await db.transaction(() async {
      final targets = await SyncOutbox.captureDeletes(db, RecordType.todo, ids);
      await db.todosDao.emptyTrash();
      await SyncOutbox.enqueueDeletes(db, targets);
    });
  };
});

final reorderTodosProvider = Provider<Future<void> Function(List<int>)>((ref) {
  final db = ref.read(databaseProvider);
  return (List<int> ids) => db.transaction(() async {
    await db.todosDao.updateSortOrders(ids);
    for (final id in ids) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    }
  });
});

/// Subtasks for a given parent todo.
final subtasksProvider = StreamProvider.autoDispose.family<List<Todo>, int>((
  ref,
  parentId,
) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchSubtasks(parentId);
});

/// Set parent for a todo (null to remove parent).
final setParentProvider = Provider<Future<void> Function(int todoId, int? parentId)>((ref) {
  final db = ref.read(databaseProvider);
  return (int todoId, int? parentId) => db.transaction(() async {
    await db.todosDao.setParent(todoId, parentId);
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, todoId);
  });
});
