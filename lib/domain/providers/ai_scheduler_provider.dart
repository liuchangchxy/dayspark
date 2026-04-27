import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/services/ai_scheduler_service.dart';

final aiSchedulerServiceProvider = Provider<AiSchedulerService>((ref) {
  return AiSchedulerService();
});

final suggestTimeSlotsProvider =
    Provider<
      Future<List<Map<String, dynamic>>> Function({
        required String taskDescription,
        required DateTime rangeStart,
        required DateTime rangeEnd,
      })
    >((ref) {
      return ({
        required taskDescription,
        required rangeStart,
        required rangeEnd,
      }) async {
        final configAsync = ref.read(aiConfigProvider);
        final config = configAsync.value;
        if (config == null) return [];

        final events = await ref.read(
          eventsInDateRangeProvider(
            DateTimeRange(start: rangeStart, end: rangeEnd),
          ).future,
        );

        final service = ref.read(aiSchedulerServiceProvider);
        return service.suggestTimeSlots(
          config: config,
          existingEvents: events,
          taskDescription: taskDescription,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
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
