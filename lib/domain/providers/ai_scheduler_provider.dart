import 'package:flutter_riverpod/flutter_riverpod.dart';
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
