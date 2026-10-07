import 'package:flutter/foundation.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';

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

    var dayCursor = rangeStart.isUtc
        ? DateTime.utc(rangeStart.year, rangeStart.month, rangeStart.day)
        : DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final lastDay = rangeEnd.isUtc
        ? DateTime.utc(rangeEnd.year, rangeEnd.month, rangeEnd.day)
        : DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    while (!dayCursor.isAfter(lastDay) && results.length < maxSlots) {
      final workStart = dayCursor.isUtc
          ? DateTime.utc(
              dayCursor.year,
              dayCursor.month,
              dayCursor.day,
              startHour,
            )
          : DateTime(
              dayCursor.year,
              dayCursor.month,
              dayCursor.day,
              startHour,
            );
      final workEnd = dayCursor.isUtc
          ? DateTime.utc(
              dayCursor.year,
              dayCursor.month,
              dayCursor.day,
              endHour,
            )
          : DateTime(
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

      dayCursor = civilDateAddDays(dayCursor, 1);
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
    Future<String> Function({
      required AiConfig config,
      required String systemPrompt,
      required String userPrompt,
    })? aiCaller,
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
        'You MUST ONLY pick from the candidate slot IDs provided. '
        'Return ONLY a JSON array in the format: [{"id": 1, "reason": "..."}] '
        'where "id" is the numeric Slot ID (1 to ${candidateSlots.length}).',
      );

      final caller = aiCaller ?? callAiApi;
      final response = await caller(
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
        final pickedIndices = <int>{};

        for (final m in matches) {
          final itemJson = m.group(0)!;
          final reason = _extractJsonField(itemJson, 'reason');

          ({DateTime start, DateTime end})? matchedCandidate;
          int? matchedIndex;

          final idVal = _extractJsonField(itemJson, 'id');
          final idInt = int.tryParse(idVal);
          if (idInt != null && idInt >= 1 && idInt <= candidateSlots.length) {
            matchedIndex = idInt - 1;
            matchedCandidate = candidateSlots[matchedIndex];
          } else {
            // Fallback: exact membership match against candidateSlots
            final startStr = _extractJsonField(itemJson, 'start');
            final endStr = _extractJsonField(itemJson, 'end');
            final start = DateTime.tryParse(startStr);
            final end = DateTime.tryParse(endStr);
            if (start != null && end != null) {
              for (var i = 0; i < candidateSlots.length; i++) {
                final cand = candidateSlots[i];
                if (cand.start.isAtSameMomentAs(start) &&
                    cand.end.isAtSameMomentAs(end)) {
                  matchedIndex = i;
                  matchedCandidate = cand;
                  break;
                }
              }
            }
          }

          if (matchedCandidate == null || matchedIndex == null) {
            // Non-candidate: hallucinated interval, different duration, or outside range. Discard!
            debugPrint('ai_scheduler: Discarding non-candidate slot from LLM: $itemJson');
            continue;
          }

          if (pickedIndices.contains(matchedIndex)) {
            continue;
          }

          // Strict deterministic validation that the candidate slot is still free
          if (isSlotFree(
            start: matchedCandidate.start,
            end: matchedCandidate.end,
            busyIntervals: busy,
          )) {
            pickedIndices.add(matchedIndex);
            validated.add({
              'start': matchedCandidate.start.toIso8601String(),
              'end': matchedCandidate.end.toIso8601String(),
              'reason': reason.isNotEmpty ? reason : 'Optimal recommended slot',
            });
            if (validated.length >= maxSuggestions) break;
          } else {
            debugPrint('ai_scheduler: Discarding candidate slot that is now busy: $matchedCandidate');
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
    final strMatch = RegExp('"$field"\\s*:\\s*"([^"]*)"').firstMatch(json);
    if (strMatch != null) return strMatch.group(1)!;
    final numMatch = RegExp('"$field"\\s*:\\s*(\\d+)').firstMatch(json);
    if (numMatch != null) return numMatch.group(1)!;
    return '';
  }
}
