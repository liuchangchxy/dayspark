import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/router/app_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/home_widget_interactivity.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_create_page.dart';

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

  Widget buildApp() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(testDb),
      notificationServiceProvider.overrideWithValue(_MockNotificationService()),
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
    // Avoid pumpAndSettle: Drift broadcast streams never complete.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Unmount the tree inside the test body so the drift query-stream close
  // timers (scheduled on ProviderScope dispose) elapse before the binding
  // verifies that no timers are pending — otherwise teardown leaves a
  // zero-duration timer behind and the test fails on an invariant. A zero
  // pump does not advance the fake clock, so elapse 1ms.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  test('dayspark://quick-add translates to the quick-add location', () {
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://quick-add')),
      quickAddLocation,
    );
    expect(quickAddLocation, '/todo/new?source=widget');
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark:///quick-add')),
      quickAddLocation,
    );
    expect(widgetDeepLinkLocation(Uri.parse('dayspark://other')), isNull);
    expect(widgetDeepLinkLocation(Uri.parse('https://quick-add')), isNull);
    expect(widgetDeepLinkLocation(Uri.parse('')), isNull);
    expect(widgetDeepLinkLocation(null), isNull);
  });

  testWidgets('quick-add location resolves to TodoCreatePage with source', (
    tester,
  ) async {
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);

    AppRouter.router.go(quickAddLocation);
    await settle(tester);

    final page = tester.widget<TodoCreatePage>(find.byType(TodoCreatePage));
    expect(page.source, 'widget');

    await teardownTree(tester);
  });

  testWidgets('interactivity callback navigates only — enqueues nothing', (
    tester,
  ) async {
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);

    await widgetInteractivityCallback(Uri.parse('dayspark://quick-add'));
    await settle(tester);

    final page = tester.widget<TodoCreatePage>(find.byType(TodoCreatePage));
    expect(page.source, 'widget');

    expect(await testDb.select(testDb.todos).get(), isEmpty);
    expect(await testDb.select(testDb.syncOutbox).get(), isEmpty);

    await teardownTree(tester);
  });

  testWidgets('interactivity callback ignores unknown URIs', (tester) async {
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);

    await widgetInteractivityCallback(Uri.parse('dayspark://boom'));
    await settle(tester);

    expect(find.byType(TodoCreatePage), findsNothing);
    expect(await testDb.select(testDb.todos).get(), isEmpty);
    expect(await testDb.select(testDb.syncOutbox).get(), isEmpty);

    await teardownTree(tester);
  });
}
