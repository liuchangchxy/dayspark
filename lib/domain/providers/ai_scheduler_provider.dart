import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/services/ai_scheduler_service.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';

final aiSchedulerServiceProvider = Provider<AiSchedulerService>((ref) {
  return AiSchedulerService();
});

final suggestTimeSlotsProvider =
    Provider<
      Future<List<Map<String, dynamic>>> Function({
        required String taskDescription,
        required DateTime rangeStart,
        required DateTime rangeEnd,
        Duration slotDuration,
      })
    >((ref) {
      return ({
        required taskDescription,
        required rangeStart,
        required rangeEnd,
        slotDuration = const Duration(hours: 1),
      }) async {
        final configAsync = ref.read(aiConfigProvider);
        final config = configAsync.value;

        // 1. Authoritative Event candidates (including long-running recurring master rows)
        final db = ref.read(databaseProvider);
        final events = await db.eventsDao.getEventCandidates(rangeStart, rangeEnd);
        final expandedEvents = expandRecurringEvents(
          events,
          before: rangeStart,
          after: rangeEnd,
        );

        // 2. Authoritative TaskAllocations in the target window
        final allocations = await fetchTaskAllocationsInDateRange(
          db,
          rangeStart,
          rangeEnd,
        );

        final service = ref.read(aiSchedulerServiceProvider);
        return service.suggestTimeSlots(
          config: config,
          events: expandedEvents,
          allocations: allocations,
          taskDescription: taskDescription,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          slotDuration: slotDuration,
        );
      };
    });

/// Computes authoritative fresh busy intervals in the given window:
/// expanded EventOccurrence + effective TaskAllocation
Future<List<({DateTime start, DateTime end})>> fetchAuthoritativeBusyIntervals(
  AppDatabase db,
  DateTime start,
  DateTime end,
) async {
  final events = await db.eventsDao.getEventCandidates(start, end);
  final expandedEvents = expandRecurringEvents(
    events,
    before: start,
    after: end,
  );
  final allocations = await fetchTaskAllocationsInDateRange(
    db,
    start,
    end,
  );
  return AiSchedulerService().computeBusyIntervals(
    events: expandedEvents,
    allocations: allocations,
  );
}

/// Validates whether [start, end] is free against fresh authoritative busy truth.
/// Re-reads both expanded EventOccurrences and effective TaskAllocations right before write.
final validateSlotAvailabilityProvider = Provider<
  Future<bool> Function({
    required DateTime start,
    required DateTime end,
  })
>((ref) {
  return ({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = ref.read(databaseProvider);
    final busy = await fetchAuthoritativeBusyIntervals(db, start, end);
    final service = ref.read(aiSchedulerServiceProvider);
    return service.isSlotFree(
      start: start,
      end: end,
      busyIntervals: busy,
    );
  };
});

final suggestTaskBreakdownProvider =
    Provider<Future<List<String>> Function(String taskDescription)>((ref) {
      return (String taskDescription) async {
        final configAsync = ref.read(aiConfigProvider);
        final config = configAsync.value;
        if (config == null) return [];

        final service = ref.read(aiSchedulerServiceProvider);
        return service.suggestTaskBreakdown(
          config: config,
          taskDescription: taskDescription,
        );
      };
    });
