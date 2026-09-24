import 'package:drift/drift.dart' show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/records/reminder_reconciler.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _ReminderReadCounter extends QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('"reminders"')) count++;
    return super.runSelect(executor, statement, args);
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage(initialTab: 1)),
    GoRoute(
      path: '/todo/edit',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
    GoRoute(
      path: '/tags',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
    GoRoute(
      path: '/trash',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      Reminder(
        id: 0,
        parentType: 'todo',
        parentId: 0,
        triggerTime: DateTime(2020),
        isTriggered: false,
      ),
    );
  });

  testWidgets('冷启动 / 恢复前台 / 午夜定时 各触发一次组件刷新', (tester) async {
    SharedPreferences.setMockInitialValues({appLocalePrefKey: 'en'});
    final reads = _ReminderReadCounter();
    final db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(reads));
    addTearDown(db.close);

    final notif = _MockNotificationService();
    when(() => notif.cancel(any())).thenAnswer((_) async {});
    when(
      () => notif.scheduleFromReminder(
        any(),
        eventReminderTitle: any(named: 'eventReminderTitle'),
        todoReminderTitle: any(named: 'todoReminderTitle'),
        eventReminderBody: any(named: 'eventReminderBody'),
        todoReminderBody: any(named: 'todoReminderBody'),
      ),
    ).thenAnswer((_) async {});
    final reconciler = ReminderReconciler(db: db, notifications: notif);

    var refreshes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          updateHomeWidgetProvider.overrideWithValue(() async {
            refreshes++;
          }),
          reminderReconcilerProvider.overrideWithValue(reconciler),
        ],
        child: MaterialApp.router(
          routerConfig: _router(),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    await _settle(tester);

    expect(refreshes, 1, reason: '冷启动快照走同一个刷新入口');

    // resumed 只在状态真的变化时才派发：先 inactive 再 resumed。
    final readsBeforeResume = reads.count;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    expect(refreshes, 2, reason: 'resumed → 一次组件刷新');
    expect(
      reads.count,
      greaterThan(readsBeforeResume),
      reason: 'resumed → 也做一次提醒全量重算（跨进程写的兜底）',
    );

    // 推进到第一次午夜触发为止：定时器每次都用「真实现在 → 午夜」重算延迟
    // （DateTime.now() 不随测试假时钟前进），所以一次 25h 的大步 pump 会连发
    // 多次；按真实延迟精确推进时，下一次重排落在 2×延迟 之后，恰好只触发一次。
    final nowBefore = DateTime.now();
    await tester.pump(
      DateTime(
        nowBefore.year,
        nowBefore.month,
        nowBefore.day + 1,
      ).difference(nowBefore),
    );
    await _settle(tester);

    expect(refreshes, 3, reason: '午夜定时 → 一次组件刷新');

    await _unmount(tester);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}
