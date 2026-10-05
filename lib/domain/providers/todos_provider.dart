import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final completedTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchCompleted();
});

final pendingTodosByTagsProvider = StreamProvider.autoDispose
    .family<List<Todo>, String>((ref, tagIdsKey) {
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
  return (List<int> ids) =>
      RecordScope.run(db, (tx) => TodoWriter.moveOverdueToToday(db, tx, ids));
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
        RecurrenceSpec? recurrenceSpec,
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
        recurrenceSpec,
        parentId,
      }) {
        return RecordScope.run(
          db,
          (tx) => TodoWriter.create(
            db,
            tx,
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: summary,
              priority: Value(priority),
              status: Value(status),
              dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
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
            recurrenceSpec: recurrenceSpec,
          ),
        );
      };
    });

final updateTodoProvider =
    Provider<
      Future<void> Function(
        int id,
        TodosCompanion data, {
        RecurrenceSpec? recurrenceSpec,
        bool replaceRecurrence,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return (
        int id,
        TodosCompanion data, {
        RecurrenceSpec? recurrenceSpec,
        bool replaceRecurrence = false,
      }) => RecordScope.run(
        db,
        (tx) => TodoWriter.updateTodo(
          db,
          tx,
          id,
          data,
          recurrenceSpec: recurrenceSpec,
          replaceRecurrence: replaceRecurrence,
        ),
      );
    });

final confirmLegacyRecurrenceProvider =
    Provider<
      Future<void> Function({
        required int todoId,
        required String timeZone,
        required RecurrenceAnchor interpretation,
        required String rrule,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({
        required todoId,
        required timeZone,
        required interpretation,
        required rrule,
      }) => RecordScope.run(
        db,
        (tx) => TodoWriter.confirmLegacyRecurrence(
          db,
          tx,
          todoId: todoId,
          chosenTimeZone: timeZone,
          interpretation: interpretation,
          validatedRRule: rrule,
        ),
      );
    });

final toggleTodoProvider =
    Provider<
      Future<void> Function({
        required int id,
        required bool isCompleted,
        String? occurrenceId,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({required int id, required bool isCompleted, occurrenceId}) =>
          RecordScope.run(
            db,
            (tx) => TodoWriter.setCompletion(
              db,
              tx,
              id,
              isCompleted: isCompleted,
              occurrenceId: occurrenceId,
            ),
          );
    });

final ensureTodoSyncIdentityProvider = Provider<Future<Todo> Function(int)>((
  ref,
) {
  final db = ref.read(databaseProvider);
  return (int todoId) => RecordScope.run(db, (tx) async {
    await SyncOutbox.enqueueUpsert(db, RecordType.todo, todoId);
    tx.applied(RecordType.todo, todoId);
    return (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();
  });
});

final deleteTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) =>
      RecordScope.run(db, (tx) => TodoWriter.softDelete(db, tx, id));
});

final restoreTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) =>
      RecordScope.run(db, (tx) => TodoWriter.restore(db, tx, id));
});

final permanentDeleteTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) =>
      RecordScope.run(db, (tx) => TodoWriter.permanentDelete(db, tx, id));
});

final emptyTrashProvider = Provider<Future<void> Function()>((ref) {
  final db = ref.read(databaseProvider);
  return () => RecordScope.run(db, (tx) => TodoWriter.emptyTrash(db, tx));
});

final reorderTodosProvider = Provider<Future<void> Function(List<int>)>((ref) {
  final db = ref.read(databaseProvider);
  return (List<int> ids) =>
      RecordScope.run(db, (tx) => TodoWriter.reorder(db, tx, ids));
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
final setParentProvider =
    Provider<Future<void> Function(int todoId, int? parentId)>((ref) {
      final db = ref.read(databaseProvider);
      return (int todoId, int? parentId) => RecordScope.run(
        db,
        (tx) => TodoWriter.setParent(db, tx, todoId, parentId),
      );
    });
