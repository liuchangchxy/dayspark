import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage(initialTab: 2)),
    GoRoute(
      path: '/todo/detail',
      builder: (_, __) =>
          const Scaffold(body: Text('stub-detail', key: ValueKey('stub-detail'))),
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

Widget _app(AppDatabase db, GoRouter router) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 3; i++) {
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Task $i',
              dueDate: Value(today),
              sortOrder: Value(i),
            ),
          );
    }
    router = _router();
  });

  tearDown(() async {
    await db.close();
  });

  String paneTitle(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('todo-detail-title')))
      .controller!
      .text;

  testWidgets('a wide window shows details beside the list and swaps in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, router));
    await _settle(tester);

    expect(find.byKey(const ValueKey('todo-detail-title')), findsNothing);

    await tester.tap(find.text('Task 0'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('todo-detail-title')), findsOneWidget);
    expect(paneTitle(tester), 'Task 0');
    expect(
      find.byKey(const ValueKey('stub-detail')),
      findsNothing,
      reason: 'a wide window selects instead of navigating away',
    );
    // The list is still next to the detail.
    expect(find.text('Task 1'), findsOneWidget);

    await tester.tap(find.text('Task 1'));
    await _settle(tester);
    expect(paneTitle(tester), 'Task 1');
    expect(find.byKey(const ValueKey('stub-detail')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('a narrow window falls back to single-column navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, router));
    await _settle(tester);
    await tester.tap(find.text('Task 0'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('todo-detail-title')), findsOneWidget);

    tester.view.physicalSize = const Size(880, 1000);
    await tester.pump();
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('todo-detail-title')),
      findsNothing,
      reason: 'the split pane has no room anymore',
    );
    expect(
      MediaQuery.sizeOf(tester.element(find.text('Task 0'))).width,
      880,
    );

    await tester.tap(find.text('Task 0'));
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('stub-detail')),
      findsOneWidget,
      reason: 'narrow windows keep the existing route-based detail',
    );

    await _unmount(tester);
  });
}
