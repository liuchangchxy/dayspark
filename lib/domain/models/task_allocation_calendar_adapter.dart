import 'package:dayspark/domain/providers/task_allocations_provider.dart';

class TaskAllocationCalendarAdapter {
  const TaskAllocationCalendarAdapter({
    required this.id,
    required this.todoId,
    required this.todoTitle,
    required this.start,
    required this.end,
  });

  factory TaskAllocationCalendarAdapter.fromItem(
    TaskAllocationCalendarItem item,
  ) => TaskAllocationCalendarAdapter(
    id: item.allocation.id,
    todoId: item.todo.id,
    todoTitle: item.todo.summary,
    start: item.allocation.startAt,
    end: item.allocation.endAt,
  );

  final int id;
  final int todoId;
  final String todoTitle;
  final DateTime start;
  final DateTime end;

  TaskAllocationCalendarAdapter copyWith({DateTime? start, DateTime? end}) =>
      TaskAllocationCalendarAdapter(
        id: id,
        todoId: todoId,
        todoTitle: todoTitle,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}
