// 设置页「系统闹钟」闸门的 **native 侧回归**：开关只有 alarm 插件真的支持
// （Android / iOS）才出现。Windows 以前会显示一个翻转后无人读取的开关，
// 2026-10-24 起按「界面不得提供无效操作」移除；macOS 改由通知权限入口负责。
//
// 两条守卫都覆盖：①「系统闹钟」开关（SwitchListTile）②精确闹钟授权入口
// （CupertinoIcons.timer，仅 Android 且未授权时显示）。
// 未覆盖（据实披露）：web 上"不显示"那一半 —— `kIsWeb` 是编译期常量，VM 测试里恒为
// false，所以这里断言不到；那一半由 `platform_target.dart` 的同行守卫（静态）与
// web 冒烟截图（端到端）负责，不由本文件负责。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/alarm_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/settings/settings_sections/notifications_section.dart';

Future<void> _pumpNotificationsSection(
  WidgetTester tester,
  TargetPlatform platform, {
  bool? exactAlarmsAllowed,
  bool? initialAlarm,
  AlarmToggle? alarmToggle,
}) async {
  // binding 在测试体结束时就校验 debug 变量已复位（早于 tearDown），所以调用方
  // 必须在断言之后、测试体之内把它置回 null；这里的 addTearDown 只是断言失败时的兜底。
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);

  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        if (exactAlarmsAllowed != null)
          NotificationsSection.canScheduleExactProvider.overrideWith(
            (ref) async => exactAlarmsAllowed,
          ),
        if (initialAlarm != null)
          NotificationsSection.systemAlarmProvider.overrideWith(
            (ref) => initialAlarm,
          ),
        if (alarmToggle != null)
          alarmToggleProvider.overrideWithValue(alarmToggle),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: NotificationsSection()),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('$platform：系统闹钟开关出现（插件支持该平台）', (tester) async {
      await _pumpNotificationsSection(tester, platform);
      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'alarm 插件只在 Android / iOS 上真正排程',
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    testWidgets('$platform：不显示系统闹钟开关（无实现，不能提供无效操作）', (tester) async {
      await _pumpNotificationsSection(tester, platform);
      expect(find.byType(Switch), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('android：切换 OFF 时开关先响应，不等后台 stopAll 完成', (tester) async {
    final gate = Completer<void>();
    bool? toggled;
    await _pumpNotificationsSection(
      tester,
      TargetPlatform.android,
      initialAlarm: true,
      alarmToggle: (enabled) {
        toggled = enabled;
        // Deliberately never completes until after the assertions: the switch
        // must not wait for native cleanup.
        return gate.future;
      },
    );
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isTrue,
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(toggled, isFalse);
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isFalse,
      reason: '视觉状态必须在后台 stopAll 完成前改变',
    );
    debugDefaultTargetPlatformOverride = null;
    gate.complete();
  });

  testWidgets('macOS：提供通知权限入口（该平台确实会发提醒）', (tester) async {
    await _pumpNotificationsSection(tester, TargetPlatform.macOS);
    expect(find.text('Notification permission'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  // 守卫②：精确闹钟授权入口（`!kIsWeb && android && 未授权` 才显示）。它与守卫①
  // 用的是两套控件（ListTile + CupertinoIcons.timer），故必须分别断言。
  testWidgets('android 且未授权：精确闹钟入口出现', (tester) async {
    await _pumpNotificationsSection(
      tester,
      TargetPlatform.android,
      exactAlarmsAllowed: false,
    );
    await tester.pump();
    expect(find.text('Exact alarm permission'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('android 且已授权：精确闹钟入口不出现', (tester) async {
    await _pumpNotificationsSection(
      tester,
      TargetPlatform.android,
      exactAlarmsAllowed: true,
    );
    await tester.pump();
    expect(find.text('Exact alarm permission'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS 且未授权：精确闹钟入口也不出现（只有 Android 有）', (tester) async {
    await _pumpNotificationsSection(
      tester,
      TargetPlatform.macOS,
      exactAlarmsAllowed: false,
    );
    await tester.pump();
    expect(find.text('Exact alarm permission'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
