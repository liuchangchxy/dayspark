import 'package:calendar_todo_app/domain/providers/ai_provider.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

/// Uses AI to suggest optimal time slots for events and task scheduling.
class AiSchedulerService {
  Future<List<Map<String, dynamic>>> suggestTimeSlots({
    required AiConfig config,
    required List<Event> existingEvents,
    required String taskDescription,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxSuggestions = 3,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Find free time slots for: "$taskDescription"');
    buffer.writeln('Date range: ${rangeStart.toIso8601String()} to ${rangeEnd.toIso8601String()}');
    buffer.writeln('Today: ${DateTime.now().toIso8601String().substring(0, 10)}');
    buffer.writeln();
    buffer.writeln('Existing events in range:');

    if (existingEvents.isEmpty) {
      buffer.writeln('(none)');
    } else {
      for (final e in existingEvents) {
        buffer.writeln(
          '- ${e.summary}: ${e.startDt.toIso8601String()} to ${e.endDt.toIso8601String()}',
        );
      }
    }

    buffer.writeln();
    buffer.writeln('Return ONLY a JSON array of up to $maxSuggestions suggested time slots:');
    buffer.writeln('[{"start":"2026-04-20T10:00:00","end":"2026-04-20T11:00:00","reason":"free morning slot"}]');

    final response = await callAiApi(
      config: config,
      systemPrompt: 'You are a scheduling assistant. Suggest optimal time slots '
          'based on existing events. Respond in JSON only. Be concise.',
      userPrompt: buffer.toString(),
    );

    final arrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
    if (arrayMatch == null) return [];

    final list = RegExp(r'\{[^{}]*\}')
        .allMatches(arrayMatch.group(0)!)
        .map((m) => <String, dynamic>{
              'start': _extractJsonField(m.group(0)!, 'start'),
              'end': _extractJsonField(m.group(0)!, 'end'),
              'reason': _extractJsonField(m.group(0)!, 'reason'),
            })
        .toList();

    return list;
  }

  Future<List<String>> suggestTaskBreakdown({
    required AiConfig config,
    required String taskDescription,
  }) async {
    final response = await callAiApi(
      config: config,
      systemPrompt: 'Break down a task into actionable subtasks. '
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
