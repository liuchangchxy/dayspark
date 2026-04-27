import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _keyAiApiKey = 'ai_api_key';
const _keyAiBaseUrl = 'ai_base_url';
const _keyAiModel = 'ai_model';

/// AI configuration state.
class AiConfig {
  final String apiKey;
  final String baseUrl;
  final String model;

  AiConfig({required this.apiKey, required this.baseUrl, required this.model});
}

/// Current AI config (read from secure storage).
final aiConfigProvider = FutureProvider<AiConfig?>((ref) async {
  const storage = FlutterSecureStorage();
  final apiKey = await storage.read(key: _keyAiApiKey);
  final baseUrl = await storage.read(key: _keyAiBaseUrl);
  final model = await storage.read(key: _keyAiModel);

  if (apiKey == null) return null;
  return AiConfig(
    apiKey: apiKey,
    baseUrl: baseUrl ?? 'https://api.openai.com/v1',
    model: model ?? 'gpt-4o-mini',
  );
});

/// Whether AI is configured.
final isAiConfiguredProvider = FutureProvider<bool>((ref) async {
  final config = ref.watch(aiConfigProvider).value;
  return config != null;
});

/// Save AI configuration.
final saveAiConfigProvider =
    Provider<
      Future<void> Function({
        required String apiKey,
        required String baseUrl,
        required String model,
      })
    >((ref) {
      return ({required apiKey, required baseUrl, required model}) async {
        const storage = FlutterSecureStorage();
        await storage.write(key: _keyAiApiKey, value: apiKey);
        await storage.write(key: _keyAiBaseUrl, value: baseUrl);
        await storage.write(key: _keyAiModel, value: model);
        ref.invalidate(aiConfigProvider);
      };
    });

/// Delete AI configuration.
final deleteAiConfigProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: _keyAiApiKey);
    await storage.delete(key: _keyAiBaseUrl);
    await storage.delete(key: _keyAiModel);
    ref.invalidate(aiConfigProvider);
  };
});

/// Call AI API with a prompt, returns the response text.
Future<String> callAiApi({
  required AiConfig config,
  required String systemPrompt,
  required String userPrompt,
}) async {
  final dio = Dio();
  final response = await dio.post<void>(
    '${config.baseUrl}/chat/completions',
    options: Options(
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
    ),
    data: jsonEncode({
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.3,
    }),
  );

  final data = response.data as Map<String, dynamic>;
  final choices = data['choices'] as List;
  if (choices.isEmpty) throw Exception('No response from AI');
  final message = choices[0]['message'] as Map<String, dynamic>;
  return message['content'] as String;
}

/// Parse natural language into structured event/todo data.
Future<Map<String, dynamic>> parseNaturalLanguage({
  required AiConfig config,
  required String input,
  required String type, // 'event' or 'todo'
}) async {
  final systemPrompt =
      '''You are a calendar and todo parser. Parse the user's natural language input into structured data.
Return ONLY valid JSON with these fields:
${type == 'event' ? '''{
  "summary": "event title",
  "start": "2026-05-01T10:00:00",
  "end": "2026-05-01T11:00:00",
  "description": "optional description",
  "location": "optional location",
  "is_all_day": false
}''' : '''{
  "summary": "todo title",
  "due_date": "2026-05-15",
  "priority": 5,
  "description": "optional description"
}'''}

Use today's date as reference: ${DateTime.now().toIso8601String().substring(0, 10)}.
If a date/time is ambiguous, make a reasonable guess. Priority: 1=high, 5=medium, 9=low, 0=none.''';

  final result = await callAiApi(
    config: config,
    systemPrompt: systemPrompt,
    userPrompt: input,
  );

  // Extract JSON from response (may be wrapped in markdown code block)
  final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(result);
  if (jsonMatch == null) throw FormatException('No JSON found in AI response');

  return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
}

/// AI chat message.
class AiChatMessage {
  final String role;
  final String content;
  AiChatMessage({required this.role, required this.content});
}

/// Send a chat message to AI and get response.
final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, List<AiChatMessage>>((ref) {
      return AiChatNotifier(ref);
    });

class AiChatNotifier extends StateNotifier<List<AiChatMessage>> {
  final Ref _ref;

  AiChatNotifier(this._ref) : super([]);

  Future<void> sendMessage(String message) async {
    final config = _ref.read(aiConfigProvider).value;
    if (config == null) return;

    state = [...state, AiChatMessage(role: 'user', content: message)];
    state = [...state, AiChatMessage(role: 'assistant', content: '...')];

    try {
      final systemPrompt =
          'You are a helpful calendar and todo assistant. '
          'Help the user manage their schedule. Be concise. Respond in the same language as the user.';
      final response = await callAiApi(
        config: config,
        systemPrompt: systemPrompt,
        userPrompt: message,
      );

      state = [
        ...state.sublist(0, state.length - 1),
        AiChatMessage(role: 'assistant', content: response),
      ];
    } catch (e) {
      state = [
        ...state.sublist(0, state.length - 1),
        AiChatMessage(role: 'assistant', content: 'Error: $e'),
      ];
    }
  }

  void clear() => state = [];
}
