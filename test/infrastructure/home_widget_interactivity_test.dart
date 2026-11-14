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
    expect(quickAddLocation, '/quick-add');
    expect(
      widgetDeepLinkLocation(
        Uri.parse('dayspark://quick-add?date=2026-11-07'),
      ),
      '/quick-add?date=2026-11-07',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://quick-add?date=bad')),
      '/quick-add',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark:///quick-add')),
      quickAddLocation,
    );
    expect(widgetDeepLinkLocation(Uri.parse('dayspark://other')), isNull);
    expect(widgetDeepLinkLocation(Uri.parse('https://quick-add')), isNull);
    expect(widgetDeepLinkLocation(Uri.parse('')), isNull);
    expect(widgetDeepLinkLocation(null), isNull);
  });

  test('open deep links resolve to real app routes', () {
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/today')),
      todayLocation,
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/action')),
      '/?tab=0',
    );
    expect(widgetDeepLinkLocation(Uri.parse('dayspark://open/home')), '/');
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/calendar')),
      calendarLocation,
    );
    expect(
      widgetDeepLinkLocation(
        Uri.parse('dayspark://open/calendar?date=2026-11-07'),
      ),
      '$calendarLocation&date=2026-11-07',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/calendar?date=bad')),
      calendarLocation,
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/todo?id=42')),
      '/todo/detail?id=42',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/todo?id=0')),
      '/?tab=2',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/todos?view=inbox')),
      '/?tab=2&view=inbox',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/todos?view=all')),
      '/?tab=2&view=all',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/todos?view=today')),
      '/?tab=2&view=today',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/todos?view=bad')),
      '/?tab=2&view=today',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/event?id=7')),
      '/event/detail?id=7',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/event?id=x')),
      '/?tab=1',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/new-todo')),
      quickAddLocation,
    );
    expect(
      widgetDeepLinkLocation(
        Uri.parse('dayspark://open/new-event?date=2026-11-07'),
      ),
      '/event/new?date=2026-11-07',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/new-event')),
      '/event/new',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('dayspark://open/unknown')),
      isNull,
    );
  });

  test('Android cold-start path-only routes resolve too', () {
    expect(widgetDeepLinkLocation(Uri.parse('/today')), todayLocation);
    expect(widgetDeepLinkLocation(Uri.parse('/action')), '/?tab=0');
    expect(widgetDeepLinkLocation(Uri.parse('/home')), '/');
    expect(
      widgetDeepLinkLocation(Uri.parse('/calendar?date=2026-11-07')),
      '$calendarLocation&date=2026-11-07',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('/todo?id=42')),
      '/todo/detail?id=42',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('/event?id=7')),
      '/event/detail?id=7',
    );
    expect(widgetDeepLinkLocation(Uri.parse('/new-todo')), quickAddLocation);
    expect(widgetDeepLinkLocation(Uri.parse('/quick-add')), quickAddLocation);
    expect(
      widgetDeepLinkLocation(Uri.parse('/quick-add?date=2026-11-07')),
      '/quick-add?date=2026-11-07',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('/todos?view=inbox')),
      '/?tab=2&view=inbox',
    );
    expect(
      widgetDeepLinkLocation(Uri.parse('/new-event?date=2026-11-07')),
      '/event/new?date=2026-11-07',
    );
    expect(widgetDeepLinkLocation(Uri.parse('/')), isNull);
    expect(widgetDeepLinkLocation(Uri.parse('/settings')), isNull);
    expect(
      widgetDeepLinkLocation(Uri.parse('https://example.com/todo?id=1')),
      isNull,
    );
  });

  testWidgets('quick-add location resolves to the minimal capture page', (
    tester,
  ) async {
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);

    AppRouter.router.go(quickAddLocation);
    await settle(tester);

    expect(find.byType(QuickAddPage), findsOneWidget);

    // A widget date is capture context only; the page renders the same either
    // way and never turns it into a deadline.
    AppRouter.router.go('$quickAddLocation?date=2026-11-07');
    await settle(tester);
    expect(find.byType(QuickAddPage), findsOneWidget);

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

    expect(find.byType(QuickAddPage), findsOneWidget);

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

    expect(find.byType(QuickAddPage), findsNothing);
    expect(await testDb.select(testDb.todos).get(), isEmpty);
    expect(await testDb.select(testDb.syncOutbox).get(), isEmpty);

    await teardownTree(tester);
  });
}
