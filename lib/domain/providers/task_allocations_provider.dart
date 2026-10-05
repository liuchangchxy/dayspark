import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/task_allocation_writer.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

final taskAllocationsForTodoProvider = StreamProvider.autoDispose
    .family<List<TaskAllocation>, int>((ref, todoId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.taskAllocations)
            ..where((row) => row.todoId.equals(todoId))
            ..orderBy([(row) => OrderingTerm.asc(row.startAt)]))
          .watch();
    });

final taskAllocationsInDateRangeProvider = StreamProvider.autoDispose
    .family<List<TaskAllocationCalendarItem>, String>((ref, rangeKey) {
      final db = ref.watch(databaseProvider);
      final parts = rangeKey.split('-');
      if (parts.length != 2) return Stream.value(const []);
      final startMs = int.tryParse(parts[0]);
      final endMs = int.tryParse(parts[1]);
      if (startMs == null || endMs == null || endMs <= startMs) {
        return Stream.value(const []);
      }
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final end = DateTime.fromMillisecondsSinceEpoch(endMs);
      final query =
          db.select(db.taskAllocations).join([
            innerJoin(
              db.todos,
              db.todos.id.equalsExp(db.taskAllocations.todoId),
            ),
          ])..where(
            db.taskAllocations.state.equals('active') &
                db.taskAllocations.startAt.isSmallerThanValue(
                  end.toUtc().millisecondsSinceEpoch,
                ) &
                db.taskAllocations.endAt.isBiggerThanValue(
                  start.toUtc().millisecondsSinceEpoch,
                ) &
                db.todos.deletedAt.isNull() &
                db.todos.status.isNotIn(const ['CANCELLED']),
          );
      return query.watch().map(
        (rows) => rows
            .map((row) {
              final allocation = row.readTable(db.taskAllocations);
              final todo = row.readTable(db.todos);
              final completedAt = todo.completedAt;
              final recurring = todo.rrule != null && todo.rrule!.isNotEmpty;
              final validOccurrence = !recurring
                  ? allocation.occurrenceId == null
                  : allocation.occurrenceId != null &&
                        _isValidOccurrence(todo, allocation.occurrenceId!);
              final passesCompletionBoundary =
                  todo.status != 'COMPLETED' ||
                  (completedAt != null &&
                      allocation.startAt.toUtc().millisecondsSinceEpoch <
                          completedAt.toUtc().millisecondsSinceEpoch);
              return passesCompletionBoundary && validOccurrence
                  ? TaskAllocationCalendarItem(
                      allocation: allocation,
                      todo: todo,
                    )
                  : null;
            })
            .whereType<TaskAllocationCalendarItem>()
            .toList(),
      );
    });

bool _isValidOccurrence(Todo todo, String occurrenceId) {
  try {
    return !TodoRecurrence.fromTodo(todo).isUnknownLegacy &&
        isOccurrenceStillValidForSeries(todo, occurrenceId);
  } on FormatException {
    return false;
  } on RecurrenceRuleException {
    return false;
  }
}

final createTaskAllocationProvider =
    Provider<
      Future<int> Function({
        required int todoId,
        required DateTime startAt,
        required DateTime endAt,
        String? occurrenceId,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({
        required todoId,
        required startAt,
        required endAt,
        occurrenceId,
      }) => RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          startAt: startAt,
          endAt: endAt,
          occurrenceId: occurrenceId,
        ),
      );
    });

final rescheduleTaskAllocationProvider =
    Provider<
      Future<void> Function({
        required int id,
        required DateTime startAt,
        required DateTime endAt,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({required id, required startAt, required endAt}) =>
          RecordScope.run(
            db,
            (tx) => TaskAllocationWriter.reschedule(
              db,
              tx,
              id: id,
              startAt: startAt,
              endAt: endAt,
            ),
          );
    });

final cancelTaskAllocationProvider = Provider<Future<void> Function(int)>((
  ref,
) {
  final db = ref.read(databaseProvider);
  return (id) =>
      RecordScope.run(db, (tx) => TaskAllocationWriter.cancel(db, tx, id));
});

final class TaskAllocationCalendarItem {
  const TaskAllocationCalendarItem({
    required this.allocation,
    required this.todo,
  });

  final TaskAllocation allocation;
  final Todo todo;
}
