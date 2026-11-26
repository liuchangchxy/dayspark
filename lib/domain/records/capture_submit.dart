import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';

/// The one write path behind both desktop capture surfaces: a todo, then the
/// optional allocation and reminder its draft asked for. The reminder is
/// anchored to the deadline when there is one, otherwise to the planned start,
/// exactly like the composer does; either fact can carry a reminder.
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
    if (reminderOffset != null) {
      final anchor = dueDate ?? planStart;
      if (anchor != null) {
        await ref.read(createReminderProvider)(
          parentType: 'todo',
          parentId: todoId,
          triggerTime: anchor.subtract(reminderOffset),
        );
      }
    }
    return todoId;
  });
}
