import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';

/// The one write path behind both desktop capture surfaces: a todo, then the
/// optional allocation and reminder its draft asked for. A reminder is only
/// written when a due date exists, because the reconciler derives every todo
/// reminder's reference from `todos.dueDate`; a plan-only reminder would never
/// fire.
Future<int> writeCapturedTodo(
  WidgetRef ref, {
  required int calendarId,
  required String summary,
  DateTime? dueDate,
  DateTime? planStart,
  DateTime? planEnd,
  Duration? reminderOffset,
}) {
  return RecordScope.run(ref.read(databaseProvider), (tx) async {
    final todoId = await ref.read(createTodoProvider)(
      calendarId: calendarId,
      summary: summary,
      priority: 0,
      status: 'NEEDS-ACTION',
      dueDate: dueDate,
    );
    if (planStart != null && planEnd != null) {
      await ref.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: planStart,
        endAt: planEnd,
      );
    }
    if (reminderOffset != null && dueDate != null) {
      await ref.read(createReminderProvider)(
        parentType: 'todo',
        parentId: todoId,
        triggerTime: dueDate.subtract(reminderOffset),
      );
    }
    return todoId;
  });
}
