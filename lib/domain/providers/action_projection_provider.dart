import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';

class ActionProjectionData {
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<Todo> dueTodayTodos;
  final List<Todo> overdueTodos;
  final int unplannedCount;
  final List<Todo> completedTodayTodos;

  const ActionProjectionData({
    this.events = const [],
    this.allocations = const [],
    this.dueTodayTodos = const [],
    this.overdueTodos = const [],
    this.unplannedCount = 0,
    this.completedTodayTodos = const [],
  });

  bool get isEmpty =>
      events.isEmpty &&
      allocations.isEmpty &&
      dueTodayTodos.isEmpty &&
      overdueTodos.isEmpty &&
      unplannedCount == 0 &&
      completedTodayTodos.isEmpty;
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

      if (eventsAsync.isLoading ||
          allocationsAsync.isLoading ||
          dueTodayAsync.isLoading ||
          overdueAsync.isLoading ||
          unplannedAsync.isLoading ||
          completedAsync.isLoading) {
        return const AsyncValue.loading();
      }

      final firstError =
          eventsAsync.error ??
          allocationsAsync.error ??
          dueTodayAsync.error ??
          overdueAsync.error ??
          unplannedAsync.error ??
          completedAsync.error;
      if (firstError != null) {
        final st =
            eventsAsync.stackTrace ??
            allocationsAsync.stackTrace ??
            dueTodayAsync.stackTrace ??
            overdueAsync.stackTrace ??
            unplannedAsync.stackTrace ??
            completedAsync.stackTrace ??
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

      final allAllocations = allocationsAsync.valueOrNull ?? const [];
      final todayAllocations =
          allAllocations
              .where(
                (item) =>
                    item.allocation.occurrenceId == null &&
                    (item.todo.rrule == null || item.todo.rrule!.isEmpty) &&
                    item.todo.recurrenceRule == null &&
                    item.todo.status != 'COMPLETED',
              )
              .toList()
            ..sort(
              (a, b) => a.allocation.startAt.compareTo(b.allocation.startAt),
            );

      final dueToday = dueTodayAsync.valueOrNull ?? const [];
      final overdue = overdueAsync.valueOrNull ?? const [];
      final unplanned = unplannedAsync.valueOrNull ?? const [];
      final completed = completedAsync.valueOrNull ?? const [];

      return AsyncValue.data(
        ActionProjectionData(
          events: todayEvents,
          allocations: todayAllocations,
          dueTodayTodos: dueToday,
          overdueTodos: overdue,
          unplannedCount: unplanned.length,
          completedTodayTodos: completed,
        ),
      );
    });
