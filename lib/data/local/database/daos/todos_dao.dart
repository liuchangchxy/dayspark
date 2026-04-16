import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/todos_table.dart';

part 'todos_dao.g.dart';

@DriftAccessor(tables: [Todos])
class TodosDao extends DatabaseAccessor<AppDatabase>
    with _$TodosDaoMixin {
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

  Stream<List<Todo>> watchByDueDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(todos)
          ..where((t) =>
              t.dueDate.isBiggerOrEqualValue(startOfDay) &
              t.dueDate.isSmallerThanValue(endOfDay)))
        .watch();
  }

  Future<void> upsert(Todo entry) {
    return into(todos).insertOnConflictUpdate(entry);
  }
}
