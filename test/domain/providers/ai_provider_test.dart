import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';

void main() {
  group('AiConfig', () {
    test('creates with required fields', () {
      final config = AiConfig(
        apiKey: 'sk-test',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
      );
      expect(config.apiKey, 'sk-test');
      expect(config.baseUrl, 'https://api.openai.com/v1');
      expect(config.model, 'gpt-4o-mini');
    });
  });

  group('AiChatMessage', () {
    test('creates user message', () {
      final msg = AiChatMessage(role: 'user', content: 'hello');
      expect(msg.role, 'user');
      expect(msg.content, 'hello');
    });

    test('creates assistant message', () {
      final msg = AiChatMessage(role: 'assistant', content: 'hi there');
      expect(msg.role, 'assistant');
      expect(msg.content, 'hi there');
    });
  });
}
