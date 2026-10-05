import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

enum TodoOccurrenceExpansionStatus {
  expanded,
  notRecurring,
  requiresLegacyConfirmation,
  unsupported,
}

final class TodoOccurrence {
  const TodoOccurrence({
    required this.todoSyncId,
    required this.occurrenceId,
    required this.nominalAnchor,
    required this.resolvedStartInstant,
    required this.timeZone,
  });

  final String todoSyncId;
  final String occurrenceId;
  final RecurrenceLocalValue nominalAnchor;
  final DateTime? resolvedStartInstant;
  final String timeZone;
}

final class TodoOccurrenceExpansion {
  const TodoOccurrenceExpansion(this.status, this.occurrences);

  final TodoOccurrenceExpansionStatus status;
  final List<TodoOccurrence> occurrences;
}

TodoOccurrenceExpansion expandTodoOccurrences(
  Todo todo, {
  required DateTime startInclusive,
  required DateTime endExclusive,
  int maxOccurrences = 100,
}) {
  if (todo.rrule != null && todo.recurrenceLegacyState != 'knownZoned') {
    return const TodoOccurrenceExpansion(
      TodoOccurrenceExpansionStatus.requiresLegacyConfirmation,
      [],
    );
  }
  final TodoRecurrence recurrence;
  try {
    recurrence = TodoRecurrence.fromTodo(todo);
  } on RecurrenceRuleException catch (error) {
    if (error.kind == RecurrenceRuleErrorKind.unsupported) {
      return const TodoOccurrenceExpansion(
        TodoOccurrenceExpansionStatus.unsupported,
        [],
      );
    }
    rethrow;
  }
  if (recurrence.isUnknownLegacy) {
    return const TodoOccurrenceExpansion(
      TodoOccurrenceExpansionStatus.requiresLegacyConfirmation,
      [],
    );
  }
  final spec = recurrence.spec;
  if (spec == null) {
    return const TodoOccurrenceExpansion(
      TodoOccurrenceExpansionStatus.notRecurring,
      [],
    );
  }
  try {
    ensureTodoRecurrenceTimeZonesInitialized();
    final RecurrenceWindow window;
    if (spec.anchor.valueType == RecurrenceValueType.date) {
      window = LocalDateWindow(
        startInclusive: LocalDate(
          startInclusive.year,
          startInclusive.month,
          startInclusive.day,
        ),
        endExclusive: LocalDate(
          endExclusive.year,
          endExclusive.month,
          endExclusive.day,
        ),
      );
    } else {
      window = InstantWindow(
        startInclusive: startInclusive.toUtc(),
        endExclusive: endExclusive.toUtc(),
      );
    }
    final occurrences = const RecurrenceEngine().expand(
      spec,
      window: window,
      limit: maxOccurrences,
    );
    final syncId = todo.syncId;
    if (syncId == null || syncId.isEmpty) {
      throw StateError('Recurring Todo requires a sync identity.');
    }
    return TodoOccurrenceExpansion(
      TodoOccurrenceExpansionStatus.expanded,
      List.unmodifiable(
        occurrences.map(
          (occurrence) => TodoOccurrence(
            todoSyncId: syncId,
            occurrenceId: occurrence.occurrenceId.value,
            nominalAnchor: occurrence.nominal,
            resolvedStartInstant: occurrence.resolvedInstant,
            timeZone: spec.timeZone,
          ),
        ),
      ),
    );
  } on RecurrenceRuleException catch (error) {
    if (error.kind == RecurrenceRuleErrorKind.unsupported) {
      return const TodoOccurrenceExpansion(
        TodoOccurrenceExpansionStatus.unsupported,
        [],
      );
    }
    rethrow;
  }
}

bool isOccurrenceStillValidForSeries(Todo todo, String occurrenceId) {
  final recurrence = TodoRecurrence.fromTodo(todo);
  final spec = recurrence.spec;
  if (spec == null || recurrence.isUnknownLegacy) return false;
  ensureTodoRecurrenceTimeZonesInitialized();
  return isOccurrenceValidForSpec(spec, occurrenceId);
}
