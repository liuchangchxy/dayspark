import 'package:flutter/foundation.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';

/// Uses deterministic availability computation and optional AI ranking
/// to suggest optimal time slots for task scheduling.
class AiSchedulerService {
  /// Computes merged disjoint busy intervals from expanded events and active task allocations.
  List<({DateTime start, DateTime end})> computeBusyIntervals({
    required List<CalendaEventAdapter> events,
    required List<TaskAllocationCalendarItem> allocations,
  }) {
    final raw = <({DateTime start, DateTime end})>[];

    for (final event in events) {
      if (event.end.isAfter(event.start)) {
        raw.add((start: event.start, end: event.end));
      }
    }

    for (final item in allocations) {
      final alloc = item.allocation;
      if (alloc.endAt.isAfter(alloc.startAt)) {
        raw.add((start: alloc.startAt, end: alloc.endAt));
      }
    }

    raw.sort((a, b) => a.start.compareTo(b.start));

    final merged = <({DateTime start, DateTime end})>[];
    for (final interval in raw) {
      if (merged.isEmpty) {
        merged.add(interval);
      } else {
        final last = merged.last;
        if (!interval.start.isAfter(last.end)) {
          final newEnd =
              interval.end.isAfter(last.end) ? interval.end : last.end;
          merged[merged.length - 1] = (start: last.start, end: newEnd);
        } else {
          merged.add(interval);
        }
      }
    }

    return merged;
  }

  /// Finds deterministic candidate free slots within working hours (default 09:00 - 18:00)
  /// that do not intersect any busy intervals.
  List<({DateTime start, DateTime end})> computeFreeSlots({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required List<({DateTime start, DateTime end})> busyIntervals,
    Duration slotDuration = const Duration(hours: 1),
    int startHour = 9,
    int endHour = 18,
    int maxSlots = 10,
  }) {
    final results = <({DateTime start, DateTime end})>[];
    if (!rangeEnd.isAfter(rangeStart) || maxSlots <= 0) return results;

    var dayCursor = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final lastDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    while (!dayCursor.isAfter(lastDay) && results.length < maxSlots) {
      final workStart = DateTime(
        dayCursor.year,
        dayCursor.month,
        dayCursor.day,
        startHour,
      );
      final workEnd = DateTime(
        dayCursor.year,
        dayCursor.month,
        dayCursor.day,
        endHour,
      );

      final windowStart = workStart.isBefore(rangeStart) ? rangeStart : workStart;
      final windowEnd = workEnd.isAfter(rangeEnd) ? rangeEnd : workEnd;

      if (windowEnd.isAfter(windowStart)) {
        var cursor = windowStart;

        for (final interval in busyIntervals) {
          if (results.length >= maxSlots) break;
          if (!interval.end.isAfter(windowStart) ||
              !interval.start.isBefore(windowEnd)) {
            continue;
          }

          if (interval.start.isAfter(cursor)) {
            final gapEnd =
                interval.start.isBefore(windowEnd) ? interval.start : windowEnd;
            while (gapEnd.difference(cursor) >= slotDuration &&
                results.length < maxSlots) {
              results.add((start: cursor, end: cursor.add(slotDuration)));
              cursor = cursor.add(slotDuration);
            }
          }

          if (interval.end.isAfter(cursor)) {
            cursor = interval.end;
          }
          if (!cursor.isBefore(windowEnd)) break;
        }

        while (windowEnd.difference(cursor) >= slotDuration &&
            results.length < maxSlots) {
          results.add((start: cursor, end: cursor.add(slotDuration)));
          cursor = cursor.add(slotDuration);
        }
      }

      dayCursor = dayCursor.add(const Duration(days: 1));
    }

    return results;
  }

  /// Deterministic validator: returns true if [start, end] is completely free of conflicts.
  bool isSlotFree({
    required DateTime start,
    required DateTime end,
    required List<({DateTime start, DateTime end})> busyIntervals,
  }) {
    if (!end.isAfter(start)) return false;
    for (final busy in busyIntervals) {
      if (start.isBefore(busy.end) && end.isAfter(busy.start)) {
        return false;
      }
    }
    return true;
  }

  /// Suggests optimal time slots based on deterministic free slots and optional LLM ranking.
  /// The LLM is never the truth engine for availability; all returned slots are verified.
  Future<List<Map<String, dynamic>>> suggestTimeSlots({
    required AiConfig? config,
    required List<CalendaEventAdapter> events,
    required List<TaskAllocationCalendarItem> allocations,
    required String taskDescription,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    Duration slotDuration = const Duration(hours: 1),
    int maxSuggestions = 3,
  }) async {
    final busy = computeBusyIntervals(
      events: events,
      allocations: allocations,
    );

    final candidateSlots = computeFreeSlots(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      busyIntervals: busy,
      slotDuration: slotDuration,
      maxSlots: 10,
    );

    if (candidateSlots.isEmpty) return [];

    if (config == null) {
      return candidateSlots.take(maxSuggestions).map((slot) {
        return <String, dynamic>{
          'start': slot.start.toIso8601String(),
          'end': slot.end.toIso8601String(),
          'reason': 'Available free slot',
        };
      }).toList();
    }

    try {
      final buffer = StringBuffer();
      buffer.writeln('Task to schedule: "$taskDescription"');
      buffer.writeln('Task duration: ${slotDuration.inMinutes} minutes');
      buffer.writeln('Authoritative available candidate free slots:');
      for (var i = 0; i < candidateSlots.length; i++) {
        final slot = candidateSlots[i];
        buffer.writeln(
          'Slot ${i + 1}: ${slot.start.toIso8601String()} to ${slot.end.toIso8601String()}',
        );
      }
      buffer.writeln();
      buffer.writeln(
        'Choose up to $maxSuggestions best time slots from the candidates above. '
        'You MUST ONLY pick from the candidate slots provided. Do not hallucinate or create conflicting slots. '
        'Return ONLY a JSON array in the format: [{"start":"...","end":"...","reason":"..."}]',
      );

      final response = await callAiApi(
        config: config,
        systemPrompt:
            'You are a scheduling assistant. Recommend up to $maxSuggestions time slots '
            'strictly chosen from the provided candidate free slots. Respond in JSON only.',
        userPrompt: buffer.toString(),
      );

      final arrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
      if (arrayMatch != null) {
        final matches = RegExp(r'\{[^{}]*\}').allMatches(arrayMatch.group(0)!);
        final validated = <Map<String, dynamic>>[];

        for (final m in matches) {
          final startStr = _extractJsonField(m.group(0)!, 'start');
          final endStr = _extractJsonField(m.group(0)!, 'end');
          final reason = _extractJsonField(m.group(0)!, 'reason');

          final start = DateTime.tryParse(startStr);
          final end = DateTime.tryParse(endStr);

          if (start != null && end != null) {
            // Strict deterministic validation
            if (isSlotFree(start: start, end: end, busyIntervals: busy)) {
              validated.add({
                'start': start.toIso8601String(),
                'end': end.toIso8601String(),
                'reason': reason.isNotEmpty ? reason : 'Optimal recommended slot',
              });
              if (validated.length >= maxSuggestions) break;
            } else {
              debugPrint('ai_scheduler: Discarding hallucinated/conflicting slot: $start - $end');
            }
          }
        }

        if (validated.isNotEmpty) {
          return validated;
        }
      }
    } catch (e) {
      debugPrint('ai_scheduler: LLM call error: $e');
    }

    // Fallback to deterministic slots on LLM error, empty response, or all-hallucinated response
    return candidateSlots.take(maxSuggestions).map((slot) {
      return <String, dynamic>{
        'start': slot.start.toIso8601String(),
        'end': slot.end.toIso8601String(),
        'reason': 'Available free slot',
      };
    }).toList();
  }

  Future<List<String>> suggestTaskBreakdown({
    required AiConfig config,
    required String taskDescription,
  }) async {
    final response = await callAiApi(
      config: config,
      systemPrompt:
          'Break down a task into actionable subtasks. '
          'Return ONLY a JSON array of strings. Be concise. '
          'Respond in the same language as the user.',
      userPrompt: 'Break down: "$taskDescription"',
    );

    final arrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
    if (arrayMatch == null) return [];

    return RegExp(r'"([^"]*)"')
        .allMatches(arrayMatch.group(0)!)
        .map((m) => m.group(1)!)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _extractJsonField(String json, String field) {
    final match = RegExp('"$field"\\s*:\\s*"([^"]*)"').firstMatch(json);
    return match?.group(1) ?? '';
  }
}
