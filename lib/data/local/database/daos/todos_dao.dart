import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/todos_table.dart';
import '../tables/todo_tags_table.dart';

part 'todos_dao.g.dart';

@DriftAccessor(tables: [Todos, TodoTags])
class TodosDao extends DatabaseAccessor<AppDatabase> with _$TodosDaoMixin {
  TodosDao(super.db);

  Stream<List<Todo>> watchPending() {
    return (select(todos)
          ..where((t) => t.status.isNotIn(const ['COMPLETED', 'CANCELLED']))
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.dueDate),
          ]))
        .watch();
  }

  Future<void> markComplete(int id) {
    return (update(todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(
        status: const Value('COMPLETED'),
        completedAt: Value(DateTime.now()),
        percentComplete: const Value(100),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markIncomplete(int id) {
    return (update(todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(
        status: const Value('NEEDS-ACTION'),
        completedAt: const Value.absent(),
        percentComplete: const Value(0),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<Todo>> watchCompleted() {
    return (select(todos)
          ..where((t) => t.status.equals('COMPLETED'))
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
        .watch();
  }

  Stream<List<Todo>> watchByDueDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(todos)..where(
          (t) =>
              t.dueDate.isBiggerOrEqualValue(startOfDay) &
              t.dueDate.isSmallerThanValue(endOfDay),
        ))
        .watch();
  }

  Stream<List<Todo>> watchOverdue() {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return (select(todos)..where(
          (t) =>
              t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
              t.dueDate.isNotNull() &
              t.dueDate.isSmallerThanValue(today),
        ))
        .watch();
  }

  Future<List<Todo>> getOverduePending() {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return (select(todos)..where(
          (t) =>
              t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
              t.dueDate.isNotNull() &
              t.dueDate.isSmallerThanValue(today),
        ))
        .get();
  }

  Future<void> moveOverdueToToday(List<int> ids) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return (update(todos)..where((t) => t.id.isIn(ids))).write(
      TodosCompanion(
        dueDate: Value(today),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> upsert(Todo entry) {
    return into(todos).insertOnConflictUpdate(entry);
  }

  Future<List<Todo>> searchTodos(String query) {
    final pattern = '%$query%';
    return (select(todos)
          ..where((t) => t.summary.like(pattern) | t.description.like(pattern))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)])
          ..limit(50))
        .get();
  }

  Stream<List<Todo>> watchPendingByTags(List<int> tagIds) {
    final query =
        select(
            todos,
          ).join([innerJoin(todoTags, todoTags.todoId.equalsExp(todos.id))])
          ..where(todos.status.isNotIn(const ['COMPLETED', 'CANCELLED']))
          ..where(todoTags.tagId.isIn(tagIds))
          ..groupBy([todos.id])
          ..orderBy([
            OrderingTerm.asc(todos.priority),
            OrderingTerm.asc(todos.dueDate),
          ]);
    return query.map((row) => row.readTable(todos)).watch();
  }
}
