import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/services/action_projection_query.dart';

class RecurringExpansionError {
  final Todo todo;
  final Object error;

  const RecurringExpansionError({
    required this.todo,
    required this.error,
  });
}

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
  final List<Todo> earlierMissedSeries;
  final bool hasEarlierMissed;
  final List<Todo> earlierHistorySeries;
  final bool hasEarlierHistory;
  final List<ProjectedTaskInstance> completedTodayTaskInstances;
  final int unconfirmedRecurringCount;
  final List<Todo> unconfirmedRecurringTodos;
  final List<RecurringExpansionError> recurrenceExpansionErrors;

  const ActionProjectionData({
    this.events = const [],
    this.allocations = const [],
    this.dueTodayTodos = const [],
    this.overdueTodos = const [],
    this.unplannedCount = 0,
    this.completedTodayTodos = const [],
    this.todayTaskInstances = const [],
    this.missedTaskInstances = const [],
    this.earlierMissedSeries = const [],
    this.hasEarlierMissed = false,
    this.earlierHistorySeries = const [],
    this.hasEarlierHistory = false,
    this.completedTodayTaskInstances = const [],
    this.unconfirmedRecurringCount = 0,
    this.unconfirmedRecurringTodos = const [],
    this.recurrenceExpansionErrors = const [],
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
      earlierMissedSeries.isEmpty &&
      earlierHistorySeries.isEmpty &&
      completedTodayTaskInstances.isEmpty &&
      unconfirmedRecurringCount == 0 &&
      recurrenceExpansionErrors.isEmpty;
}

final actionDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final actionDueTodayTodosProvider = StreamProvider.autoDispose
    .family<List<Todo>, DateTime>((ref, date) {
      final db = ref.watch(databaseProvider);
      final start = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day);
      final end = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day + 1)
          : DateTime(date.year, date.month, date.day + 1);
      return db.todosDao.watchOrdinaryDueBetween(start, end);
    });

final actionOverdueTodosProvider = StreamProvider.autoDispose
    .family<List<Todo>, DateTime>((ref, date) {
      final db = ref.watch(databaseProvider);
      final start = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day);
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
      final start = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day);
      final end = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day + 1)
          : DateTime(date.year, date.month, date.day + 1);
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
      final startOfDay = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day);
      final endOfDay = date.isUtc
          ? DateTime.utc(date.year, date.month, date.day + 1)
          : DateTime(date.year, date.month, date.day + 1);
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

      return AsyncValue.data(
        ActionProjectionQuery.compute(
          date: date,
          eventCandidates: eventsAsync.valueOrNull ?? const [],
          allocations: allocationsAsync.valueOrNull ?? const [],
          dueTodayTodos: dueTodayAsync.valueOrNull ?? const [],
          overdueTodos: overdueAsync.valueOrNull ?? const [],
          unplannedCount: (unplannedAsync.valueOrNull ?? const []).length,
          completedTodayTodos: completedAsync.valueOrNull ?? const [],
          recurringTodos: recurringTodosAsync.valueOrNull ?? const [],
          allTodos: allTodosAsync.valueOrNull ?? const [],
          instanceStates: instanceStatesAsync.valueOrNull ?? const [],
        ),
      );
    });
