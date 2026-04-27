import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';

final pendingTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchPending();
});

final completedTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchCompleted();
});

final overdueTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchOverdue();
});

final moveOverdueToTodayProvider = Provider<Future<void> Function(List<int>)>((ref) {
  final db = ref.watch(databaseProvider);
  return (List<int> ids) => db.todosDao.moveOverdueToToday(ids);
});

final createTodoProvider = Provider<Future<int> Function({
  required int calendarId,
  required String uid,
  required String summary,
  required int priority,
  required String status,
  DateTime? dueDate,
  DateTime? startDate,
  String? description,
  String? rrule,
})>((ref) {
  final db = ref.watch(databaseProvider);
  return ({
    required calendarId,
    required uid,
    required summary,
    required priority,
    required status,
    dueDate,
    startDate,
    description,
    rrule,
  }) async {
    return db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            uid: uid,
            summary: summary,
            priority: Value(priority),
            status: Value(status),
            dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
            startDate: startDate != null ? Value(startDate) : const Value.absent(),
            description:
                description != null ? Value(description) : const Value.absent(),
            rrule: rrule != null ? Value(rrule) : const Value.absent(),
          ),
        );
  };
});

final toggleTodoProvider = Provider<Future<void> Function({required int id, required bool isCompleted})>((ref) {
  final db = ref.watch(databaseProvider);
  return ({required int id, required bool isCompleted}) {
    if (isCompleted) {
      return db.todosDao.markComplete(id);
    } else {
      return db.todosDao.markIncomplete(id);
    }
  };
});

final deleteTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  final notifService = ref.watch(notificationServiceProvider);
  return (int id) async {
    // Cancel and delete reminders
    final reminders = await (db.select(db.reminders)
          ..where((t) => t.parentType.equals('todo') & t.parentId.equals(id)))
        .get();
    for (final r in reminders) {
      await notifService.cancel(r.id);
    }
    await (db.delete(db.reminders)
          ..where((t) => t.parentType.equals('todo') & t.parentId.equals(id)))
        .go();
    // Delete junction table rows
    await (db.delete(db.todoTags)..where((t) => t.todoId.equals(id))).go();
    // Delete attachments
    await (db.delete(db.attachments)
          ..where((t) => t.parentType.equals('todo') & t.parentId.equals(id)))
        .go();
    // Delete the todo itself
    await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
  };
});
