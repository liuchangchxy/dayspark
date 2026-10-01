// 「当前生效语言」的解析与语言名映射。
//
// 这两件事是「文案烘焙进系统的出口」的共同前置：通知排期时用它决定文案，
// AI prompt 用它声明回答语言。所以它自己的正确性要有测试钉住。
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('languageNameFor', () {
    test('中文与英文给全名，模型才稳', () {
      expect(languageNameFor(const Locale('zh')), 'Chinese (Simplified)');
      expect(languageNameFor(const Locale('en')), 'English');
    });

    test('未登记的语言回落到 languageCode，而不是空串', () {
      expect(languageNameFor(const Locale('ja')), 'ja');
    });
  });

  group('resolveAppLocale 的优先级：显式传入 → 持久化 → 系统', () {
    test('显式传入最优先，压过持久化值', () async {
      SharedPreferences.setMockInitialValues({appLocalePrefKey: 'zh'});
      expect(
        await resolveAppLocale(override: const Locale('en')),
        const Locale('en'),
      );
    });

    test('无显式传入时取持久化的 app locale', () async {
      SharedPreferences.setMockInitialValues({appLocalePrefKey: 'zh'});
      expect((await resolveAppLocale()).languageCode, 'zh');
    });

    test('持久化为空时回落到系统语言（而不是硬编码某一种）', () async {
      SharedPreferences.setMockInitialValues({});
      final resolved = await resolveAppLocale();
      expect(
        resolved,
        TestWidgetsFlutterBinding.instance.platformDispatcher.locale,
      );
    });
  });
}
