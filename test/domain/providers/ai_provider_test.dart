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

  // 出口清单 #7：AI 生成文本必须显式透传语言。这些断言就是那条的验收点——
  // 没有它们，"prompt 里有没有语言约束"只能靠读代码。
  group('系统提示词的语言约束', () {
    test('对话：硬约束对目标语言，而不是"跟用户同语言"这种启发式', () {
      final p = buildChatSystemPrompt('English');
      expect(p, contains('Respond strictly in English.'));
      expect(
        p,
        isNot(contains('same language as the user')),
        reason: '启发式已被替换，不能回流',
      );
    });

    test('对话：切到中文时约束跟着变', () {
      expect(
        buildChatSystemPrompt('Chinese (Simplified)'),
        contains('Respond strictly in Chinese (Simplified).'),
      );
    });

    test('解析器：透传语言，但明确要求不要翻译用户写的 summary', () {
      final p = buildParseSystemPrompt(
        type: 'todo',
        appLanguage: 'English',
        today: '2026-10-01',
      );
      expect(p, contains("The user's app language is English."));
      expect(
        p,
        contains('Keep "summary" in the language the user wrote in'),
        reason: '标题是用户自己的话，按 App 语言翻译它是错的',
      );
      expect(p, contains("Use today's date as reference: 2026-10-01."));
    });

    test('解析器：按 type 出对应的 JSON 形状（event 与 todo 不串）', () {
      final event = buildParseSystemPrompt(
        type: 'event',
        appLanguage: 'English',
        today: '2026-10-01',
      );
      final todo = buildParseSystemPrompt(
        type: 'todo',
        appLanguage: 'English',
        today: '2026-10-01',
      );
      expect(event, contains('"start":'));
      expect(event, isNot(contains('"due_date":')));
      expect(todo, contains('"due_date":'));
      expect(todo, isNot(contains('"start":')));
    });
  });
}
