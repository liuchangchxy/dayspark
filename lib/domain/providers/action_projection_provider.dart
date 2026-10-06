import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

class ActionProjectionData {
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<Todo> dueTodayTodos;
  final List<Todo> overdueTodos;
  final int unplannedCount;
  final List<Todo> completedTodayTodos;

  // Phase 2 additions:
  final List<ProjectedTaskInstance> todayTaskInstances;
  final List<ProjectedTaskInstance> missedTaskInstances;
  final bool hasEarlierMissed;
  final List<ProjectedTaskInstance> completedTodayTaskInstances;
  final int unconfirmedRecurringCount;
  final List<Todo> unconfirmedRecurringTodos;

  const ActionProjectionData({
    this.events = const [],
    this.allocations = const [],
    this.dueTodayTodos = const [],
    this.overdueTodos = const [],
    this.unplannedCount = 0,
    this.completedTodayTodos = const [],
    this.todayTaskInstances = const [],
    this.missedTaskInstances = const [],
    this.hasEarlierMissed = false,
    this.completedTodayTaskInstances = const [],
    this.unconfirmedRecurringCount = 0,
    this.unconfirmedRecurringTodos = const [],
  });

  bool get isEmpty =>
      events.isEmpty &&
      allocations.isEmpty &&
      dueTodayTodos.isEmpty &&
      overdueTodos.isEmpty &&
      unplannedCount == 0 &&
      completedTodayTodos.isEmpty &&
      todayTaskInstances.isEmpty &&
      missedTaskInstances.isEmpty &&
      completedTodayTaskInstances.isEmpty &&
      unconfirmedRecurringCount == 0;
}

final actionDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final actionDueTodayTodosProvider = StreamProvider.autoDispose
    .family<List<Todo>, DateTime>((ref, date) {
      final db = ref.watch(databaseProvider);
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      return db.todosDao.watchOrdinaryDueBetween(start, end);
    });

final actionOverdueTodosProvider = StreamProvider.autoDispose
    .family<List<Todo>, DateTime>((ref, date) {
      final db = ref.watch(databaseProvider);
      final start = DateTime(date.year, date.month, date.day);
      return db.todosDao.watchOrdinaryOverdue(start);
    });

final actionUnplannedTodosProvider = StreamProvider.autoDispose<List<Todo>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.todosDao.watchOrdinaryUnplanned();
});

final actionCompletedTodayTodosProvider = StreamProvider.autoDispose
    .family<List<Todo>, DateTime>((ref, date) {
      final db = ref.watch(databaseProvider);
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      return db.todosDao.watchOrdinaryCompletedOn(start, end);
    });

final actionActiveRecurringTodosProvider =
    StreamProvider.autoDispose<List<Todo>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.todosDao.watchActiveRecurring();
    });

final actionAllNotDeletedTodosProvider =
    StreamProvider.autoDispose<List<Todo>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.todosDao.watchAllNotDeleted();
    });

final actionTaskInstanceStatesProvider =
    StreamProvider.autoDispose<List<TaskInstanceState>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.select(db.taskInstanceStates).watch();
    });

final actionProjectionProvider =
    Provider.autoDispose<AsyncValue<ActionProjectionData>>((ref) {
      final date = ref.watch(actionDateProvider);
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final rangeKey =
          '${startOfDay.millisecondsSinceEpoch}-${endOfDay.millisecondsSinceEpoch}';

      final eventsAsync = ref.watch(
        eventCandidatesInDateRangeProvider(rangeKey),
      );
      final allocationsAsync = ref.watch(
        taskAllocationsInDateRangeProvider(rangeKey),
      );
      final dueTodayAsync = ref.watch(actionDueTodayTodosProvider(startOfDay));
      final overdueAsync = ref.watch(actionOverdueTodosProvider(startOfDay));
      final unplannedAsync = ref.watch(actionUnplannedTodosProvider);
      final completedAsync = ref.watch(
        actionCompletedTodayTodosProvider(startOfDay),
      );
      final recurringTodosAsync = ref.watch(actionActiveRecurringTodosProvider);
      final allTodosAsync = ref.watch(actionAllNotDeletedTodosProvider);
      final instanceStatesAsync = ref.watch(actionTaskInstanceStatesProvider);

      if (eventsAsync.isLoading ||
          allocationsAsync.isLoading ||
          dueTodayAsync.isLoading ||
          overdueAsync.isLoading ||
          unplannedAsync.isLoading ||
          completedAsync.isLoading ||
          recurringTodosAsync.isLoading ||
          allTodosAsync.isLoading ||
          instanceStatesAsync.isLoading) {
        return const AsyncValue.loading();
      }

      final firstError =
          eventsAsync.error ??
          allocationsAsync.error ??
          dueTodayAsync.error ??
          overdueAsync.error ??
          unplannedAsync.error ??
          completedAsync.error ??
          recurringTodosAsync.error ??
          allTodosAsync.error ??
          instanceStatesAsync.error;
      if (firstError != null) {
        final st =
            eventsAsync.stackTrace ??
            allocationsAsync.stackTrace ??
            dueTodayAsync.stackTrace ??
            overdueAsync.stackTrace ??
            unplannedAsync.stackTrace ??
            completedAsync.stackTrace ??
            recurringTodosAsync.stackTrace ??
            allTodosAsync.stackTrace ??
            instanceStatesAsync.stackTrace ??
            StackTrace.current;
        return AsyncValue.error(firstError, st);
      }

      final events = eventsAsync.valueOrNull ?? const [];
      final expanded = expandRecurringEvents(
        events,
        before: startOfDay,
        after: endOfDay,
      );
      final todayEvents =
          expanded
              .where(
                (e) => e.start.isBefore(endOfDay) && e.end.isAfter(startOfDay),
              )
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));

      // Phase 2: Timeline allocations include both ordinary and recurring allocations.
      final allAllocations = allocationsAsync.valueOrNull ?? const [];
      final todayAllocations =
          allAllocations
              .where((item) => item.todo.status != 'COMPLETED')
              .toList()
            ..sort(
              (a, b) => a.allocation.startAt.compareTo(b.allocation.startAt),
            );

      final dueToday = dueTodayAsync.valueOrNull ?? const [];
      final overdue = overdueAsync.valueOrNull ?? const [];
      final unplanned = unplannedAsync.valueOrNull ?? const [];
      final completed = completedAsync.valueOrNull ?? const [];

      // Phase 2 Recurring TaskInstance projections
      final recurringTodos = recurringTodosAsync.valueOrNull ?? const [];
      final allTodos = allTodosAsync.valueOrNull ?? const [];
      final allStates = instanceStatesAsync.valueOrNull ?? const [];

      final statesMap = <String, TaskInstanceState>{
        for (final s in allStates) '${s.todoSyncId}:${s.occurrenceId}': s,
      };
      final todosBySyncId = <String, Todo>{
        for (final t in allTodos)
          if (t.syncId != null && t.syncId!.isNotEmpty) t.syncId!: t,
      };

      final todayTaskInstances = <ProjectedTaskInstance>[];
      final missedTaskInstances = <ProjectedTaskInstance>[];
      final unconfirmedRecurringTodos = <Todo>[];
      var hasEarlierMissed = false;

      final thirtyDaysAgo = startOfDay.subtract(const Duration(days: 30));

      for (final todo in recurringTodos) {
        // Ruling C: unknownLegacy / unsupported recurrence discovery without guessed instances.
        final TodoRecurrence recurrence;
        try {
          recurrence = TodoRecurrence.fromTodo(todo);
        } catch (_) {
          unconfirmedRecurringTodos.add(todo);
          continue;
        }

        if (todo.rrule != null && todo.recurrenceLegacyState != 'knownZoned') {
          unconfirmedRecurringTodos.add(todo);
          continue;
        }
        if (recurrence.isUnknownLegacy || recurrence.spec == null) {
          unconfirmedRecurringTodos.add(todo);
          continue;
        }

        if (todo.syncId == null || todo.syncId!.isEmpty) {
          continue;
        }

        // Expand occurrences in [thirtyDaysAgo, endOfDay)
        final TodoOccurrenceExpansion expansion;
        try {
          expansion = expandTodoOccurrences(
            todo,
            startInclusive: thirtyDaysAgo,
            endExclusive: endOfDay,
            maxOccurrences: 200,
          );
        } catch (_) {
          // Surfaced explicitly, never silently truncated.
          unconfirmedRecurringTodos.add(todo);
          continue;
        }

        if (expansion.status != TodoOccurrenceExpansionStatus.expanded) {
          unconfirmedRecurringTodos.add(todo);
          continue;
        }

        for (final occurrence in expansion.occurrences) {
          final state = statesMap['${occurrence.todoSyncId}:${occurrence.occurrenceId}'];
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

        // Check if there are earlier occurrences before the 30-day window
        if (!hasEarlierMissed) {
          final anchor = todo.startDate ?? todo.dueDate;
          if (anchor != null && anchor.isBefore(thirtyDaysAgo)) {
            hasEarlierMissed = true;
          }
        }
      }

      // Ruling D: TaskInstances completed today belong in collapsed Completed today
      final completedTodayTaskInstances = <ProjectedTaskInstance>[];
      for (final state in allStates) {
        if (state.status == 'completed' &&
            state.completedAt != null &&
            !state.completedAt!.isBefore(startOfDay) &&
            state.completedAt!.isBefore(endOfDay)) {
          final parentTodo = todosBySyncId[state.todoSyncId];
          if (parentTodo != null && parentTodo.deletedAt == null) {
            try {
              final parsed = OccurrenceId.parse(state.occurrenceId);
              final occurrence = TodoOccurrence(
                todoSyncId: state.todoSyncId,
                occurrenceId: state.occurrenceId,
                nominalAnchor: parsed.nominal,
                resolvedStartInstant: state.completedAt,
                timeZone: parsed.timeZone?.id ?? 'UTC',
              );
              completedTodayTaskInstances.add(
                ProjectedTaskInstance(
                  todo: parentTodo,
                  occurrence: occurrence,
                  status: 'completed',
                  completedAt: state.completedAt,
                ),
              );
            } catch (_) {
              // Ignore unparseable legacy occurrence states.
            }
          }
        }
      }

      // Sort items
      todayTaskInstances.sort((a, b) => a.occurrence.nominalAnchor.canonical.compareTo(b.occurrence.nominalAnchor.canonical));
      missedTaskInstances.sort((a, b) => a.occurrence.nominalAnchor.canonical.compareTo(b.occurrence.nominalAnchor.canonical));
      completedTodayTaskInstances.sort((a, b) => (b.completedAt ?? DateTime(0)).compareTo(a.completedAt ?? DateTime(0)));

      return AsyncValue.data(
        ActionProjectionData(
          events: todayEvents,
          allocations: todayAllocations,
          dueTodayTodos: dueToday,
          overdueTodos: overdue,
          unplannedCount: unplanned.length,
          completedTodayTodos: completed,
          todayTaskInstances: todayTaskInstances,
          missedTaskInstances: missedTaskInstances,
          hasEarlierMissed: hasEarlierMissed,
          completedTodayTaskInstances: completedTodayTaskInstances,
          unconfirmedRecurringCount: unconfirmedRecurringTodos.length,
          unconfirmedRecurringTodos: unconfirmedRecurringTodos,
        ),
      );
    });
