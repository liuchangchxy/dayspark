import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

/// Pure computational and direct database query seam for Action & Widget projections.
/// Ensures Action page and HomeWidget share the exact same domain truth:
/// Event recurrence expansion, TaskAllocation validity, and TaskInstance projection.
class ActionProjectionQuery {
  const ActionProjectionQuery._();

  /// Pure in-memory computation of [ActionProjectionData].
  static ActionProjectionData compute({
    required DateTime date,
    required List<Event> eventCandidates,
    required List<TaskAllocationCalendarItem> allocations,
    required List<Todo> dueTodayTodos,
    required List<Todo> overdueTodos,
    required int unplannedCount,
    required List<Todo> completedTodayTodos,
    required List<Todo> recurringTodos,
    required List<Todo> allTodos,
    required List<TaskInstanceState> instanceStates,
  }) {
    final startOfDay = date.isUtc
        ? DateTime.utc(date.year, date.month, date.day)
        : DateTime(date.year, date.month, date.day);
    final endOfDay = date.isUtc
        ? DateTime.utc(date.year, date.month, date.day + 1)
        : DateTime(date.year, date.month, date.day + 1);

    final expanded = expandRecurringEvents(
      eventCandidates,
      before: startOfDay,
      after: endOfDay,
    );
    final todayEvents =
        expanded
            .where((e) => e.start.isBefore(endOfDay) && e.end.isAfter(startOfDay))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    final todayAllocations =
        allocations
            .where((item) => item.todo.status != 'COMPLETED')
            .toList()
          ..sort((a, b) => a.allocation.startAt.compareTo(b.allocation.startAt));

    final statesMap = <String, TaskInstanceState>{
      for (final s in instanceStates) '${s.todoSyncId}:${s.occurrenceId}': s,
    };

    final todayTaskInstances = <ProjectedTaskInstance>[];
    final missedTaskInstances = <ProjectedTaskInstance>[];
    final unconfirmedRecurringTodos = <Todo>[];
    final recurrenceExpansionErrors = <RecurringExpansionError>[];
    final earlierMissedSeries = <Todo>[];
    final earlierHistorySeries = <Todo>[];
    final completedTodayTaskInstances = <ProjectedTaskInstance>[];

    final thirtyDaysAgo = civilDateAddDays(startOfDay, -30);

    for (final todo in recurringTodos) {
      final TodoRecurrence recurrence;
      try {
        recurrence = TodoRecurrence.fromTodo(todo);
      } catch (err) {
        if (todo.recurrenceLegacyState == 'knownZoned') {
          recurrenceExpansionErrors.add(
            RecurringExpansionError(todo: todo, error: err),
          );
        } else {
          unconfirmedRecurringTodos.add(todo);
        }
        continue;
      }

      if (todo.rrule != null && todo.recurrenceLegacyState != 'knownZoned') {
        unconfirmedRecurringTodos.add(todo);
        continue;
      }
      if (recurrence.isUnknownLegacy) {
        unconfirmedRecurringTodos.add(todo);
        continue;
      }
      if (recurrence.spec == null) {
        if (todo.recurrenceLegacyState == 'knownZoned') {
          recurrenceExpansionErrors.add(
            RecurringExpansionError(
              todo: todo,
              error: const FormatException('knownZoned recurrence missing spec'),
            ),
          );
        }
        continue;
      }

      if (todo.syncId == null || todo.syncId!.isEmpty) {
        continue;
      }

      final TodoOccurrenceExpansion expansion;
      try {
        expansion = expandTodoOccurrences(
          todo,
          startInclusive: thirtyDaysAgo,
          endExclusive: endOfDay,
          maxOccurrences: 200,
        );
      } on RecurrenceRuleException catch (e) {
        if (e.kind == RecurrenceRuleErrorKind.unsupported) {
          unconfirmedRecurringTodos.add(todo);
        } else {
          recurrenceExpansionErrors.add(
            RecurringExpansionError(todo: todo, error: e),
          );
        }
        continue;
      } catch (e) {
        recurrenceExpansionErrors.add(
          RecurringExpansionError(todo: todo, error: e),
        );
        continue;
      }

      if (expansion.status != TodoOccurrenceExpansionStatus.expanded) {
        if (expansion.status ==
                TodoOccurrenceExpansionStatus.requiresLegacyConfirmation ||
            expansion.status == TodoOccurrenceExpansionStatus.unsupported) {
          unconfirmedRecurringTodos.add(todo);
        } else {
          recurrenceExpansionErrors.add(
            RecurringExpansionError(todo: todo, error: expansion.status.name),
          );
        }
        continue;
      }

      for (final occurrence in expansion.occurrences) {
        final state =
            statesMap['${occurrence.todoSyncId}:${occurrence.occurrenceId}'];
        final status = state?.status ?? 'pending';
        final instance = ProjectedTaskInstance(
          todo: todo,
          occurrence: occurrence,
          status: status,
          completedAt: state?.completedAt,
        );

        if (instance.isSkipped) continue;

        if (instance.isPending) {
          if (instance.isToday(startOfDay)) {
            todayTaskInstances.add(instance);
          } else if (instance.isMissedWithin30Days(startOfDay)) {
            missedTaskInstances.add(instance);
          }
        }
      }

      final spec = recurrence.spec!;
      final anchor = spec.anchor.value;
      final anchorDate = switch (anchor) {
        LocalDate d => startOfDay.isUtc
            ? DateTime.utc(d.year, d.month, d.day)
            : DateTime(d.year, d.month, d.day),
        LocalDateTime dt => startOfDay.isUtc
            ? DateTime.utc(
              dt.year,
              dt.month,
              dt.day,
              dt.hour,
              dt.minute,
              dt.second,
            )
            : DateTime(
              dt.year,
              dt.month,
              dt.day,
              dt.hour,
              dt.minute,
              dt.second,
            ),
      };

      if (anchorDate.isBefore(thirtyDaysAgo)) {
        var pageEnd = thirtyDaysAgo;
        var foundPendingEarlier = false;
        var exhaustedHistory = false;
        const probeMaxPages = 24;
        for (var p = 0; p < probeMaxPages; p++) {
          final pageStart = civilDateAddDays(pageEnd, -30);
          final effectiveStart =
              pageStart.isBefore(anchorDate) ? anchorDate : pageStart;
          try {
            final earlierExpansion = expandTodoOccurrences(
              todo,
              startInclusive: effectiveStart,
              endExclusive: pageEnd,
              maxOccurrences: 100,
            );
            if (earlierExpansion.status ==
                    TodoOccurrenceExpansionStatus.expanded &&
                earlierExpansion.occurrences.isNotEmpty) {
              final hasPending = earlierExpansion.occurrences.any((occ) {
                final st =
                    statesMap['${occ.todoSyncId}:${occ.occurrenceId}'];
                return st == null ||
                    (st.status != 'completed' && st.status != 'skipped');
              });
              if (hasPending) {
                foundPendingEarlier = true;
                break;
              }
            }
          } catch (_) {}
          if (!pageStart.isAfter(anchorDate)) {
            exhaustedHistory = true;
            break;
          }
          pageEnd = pageStart;
        }
        if (foundPendingEarlier) {
          earlierMissedSeries.add(todo);
        } else if (!exhaustedHistory) {
          earlierHistorySeries.add(todo);
        }
      }
    }

    final todosBySyncId = <String, Todo>{
      for (final t in allTodos)
        if (t.syncId != null && t.syncId!.isNotEmpty) t.syncId!: t,
    };

    // Ruling D: TaskInstances completed today belong in collapsed Completed today
    for (final state in instanceStates) {
      if (state.status == 'completed' &&
          state.completedAt != null &&
          !state.completedAt!.isBefore(startOfDay) &&
          state.completedAt!.isBefore(endOfDay)) {
        final parentTodo = todosBySyncId[state.todoSyncId];
        if (parentTodo != null && parentTodo.deletedAt == null) {
          final occurrence = resolveTodoOccurrence(
            parentTodo,
            state.occurrenceId,
          );
          if (occurrence != null) {
            completedTodayTaskInstances.add(
              ProjectedTaskInstance(
                todo: parentTodo,
                occurrence: occurrence,
                status: 'completed',
                completedAt: state.completedAt,
              ),
            );
          }
        }
      }
    }

    todayTaskInstances.sort(
      (a, b) => a.occurrence.nominalAnchor.canonical.compareTo(
        b.occurrence.nominalAnchor.canonical,
      ),
    );
    missedTaskInstances.sort(
      (a, b) => a.occurrence.nominalAnchor.canonical.compareTo(
        b.occurrence.nominalAnchor.canonical,
      ),
    );
    completedTodayTaskInstances.sort(
      (a, b) =>
          (b.completedAt ?? DateTime(0)).compareTo(a.completedAt ?? DateTime(0)),
    );

    return ActionProjectionData(
      events: todayEvents,
      allocations: todayAllocations,
      dueTodayTodos: dueTodayTodos,
      overdueTodos: overdueTodos,
      unplannedCount: unplannedCount,
      completedTodayTodos: completedTodayTodos,
      todayTaskInstances: todayTaskInstances,
      missedTaskInstances: missedTaskInstances,
      earlierMissedSeries: earlierMissedSeries,
      hasEarlierMissed: earlierMissedSeries.isNotEmpty,
      earlierHistorySeries: earlierHistorySeries,
      hasEarlierHistory: earlierHistorySeries.isNotEmpty,
      completedTodayTaskInstances: completedTodayTaskInstances,
      unconfirmedRecurringCount: unconfirmedRecurringTodos.length,
      unconfirmedRecurringTodos: unconfirmedRecurringTodos,
      recurrenceExpansionErrors: recurrenceExpansionErrors,
    );
  }

  /// Queries [AppDatabase] directly for all underlying records and returns
  /// the unified [ActionProjectionData] for [date].
  static Future<ActionProjectionData> fetch(
    AppDatabase db, {
    required DateTime date,
  }) async {
    final startOfDay = date.isUtc
        ? DateTime.utc(date.year, date.month, date.day)
        : DateTime(date.year, date.month, date.day);
    final endOfDay = date.isUtc
        ? DateTime.utc(date.year, date.month, date.day + 1)
        : DateTime(date.year, date.month, date.day + 1);

    final eventCandidates = await db.eventsDao.getEventCandidates(
      startOfDay,
      endOfDay,
    );
    final allocations = await fetchTaskAllocationsInDateRange(
      db,
      startOfDay,
      endOfDay,
    );

    final dueTodayTodos = await (db.select(db.todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                t.rrule.isNull() &
                t.recurrenceRule.isNull() &
                t.dueDate.isBiggerOrEqualValue(startOfDay) &
                t.dueDate.isSmallerThanValue(endOfDay),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.priority),
          ]))
        .get();

    final overdueTodos = await (db.select(db.todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                t.rrule.isNull() &
                t.recurrenceRule.isNull() &
                t.dueDate.isNotNull() &
                t.dueDate.isSmallerThanValue(startOfDay),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.dueDate),
            (t) => OrderingTerm.asc(t.priority),
          ]))
        .get();

    final unplannedRows = await (db.select(db.todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                t.rrule.isNull() &
                t.recurrenceRule.isNull() &
                t.dueDate.isNull(),
          ))
        .get();

    final completedTodayTodos = await (db.select(db.todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.equals('COMPLETED') &
                t.rrule.isNull() &
                t.recurrenceRule.isNull() &
                t.completedAt.isBiggerOrEqualValue(startOfDay) &
                t.completedAt.isSmallerThanValue(endOfDay),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
        .get();

    final recurringTodos = await (db.select(db.todos)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['COMPLETED', 'CANCELLED']) &
                (t.rrule.isNotNull() | t.recurrenceRule.isNotNull()),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();

    final allTodos = await (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull() & t.parentId.isNull()))
        .get();

    final instanceStates = await db.select(db.taskInstanceStates).get();

    return compute(
      date: date,
      eventCandidates: eventCandidates,
      allocations: allocations,
      dueTodayTodos: dueTodayTodos,
      overdueTodos: overdueTodos,
      unplannedCount: unplannedRows.length,
      completedTodayTodos: completedTodayTodos,
      recurringTodos: recurringTodos,
      allTodos: allTodos,
      instanceStates: instanceStates,
    );
  }
}
