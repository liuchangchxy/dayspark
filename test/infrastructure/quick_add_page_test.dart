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

  testWidgets('saves the task and closes', (tester) async {
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
    // The deep link's date is the context the composer was opened from, not
    // a deadline: nothing is written until the user sets one.
    expect(rows.single.dueDate, isNull);
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

  testWidgets('parsed date is labelled as the task deadline', (tester) async {
    await seedCalendar();
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);
    AppRouter.router.go('/quick-add');
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Buy milk 2026-11-07');
    await settle(tester);
    expect(find.textContaining('Due date:'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final todo = (await testDb.select(testDb.todos).get()).single;
    expect(todo.dueDate, DateTime(2026, 11, 7));
    await teardownTree(tester);
  });

  testWidgets('timed input defaults to task, shows suggestion, and writes plan allocation when accepted', (tester) async {
    await seedCalendar();
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);
    AppRouter.router.go('/quick-add');
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Meeting 2026-11-07 10:00');
    await settle(tester);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('No due date'), findsOneWidget);
    expect(find.textContaining('10:00–11:00 · Suggested Plan'), findsOneWidget);
    expect(find.textContaining('Preselected; saved as "Planned execution"'), findsOneWidget);

    final removeSize = tester.getSize(find.widgetWithText(TextButton, 'Remove'));
    expect(removeSize.width, greaterThanOrEqualTo(48));
    expect(removeSize.height, greaterThanOrEqualTo(48));
    final changeSize = tester.getSize(find.widgetWithText(TextButton, 'Change to Event'));
    expect(changeSize.width, greaterThanOrEqualTo(48));
    expect(changeSize.height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Save'));
    await settle(tester);

    final todo = (await testDb.select(testDb.todos).get()).single;
    expect(todo.summary, 'Meeting');
    expect(todo.dueDate, isNull);

    final allocations = await testDb.select(testDb.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.todoId, todo.id);
    expect(allocations.single.startAt.toLocal(), DateTime(2026, 11, 7, 10));
    expect(allocations.single.endAt.toLocal(), DateTime(2026, 11, 7, 11));

    expect(await testDb.select(testDb.reminders).get(), isEmpty);
    expect(await testDb.select(testDb.events).get(), isEmpty);
    await teardownTree(tester);
  });

  testWidgets('removing suggestion does not write plan allocation and clears due date on card and db', (tester) async {
    await seedCalendar();
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);
    AppRouter.router.go('/quick-add');
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Meeting 2026-11-07 10:00');
    await settle(tester);

    // Remove suggestion
    await tester.tap(find.text('Remove'));
    await settle(tester);

    expect(find.text('Time suggestion removed'), findsOneWidget);
    expect(find.text('Saves title only; no date, no plan, no deadline.'), findsOneWidget);
    // Fidelity requirement: card must NOT show "Due date" when suggestion is removed, and must show "No due date"
    expect(find.textContaining('Due date:'), findsNothing);
    expect(find.text('No due date'), findsOneWidget);

    final restoreSize = tester.getSize(find.widgetWithText(TextButton, 'Restore'));
    expect(restoreSize.width, greaterThanOrEqualTo(48));
    expect(restoreSize.height, greaterThanOrEqualTo(48));

    // Save
    await tester.tap(find.text('Save'));
    await settle(tester);

    final todo = (await testDb.select(testDb.todos).get()).single;
    expect(todo.summary, 'Meeting');
    expect(todo.dueDate, isNull);

    // No allocation written when suggestion removed
    expect(await testDb.select(testDb.taskAllocations).get(), isEmpty);
    expect(await testDb.select(testDb.events).get(), isEmpty);
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

  testWidgets('parsed time defaults to todo and only converts to event when explicitly requested', (tester) async {
    await seedCalendar();
    AppRouter.router.go('/');
    await tester.pumpWidget(buildApp());
    await settle(tester);
    AppRouter.router.go('/quick-add');
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Report 2026-11-07 15:00');
    await settle(tester);

    // Tapping Save defaults to saving as Todo, NOT Event!
    await tester.tap(find.text('Save'));
    await settle(tester);

    final todos = await testDb.select(testDb.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Report');
    expect(await testDb.select(testDb.events).get(), isEmpty);

    // Now open again and explicitly switch to Event
    AppRouter.router.go('/quick-add');
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Interview 2026-11-07 16:00');
    await settle(tester);

    // Tap "Change to event"
    await tester.tap(find.text('Change to Event'));
    await settle(tester);

    expect(find.textContaining('16:00–17:00 · Event Schedule'), findsOneWidget);
    expect(find.text('Changed to Event; saved directly to calendar.'), findsOneWidget);
    expect(find.text('Change to Task'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);

    final toTaskBtn = tester.getSize(find.widgetWithText(TextButton, 'Change to Task'));
    expect(toTaskBtn.width, greaterThanOrEqualTo(48));
    expect(toTaskBtn.height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Save'));
    await settle(tester);

    final events = await testDb.select(testDb.events).get();
    expect(events, hasLength(1));
    expect(events.single.summary, 'Interview');

    await teardownTree(tester);
  });
}
