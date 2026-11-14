import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/router/app_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/quick_add_page.dart';

import '../helpers/test_database.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase testDb;

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    testDb = createTestDatabase();
  });

  tearDown(() async {
    await testDb.close();
  });

  Widget buildApp({List<Override> overrides = const []}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(testDb),
      notificationServiceProvider.overrideWithValue(_MockNotificationService()),
      ...overrides,
    ],
    child: MaterialApp.router(
      routerConfig: AppRouter.router,
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<int> seedCalendar() {
    return testDb
        .into(testDb.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  }

  testWidgets('saves today task and closes', (tester) async {
    await seedCalendar();
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);

    AppRouter.router.go('/quick-add?date=2026-11-07');
    await settle(tester);
    expect(find.byType(QuickAddPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.byType(QuickAddPage), findsNothing);
    final rows = await testDb.select(testDb.todos).get();
    expect(rows.length, 1);
    expect(rows.single.summary, 'Buy milk');
    expect(rows.single.dueDate, DateTime(2026, 11, 7));
    expect(rows.single.status, 'NEEDS-ACTION');
    expect(rows.single.priority, 0);

    await teardownTree(tester);
  });

  testWidgets('inbox source leaves the task undated', (tester) async {
    await seedCalendar();
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);

    AppRouter.router.go('/quick-add');
    await settle(tester);
    expect(find.byType(QuickAddPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Inbox task');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final rows = await testDb.select(testDb.todos).get();
    expect(rows.length, 1);
    expect(rows.single.summary, 'Inbox task');
    expect(rows.single.dueDate, isNull);

    await teardownTree(tester);
  });

  testWidgets('failure keeps the text and shows an error', (tester) async {
    AppRouter.router.go('/');
    await tester.pumpWidget(
      buildApp(
        overrides: [
          calendarsProvider.overrideWith(
            (ref) => Stream.value(const <Calendar>[]),
          ),
        ],
      ),
    );
    await settle(tester);

    AppRouter.router.go('/quick-add');
    await settle(tester);
    expect(find.byType(QuickAddPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'No calendar task');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.byType(QuickAddPage), findsOneWidget);
    expect(find.text('No calendar task'), findsOneWidget);
    expect(find.text('Save failed. Please try again.'), findsOneWidget);
    expect(await testDb.select(testDb.todos).get(), isEmpty);

    await teardownTree(tester);
  });
}
