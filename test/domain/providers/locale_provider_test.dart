// 「当前生效语言」的解析与语言名映射。
//
// 这两件事是「文案烘焙进系统的出口」的共同前置：通知排期时用它决定文案，
// AI prompt 用它声明回答语言。所以它自己的正确性要有测试钉住。
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  group('LocaleNotifier 不再重复写 state', () {
    ProviderContainer containerWith(Map<String, Object> prefs) {
      SharedPreferences.setMockInitialValues(prefs);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('只创建容器就会装载持久化语言，不依赖调用方手动 load', () async {
      final container = containerWith({appLocalePrefKey: 'zh'});

      container.read(localeProvider);
      await pumpEventQueue();

      expect(container.read(localeProvider), const Locale('zh'));
    });

    test('固定中文：重复 load 只通知一次，之后不再通知', () async {
      final container = containerWith({appLocalePrefKey: 'zh'});
      var notifications = 0;
      container.listen<Locale?>(localeProvider, (_, __) => notifications++);

      final notifier = container.read(localeProvider.notifier);
      await notifier.load();
      await notifier.load();
      await notifier.load();

      expect(container.read(localeProvider), const Locale('zh'));
      expect(notifications, 1);
    });

    test('固定英文：重复 load 只通知一次', () async {
      final container = containerWith({appLocalePrefKey: 'en'});
      var notifications = 0;
      container.listen<Locale?>(localeProvider, (_, __) => notifications++);

      final notifier = container.read(localeProvider.notifier);
      await notifier.load();
      await notifier.load();

      expect(container.read(localeProvider), const Locale('en'));
      expect(notifications, 1);
    });

    test('跟随系统：没有持久化值时 load 不写 state、不通知', () async {
      final container = containerWith({});
      var notifications = 0;
      container.listen<Locale?>(localeProvider, (_, __) => notifications++);

      final notifier = container.read(localeProvider.notifier);
      await notifier.load();
      await notifier.load();

      expect(container.read(localeProvider), isNull);
      expect(notifications, 0);
    });

    test('中文 → 英文 → 跟随系统：每次真实切换都生效且只通知一次', () async {
      final container = containerWith({appLocalePrefKey: 'zh'});
      var notifications = 0;
      container.listen<Locale?>(localeProvider, (_, __) => notifications++);

      final notifier = container.read(localeProvider.notifier);
      await notifier.load();
      expect(container.read(localeProvider), const Locale('zh'));
      expect(notifications, 1);

      await notifier.setLocale(const Locale('en'));
      expect(container.read(localeProvider), const Locale('en'));
      expect(notifications, 2);

      await notifier.setLocale(null);
      expect(container.read(localeProvider), isNull);
      expect(notifications, 3);

      await notifier.load();
      expect(container.read(localeProvider), isNull);
      expect(notifications, 3);
    });

    test('把同一个 Locale 值再赋一次不通知', () async {
      final container = containerWith({appLocalePrefKey: 'zh'});
      var notifications = 0;
      container.listen<Locale?>(localeProvider, (_, __) => notifications++);

      final notifier = container.read(localeProvider.notifier);
      await notifier.load();
      notifier.state = const Locale('zh');
      notifier.state = const Locale('zh');

      expect(notifications, 1);
    });
  });
}
