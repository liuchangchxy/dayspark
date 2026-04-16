import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/domain/providers/database_provider.dart';

final pendingTodosProvider = StreamProvider<List<Todo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchPending();
});

final todosByDueDateProvider = StreamProvider.family<List<Todo>, DateTime>(
  (ref, date) {
    final db = ref.watch(databaseProvider);
    return db.todosDao.watchByDueDate(date);
  },
);

final createTodoProvider = Provider<Future<int> Function({
  required int calendarId,
  required String uid,
  required String summary,
  required int priority,
  required String status,
  DateTime? dueDate,
  String? description,
})>((ref) {
  final db = ref.watch(databaseProvider);
  return ({
    required calendarId,
    required uid,
    required summary,
    required priority,
    required status,
    dueDate,
    description,
  }) async {
    return db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            uid: uid,
            summary: summary,
            priority: Value(priority),
            status: Value(status),
            dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
            description:
                description != null ? Value(description) : const Value.absent(),
          ),
        );
  };
});

final completeTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  return (int id) => db.todosDao.markComplete(id);
});

final deleteTodoProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  return (int id) async {
    await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
  };
});
