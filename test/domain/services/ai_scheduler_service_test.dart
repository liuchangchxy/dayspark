import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/services/ai_scheduler_service.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';

void main() {
  late AiSchedulerService service;

  setUp(() {
    service = AiSchedulerService();
  });

  group('AiSchedulerService - Busy Intervals & Merging', () {
    test('merges overlapping events and task allocations into disjoint sorted intervals', () {
      final events = [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 1,
          title: 'Morning Meeting',
          start: DateTime(2026, 10, 20, 9, 0),
          end: DateTime(2026, 10, 20, 10, 0),
        ),
        CalendaEventAdapter(
          drifId: 2,
          calendarId: 1,
          title: 'Overlapping Event',
          start: DateTime(2026, 10, 20, 9, 30),
          end: DateTime(2026, 10, 20, 10, 30),
        ),
      ];

      final allocations = [
        TaskAllocationCalendarItem(
          allocation: TaskAllocation(
            id: 1,
            todoId: 10,
            startAt: DateTime(2026, 10, 20, 14, 0),
            endAt: DateTime(2026, 10, 20, 15, 30),
            state: 'active',
            serverRev: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          todo: Todo(
            id: 10,
            calendarId: 1,
            summary: 'Task 10',
            status: 'pending',
            priority: 0,
            recurrenceRevision: 0,
            percentComplete: 0,
            sortOrder: 0,
            serverRev: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
      ];

      final busy = service.computeBusyIntervals(
        events: events,
        allocations: allocations,
      );

      expect(busy, hasLength(2));
      // First interval: merged 09:00 - 10:30
      expect(busy[0].start, DateTime(2026, 10, 20, 9, 0));
      expect(busy[0].end, DateTime(2026, 10, 20, 10, 30));
      // Second interval: 14:00 - 15:30
      expect(busy[1].start, DateTime(2026, 10, 20, 14, 0));
      expect(busy[1].end, DateTime(2026, 10, 20, 15, 30));
    });
  });

  group('AiSchedulerService - Free Slots Computation', () {
    test('finds free slots respecting working hours and busy intervals', () {
      final busy = [
        (start: DateTime(2026, 10, 20, 9, 0), end: DateTime(2026, 10, 20, 11, 0)),
        (start: DateTime(2026, 10, 20, 12, 0), end: DateTime(2026, 10, 20, 13, 0)),
      ];

      final slots = service.computeFreeSlots(
        rangeStart: DateTime(2026, 10, 20, 9, 0),
        rangeEnd: DateTime(2026, 10, 20, 18, 0),
        busyIntervals: busy,
        slotDuration: const Duration(hours: 1),
        startHour: 9,
        endHour: 18,
      );

      expect(slots, isNotEmpty);
      // 11:00 - 12:00 is free
      expect(slots.any((s) => s.start == DateTime(2026, 10, 20, 11, 0) && s.end == DateTime(2026, 10, 20, 12, 0)), isTrue);
      // 09:00 - 11:00 is busy, so cannot be returned
      expect(slots.any((s) => s.start.isBefore(DateTime(2026, 10, 20, 11, 0))), isFalse);
    });

    test('isSlotFree returns false when slot overlaps busy interval', () {
      final busy = [
        (start: DateTime(2026, 10, 20, 14, 0), end: DateTime(2026, 10, 20, 15, 0)),
      ];

      expect(
        service.isSlotFree(
          start: DateTime(2026, 10, 20, 14, 30),
          end: DateTime(2026, 10, 20, 15, 30),
          busyIntervals: busy,
        ),
        isFalse,
      );
      expect(
        service.isSlotFree(
          start: DateTime(2026, 10, 20, 15, 0),
          end: DateTime(2026, 10, 20, 16, 0),
          busyIntervals: busy,
        ),
        isTrue,
      );
    });
    test('civil-day arithmetic iterates across multiple civil days without 24h duration drift', () {
      final slots = service.computeFreeSlots(
        rangeStart: DateTime.utc(2026, 10, 20, 9, 0),
        rangeEnd: DateTime.utc(2026, 10, 23, 18, 0),
        busyIntervals: [],
        slotDuration: const Duration(hours: 1),
        startHour: 9,
        endHour: 18,
        maxSlots: 50,
      );

      expect(slots, isNotEmpty);
      final daysCovered = slots.map((s) => s.start.day).toSet();
      // Must cover civil days 20, 21, 22, 23 exactly
      expect(daysCovered, containsAll([20, 21, 22, 23]));
      // Every slot start must be on the exact integer hour with 0 minutes
      for (final s in slots) {
        expect(s.start.minute, 0);
        expect(s.start.hour, greaterThanOrEqualTo(9));
        expect(s.end.hour, lessThanOrEqualTo(18));
      }
    });
  });

  group('AiSchedulerService - Hallucination Defense & Candidate Matching', () {
    final dummyConfig = AiConfig(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'test-key',
      model: 'gpt-4o',
    );

    test('suggestTimeSlots falls back to deterministic free slots without config', () async {
      final events = [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 1,
          title: 'Meeting',
          start: DateTime(2026, 10, 20, 9, 0),
          end: DateTime(2026, 10, 20, 12, 0),
        ),
      ];

      final suggestions = await service.suggestTimeSlots(
        config: null,
        events: events,
        allocations: [],
        taskDescription: 'Draft Proposal',
        rangeStart: DateTime(2026, 10, 20, 9, 0),
        rangeEnd: DateTime(2026, 10, 20, 18, 0),
        slotDuration: const Duration(hours: 1),
      );

      expect(suggestions, isNotEmpty);
      for (final s in suggestions) {
        final start = DateTime.parse(s['start'] as String);
        final end = DateTime.parse(s['end'] as String);
        // None of the suggestions overlap 09:00 - 12:00
        expect(start.isBefore(DateTime(2026, 10, 20, 12, 0)), isFalse);
        expect(end.isAfter(start), isTrue);
      }
    });

    test('discards LLM non-candidate slots (e.g. 03:00-04:00) even if free from busy', () async {
      final suggestions = await service.suggestTimeSlots(
        config: dummyConfig,
        events: [],
        allocations: [],
        taskDescription: 'Draft Proposal',
        rangeStart: DateTime.utc(2026, 10, 20, 9, 0),
        rangeEnd: DateTime.utc(2026, 10, 20, 18, 0),
        slotDuration: const Duration(hours: 1),
        maxSuggestions: 3,
        aiCaller: ({required config, required systemPrompt, required userPrompt}) async {
          // LLM hallucinates an early morning slot not in candidate list (03:00-04:00)
          return '[{"start":"2026-10-20T03:00:00.000Z","end":"2026-10-20T04:00:00.000Z","reason":"Early bird"}]';
        },
      );

      // The 03:00 slot must be discarded; fallback to valid candidate slots
      expect(suggestions, isNotEmpty);
      for (final s in suggestions) {
        final start = DateTime.parse(s['start'] as String);
        expect(start.hour, greaterThanOrEqualTo(9), reason: 'Must only return slots within candidate working hours');
      }
    });

    test('discards LLM slots with invalid duration or out of range', () async {
      final suggestions = await service.suggestTimeSlots(
        config: dummyConfig,
        events: [],
        allocations: [],
        taskDescription: 'Draft Proposal',
        rangeStart: DateTime.utc(2026, 10, 20, 9, 0),
        rangeEnd: DateTime.utc(2026, 10, 20, 18, 0),
        slotDuration: const Duration(hours: 1),
        maxSuggestions: 3,
        aiCaller: ({required config, required systemPrompt, required userPrompt}) async {
          // LLM hallucinates a 30-min slot and a slot tomorrow past rangeEnd
          return '[{"start":"2026-10-20T10:00:00.000Z","end":"2026-10-20T10:30:00.000Z","reason":"Quick slot"},'
              '{"start":"2026-10-25T10:00:00.000Z","end":"2026-10-25T11:00:00.000Z","reason":"Next week"}]';
        },
      );

      expect(suggestions, isNotEmpty);
      for (final s in suggestions) {
        final start = DateTime.parse(s['start'] as String);
        final end = DateTime.parse(s['end'] as String);
        expect(end.difference(start), const Duration(hours: 1));
        expect(start.day, 20);
      }
    });

    test('accepts valid candidate slot by numeric slot ID', () async {
      final suggestions = await service.suggestTimeSlots(
        config: dummyConfig,
        events: [],
        allocations: [],
        taskDescription: 'Draft Proposal',
        rangeStart: DateTime.utc(2026, 10, 20, 9, 0),
        rangeEnd: DateTime.utc(2026, 10, 20, 18, 0),
        slotDuration: const Duration(hours: 1),
        maxSuggestions: 2,
        aiCaller: ({required config, required systemPrompt, required userPrompt}) async {
          // LLM picks slot 2 (10:00-11:00) and slot 4 (12:00-13:00)
          return '[{"id": 2, "reason": "Slot 2 preferred"}, {"id": 4, "reason": "Lunch slot"}]';
        },
      );

      expect(suggestions, hasLength(2));
      expect(DateTime.parse(suggestions[0]['start'] as String), DateTime.utc(2026, 10, 20, 10, 0));
      expect(DateTime.parse(suggestions[1]['start'] as String), DateTime.utc(2026, 10, 20, 12, 0));
      expect(suggestions[0]['reason'], 'Slot 2 preferred');
    });

    test('retains long-running recurring events created >90 days ago in availability', () {
      // Event master was created 120 days ago (2026-06-22) with RRULE:FREQ=DAILY
      final oldMaster = Event(
        id: 99,
        calendarId: 1,
        summary: 'Daily Morning Standup',
        startDt: DateTime(2026, 6, 22, 9, 0),
        endDt: DateTime(2026, 6, 22, 9, 30),
        isAllDay: false,
        rrule: 'RRULE:FREQ=DAILY',
        serverRev: 0,
        createdAt: DateTime(2026, 6, 22),
        updatedAt: DateTime(2026, 6, 22),
      );

      final expanded = expandRecurringEvents(
        [oldMaster],
        before: DateTime(2026, 10, 20),
        after: DateTime(2026, 10, 21),
      );

      // Must produce an occurrence for 2026-10-20 at 09:00 - 09:30
      expect(
        expanded.any((e) => e.start == DateTime(2026, 10, 20, 9, 0) && e.end == DateTime(2026, 10, 20, 9, 30)),
        isTrue,
      );

      final busy = service.computeBusyIntervals(events: expanded, allocations: []);
      final slots = service.computeFreeSlots(
        rangeStart: DateTime(2026, 10, 20, 9, 0),
        rangeEnd: DateTime(2026, 10, 20, 18, 0),
        busyIntervals: busy,
        slotDuration: const Duration(hours: 1),
      );

      // Free slots must NOT overlap 09:00 - 09:30
      expect(slots.any((s) => s.start.isBefore(DateTime(2026, 10, 20, 9, 30))), isFalse);
    });
  });
}
