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
          ..where(
            (t) =>
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                t.deletedAt.isNull(),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
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
          ..where((t) => t.status.equals('COMPLETED') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
        .watch();
  }

  Stream<List<Todo>> watchByDueDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(todos)..where(
          (t) =>
              t.deletedAt.isNull() &
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
              t.deletedAt.isNull() &
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
              t.deletedAt.isNull() &
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
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                (t.summary.like(pattern) | t.description.like(pattern)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)])
          ..limit(50))
        .get();
  }

  Stream<List<Todo>> watchPendingByTags(List<int> tagIds) {
    final query =
        select(
            todos,
          ).join([innerJoin(todoTags, todoTags.todoId.equalsExp(todos.id))])
          ..where(
            todos.deletedAt.isNull() &
                todos.status.isNotIn(const ['COMPLETED', 'CANCELLED']),
          )
          ..where(todoTags.tagId.isIn(tagIds))
          ..groupBy([todos.id])
          ..orderBy([
            OrderingTerm.asc(todos.priority),
            OrderingTerm.asc(todos.dueDate),
          ]);
    return query.map((row) => row.readTable(todos)).watch();
  }

  Stream<List<Todo>> watchInbox() {
    return (select(todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                t.dueDate.isNull(),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.priority),
          ]))
        .watch();
  }

  Stream<List<Todo>> watchDeleted() {
    return (select(todos)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  Stream<List<Todo>> watchAllNotDeleted() {
    return (select(todos)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.status),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.dueDate),
          ]))
        .watch();
  }

  Future<void> emptyTrash() {
    return (delete(todos)..where((t) => t.deletedAt.isNotNull())).go();
  }

  /// Update the sort order for a list of todo IDs in batch.
  Future<void> updateSortOrders(List<int> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(todos)..where((t) => t.id.equals(ids[i]))).write(
          TodosCompanion(sortOrder: Value(i), updatedAt: Value(DateTime.now())),
        );
      }
    });
  }
}
