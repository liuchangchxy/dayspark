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
    // The writer stores allocation spans as UTC instants (events keep local
    // wall time), and every calendar surface compares and prints wall-clock
    // fields: without this the block was drawn in the right slot but labelled
    // with the UTC hour, and any plan before 08:00 local fell on the day
    // before.
    start: item.allocation.startAt.toLocal(),
    end: item.allocation.endAt.toLocal(),
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
