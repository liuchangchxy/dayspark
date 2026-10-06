import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

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

  String get displayLabel {
    if (nominalAnchor.valueType == RecurrenceValueType.date) {
      return nominalAnchor.canonical;
    }
    return nominalAnchor.canonical.replaceFirst('T', '  ');
  }
}

final class TodoOccurrenceExpansion {
  const TodoOccurrenceExpansion(this.status, this.occurrences);

  final TodoOccurrenceExpansionStatus status;
  final List<TodoOccurrence> occurrences;
}

/// One page's virtual occurrence joined to its sparse persisted state.
final class TodoOccurrenceStateProjection {
  const TodoOccurrenceStateProjection({
    required this.occurrence,
    required this.status,
  });

  final TodoOccurrence occurrence;
  final String status;
}

DateTime civilDateAddDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// A projected recurring task instance with parent Todo, exact occurrence,
/// and sparse instance state.
final class ProjectedTaskInstance {
  const ProjectedTaskInstance({
    required this.todo,
    required this.occurrence,
    required this.status,
    this.completedAt,
  });

  final Todo todo;
  final TodoOccurrence occurrence;
  final String status;
  final DateTime? completedAt;

  int get todoId => todo.id;
  String get todoSyncId => occurrence.todoSyncId;
  String get occurrenceId => occurrence.occurrenceId;
  bool get isCompleted => status == 'completed';
  bool get isSkipped => status == 'skipped';
  bool get isPending => status == 'pending';

  /// Ruling E — Action-day semantics for DATE vs DATE-TIME.
  bool isToday(DateTime actionDate) {
    if (occurrence.nominalAnchor.valueType == RecurrenceValueType.date) {
      final date = occurrence.nominalAnchor as LocalDate;
      return date.year == actionDate.year &&
          date.month == actionDate.month &&
          date.day == actionDate.day;
    }
    final instant = occurrence.resolvedStartInstant;
    if (instant == null) return false;
    final DateTime startOfDayInstant;
    final DateTime endOfDayInstant;
    if (actionDate.isUtc) {
      startOfDayInstant = DateTime.utc(actionDate.year, actionDate.month, actionDate.day);
      endOfDayInstant = DateTime.utc(actionDate.year, actionDate.month, actionDate.day + 1);
    } else {
      startOfDayInstant = DateTime(actionDate.year, actionDate.month, actionDate.day).toUtc();
      endOfDayInstant = DateTime(actionDate.year, actionDate.month, actionDate.day + 1).toUtc();
    }
    return !instant.isBefore(startOfDayInstant) &&
        instant.isBefore(endOfDayInstant);
  }

  /// Ruling E & A: strictly before Action-day boundary and within recent 30 civil days.
  bool isMissedWithin30Days(DateTime actionDate) {
    if (occurrence.nominalAnchor.valueType == RecurrenceValueType.date) {
      final date = occurrence.nominalAnchor as LocalDate;
      final occDate = DateTime(date.year, date.month, date.day);
      final startOfDay = DateTime(actionDate.year, actionDate.month, actionDate.day);
      final thirtyDaysAgo = civilDateAddDays(startOfDay, -30);
      return occDate.isBefore(startOfDay) && !occDate.isBefore(thirtyDaysAgo);
    }
    final instant = occurrence.resolvedStartInstant;
    if (instant == null) return false;
    final DateTime startOfDayInstant;
    final DateTime thirtyDaysAgoInstant;
    if (actionDate.isUtc) {
      startOfDayInstant = DateTime.utc(actionDate.year, actionDate.month, actionDate.day);
      thirtyDaysAgoInstant = DateTime.utc(actionDate.year, actionDate.month, actionDate.day - 30);
    } else {
      final startOfDay = DateTime(actionDate.year, actionDate.month, actionDate.day);
      startOfDayInstant = startOfDay.toUtc();
      thirtyDaysAgoInstant = civilDateAddDays(startOfDay, -30).toUtc();
    }
    return instant.isBefore(startOfDayInstant) &&
        !instant.isBefore(thirtyDaysAgoInstant);
  }

  /// Strictly before recent 30 civil-day boundary.
  bool isEarlierMissed(DateTime actionDate) {
    if (occurrence.nominalAnchor.valueType == RecurrenceValueType.date) {
      final date = occurrence.nominalAnchor as LocalDate;
      final occDate = DateTime(date.year, date.month, date.day);
      final thirtyDaysAgo = civilDateAddDays(
        DateTime(actionDate.year, actionDate.month, actionDate.day),
        -30,
      );
      return occDate.isBefore(thirtyDaysAgo);
    }
    final instant = occurrence.resolvedStartInstant;
    if (instant == null) return false;
    final DateTime thirtyDaysAgoInstant;
    if (actionDate.isUtc) {
      thirtyDaysAgoInstant = DateTime.utc(actionDate.year, actionDate.month, actionDate.day - 30);
    } else {
      final startOfDay = DateTime(actionDate.year, actionDate.month, actionDate.day);
      thirtyDaysAgoInstant = civilDateAddDays(startOfDay, -30).toUtc();
    }
    return instant.isBefore(thirtyDaysAgoInstant);
  }
}

/// Loads one paged window of occurrence projections for [todo].
/// page = 1: recent 30 civil-day history + future 90 days.
/// page > 1: [30 * page, 30 * (page - 1)] civil days in the past.
Future<List<ProjectedTaskInstance>> loadOccurrencePage(
  AppDatabase db,
  Todo todo, {
  required int historyPage,
  required DateTime anchorDate,
}) async {
  final now = anchorDate;
  final today = DateTime(now.year, now.month, now.day);
  final pastStart = civilDateAddDays(today, -30 * historyPage);
  final pastEnd = civilDateAddDays(today, -30 * (historyPage - 1));
  final pastExpansion = expandTodoOccurrences(
    todo,
    startInclusive: pastStart,
    endExclusive: pastEnd,
    maxOccurrences: 100,
  );
  if (pastExpansion.status != TodoOccurrenceExpansionStatus.expanded) {
    return const [];
  }
  final List<TodoOccurrence> combinedOccurrences;
  if (historyPage == 1) {
    final futureExpansion = expandTodoOccurrences(
      todo,
      startInclusive: today,
      endExclusive: civilDateAddDays(today, 91),
      maxOccurrences: 100,
    );
    combinedOccurrences = [
      ...pastExpansion.occurrences,
      if (futureExpansion.status == TodoOccurrenceExpansionStatus.expanded)
        ...futureExpansion.occurrences,
    ];
  } else {
    combinedOccurrences = pastExpansion.occurrences;
  }
  if (combinedOccurrences.isEmpty) return const [];
  final syncId = combinedOccurrences.first.todoSyncId;
  final occurrenceIds = combinedOccurrences.map((o) => o.occurrenceId).toSet();
  final states = await (db.select(db.taskInstanceStates)..where(
        (state) =>
            state.todoSyncId.equals(syncId) &
            state.occurrenceId.isIn(occurrenceIds),
      )).get();
  final stateByOccurrence = {for (final s in states) s.occurrenceId: s};
  final items = combinedOccurrences
      .map((occ) {
        final st = stateByOccurrence[occ.occurrenceId];
        return ProjectedTaskInstance(
          todo: todo,
          occurrence: occ,
          status: st?.status ?? 'pending',
          completedAt: st?.completedAt,
        );
      })
      .where((item) => !item.isSkipped)
      .toList();

  items.sort(
    (a, b) => a.occurrence.nominalAnchor.canonical.compareTo(
      b.occurrence.nominalAnchor.canonical,
    ),
  );
  return items;
}

/// Loads only sparse states whose canonical IDs occur in [expansion].
/// Call once for each bounded page; never infer state from a recent-N query.
Future<List<TodoOccurrenceStateProjection>> projectTodoOccurrenceStates(
  AppDatabase db,
  TodoOccurrenceExpansion expansion,
) async {
  if (expansion.occurrences.isEmpty) return const [];
  final syncId = expansion.occurrences.first.todoSyncId;
  final occurrenceIds = expansion.occurrences
      .map((occurrence) => occurrence.occurrenceId)
      .toSet();
  final states =
      await (db.select(db.taskInstanceStates)..where(
            (state) =>
                state.todoSyncId.equals(syncId) &
                state.occurrenceId.isIn(occurrenceIds),
          ))
          .get();
  final stateByOccurrence = {
    for (final state in states) state.occurrenceId: state,
  };
  return List.unmodifiable(
    expansion.occurrences.map(
      (occurrence) => TodoOccurrenceStateProjection(
        occurrence: occurrence,
        status: stateByOccurrence[occurrence.occurrenceId]?.status ?? 'pending',
      ),
    ),
  );
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
      final DateTime startInstant;
      final DateTime endInstant;
      if (startInclusive.isUtc) {
        startInstant = startInclusive;
        endInstant = endExclusive;
      } else {
        final location = tz.getLocation(spec.timeZone);
        startInstant = tz.TZDateTime(
          location,
          startInclusive.year,
          startInclusive.month,
          startInclusive.day,
          startInclusive.hour,
          startInclusive.minute,
          startInclusive.second,
        ).toUtc();
        endInstant = tz.TZDateTime(
          location,
          endExclusive.year,
          endExclusive.month,
          endExclusive.day,
          endExclusive.hour,
          endExclusive.minute,
          endExclusive.second,
        ).toUtc();
      }
      window = InstantWindow(
        startInclusive: startInstant,
        endExclusive: endInstant,
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

/// Resolves a [TodoOccurrence] from parent [todo] and [occurrenceId]
/// preserving its true [resolvedStartInstant], independent of completion time.
TodoOccurrence? resolveTodoOccurrence(Todo todo, String occurrenceId) {
  try {
    final parsed = OccurrenceId.parse(occurrenceId);
    final recurrence = TodoRecurrence.fromTodo(todo);
    final spec = recurrence.spec;
    if (spec != null) {
      ensureTodoRecurrenceTimeZonesInitialized();
      final RecurrenceWindow window;
      if (parsed.nominal case final LocalDate date) {
        window = LocalDateWindow(
          startInclusive: date,
          endExclusive: date.addDays(1),
        );
      } else {
        final nominal = parsed.nominal as LocalDateTime;
        final candidate = DateTime.utc(
          nominal.year,
          nominal.month,
          nominal.day,
          nominal.hour,
          nominal.minute,
          nominal.second,
        );
        window = InstantWindow(
          startInclusive: candidate.subtract(const Duration(days: 2)),
          endExclusive: candidate.add(const Duration(days: 3)),
        );
      }
      final matches = const RecurrenceEngine().expand(spec, window: window, limit: 10);
      for (final occ in matches) {
        if (occ.nominal == parsed.nominal) {
          return TodoOccurrence(
            todoSyncId: todo.syncId ?? occ.occurrenceId.value,
            occurrenceId: occurrenceId,
            nominalAnchor: occ.nominal,
            resolvedStartInstant: occ.resolvedInstant,
            timeZone: spec.timeZone,
          );
        }
      }
    }
    DateTime? resolvedInstant;
    if (parsed.nominal case final LocalDateTime nominal) {
      final loc = tz.getLocation(parsed.timeZone?.id ?? 'UTC');
      resolvedInstant = tz.TZDateTime(
        loc,
        nominal.year,
        nominal.month,
        nominal.day,
        nominal.hour,
        nominal.minute,
        nominal.second,
      ).toUtc();
    }
    return TodoOccurrence(
      todoSyncId: todo.syncId ?? '',
      occurrenceId: occurrenceId,
      nominalAnchor: parsed.nominal,
      resolvedStartInstant: resolvedInstant,
      timeZone: parsed.timeZone?.id ?? 'UTC',
    );
  } catch (_) {
    return null;
  }
}
