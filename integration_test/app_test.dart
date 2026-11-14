import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/router/app_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/main.dart' show DaySparkApp;
import 'package:dayspark/ui/shell/spark_top_bar.dart';
import 'package:dayspark/ui/widgets/schedule/day_strip.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';

/// Real-app flows: the shipped [DaySparkApp], router, providers and database
/// run inside the native integration harness. Each test answers one question
/// and asserts the result the user can observe, not just that a widget exists.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedCalendar() =>
      db.into(db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));

  Future<int> seedTodo(int calendarId, String summary, {DateTime? dueDate}) =>
      db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: summary,
              dueDate: Value(dueDate),
            ),
          );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(800, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppRouter.router.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          homeWidgetAutoRefreshProvider.overrideWith((ref) {}),
          updateHomeWidgetProvider.overrideWith((ref) => () async {}),
        ],
        child: const DaySparkApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> openTasks(WidgetTester tester) async {
    final railEntry = find.byKey(const ValueKey('nav-todos'));
    if (railEntry.evaluate().isNotEmpty) {
      await tester.tap(railEntry);
      await settle(tester);
      return;
    }
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-tab-bar')),
        matching: find.text('Tasks'),
      ),
    );
    await settle(tester);
  }

  Future<void> showView(WidgetTester tester, String label) async {
    final switcher = find.byKey(const ValueKey('todos-view-switch'));
    expect(switcher, findsOneWidget);
    await tester.tap(find.descendant(of: switcher, matching: find.text(label)));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('flow: quick add writes an undated todo into the real list', (
    tester,
  ) async {
    await seedCalendar();
    expect(await db.select(db.todos).get(), isEmpty);

    await launch(tester);
    await openTasks(tester);
    // Inline capture belongs to Unplanned / All now; the by-date surface
    // captures through "arrange to <browseDate>".
    await showView(tester, 'Unplanned');

    final field = find.byKey(const ValueKey('todo-quick-add'));
    expect(field, findsOneWidget);
    expect(find.text('Book the flights'), findsNothing);

    await tester.enterText(field, 'Book the flights');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    final rows = await db.select(db.todos).get();
    expect(rows, hasLength(1));
    expect(rows.single.summary, 'Book the flights');
    expect(
      rows.single.dueDate,
      isNull,
      reason: 'a browsed day is capture context, never a deadline',
    );
    expect(find.text('Book the flights'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('flow: date browsing switches the list to another day', (
    tester,
  ) async {
    final calendarId = await seedCalendar();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final otherDay = DateTime(
      now.year,
      now.month,
      now.day + (today.weekday == 7 ? -1 : 1),
    );
    await seedTodo(calendarId, 'Today task', dueDate: today);
    await seedTodo(calendarId, 'Other day task', dueDate: otherDay);

    await launch(tester);
    await openTasks(tester);
    await showView(tester, 'By date');

    final weekStrip = find.byKey(const ValueKey('date-strip-week'));
    expect(weekStrip, findsOneWidget);
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Other day task'), findsNothing);

    await showView(tester, 'All Tasks');
    expect(weekStrip, findsNothing, reason: 'All is not attached to a day');
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Other day task'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(DateStrip), matching: find.text('Today')),
    );
    await settle(tester);
    expect(weekStrip, findsOneWidget, reason: 'Today restores the day view');
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Other day task'), findsNothing);

    await tester.tap(
      find.descendant(of: weekStrip, matching: find.text('${otherDay.day}')),
    );
    await settle(tester);

    expect(
      find.text('Other day task'),
      findsOneWidget,
      reason: 'the list follows the selected day',
    );
    expect(find.text('Today task'), findsNothing);

    await tester.tap(find.byKey(ValueKey(DayStrip.dayKey(today))));
    await settle(tester);
    expect(
      find.text('Today task'),
      findsOneWidget,
      reason: 'the strip still offers today after browsing away',
    );
    expect(find.text('Other day task'), findsNothing);

    await unmount(tester);
  });

  testWidgets('flow: wide desktop keeps the list beside the detail', (
    tester,
  ) async {
    final calendarId = await seedCalendar();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstId = await seedTodo(calendarId, 'First task', dueDate: today);
    final secondId = await seedTodo(calendarId, 'Second task', dueDate: today);

    await launch(tester, size: const Size(1440, 1000));

    await tester.tap(find.byKey(const ValueKey('nav-todos')));
    await settle(tester);
    await showView(tester, 'By date');

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(SparkTopBar))).width,
      1440,
      reason: 'the window really is as wide as the test asked for',
    );
    // The rows have no per-todo key of their own; the title is what the user
    // reads, so it is what the flow follows.
    final firstRow = find.widgetWithText(TodoListTile, 'First task');
    final secondRow = find.widgetWithText(TodoListTile, 'Second task');
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);

    await tester.tap(firstRow);
    await settle(tester);

    final firstPane = find.byKey(ValueKey('pane-todo-$firstId'));
    expect(firstPane, findsOneWidget);
    expect(
      tester.getTopLeft(firstPane).dx,
      greaterThan(tester.getTopLeft(firstRow).dx),
    );
    expect(
      find.descendant(of: firstPane, matching: find.text('First task')),
      findsOneWidget,
    );
    expect(firstRow, findsOneWidget, reason: 'the list stays beside detail');
    expect(secondRow, findsOneWidget);

    await tester.tap(secondRow);
    await settle(tester);

    expect(find.byKey(ValueKey('pane-todo-$firstId')), findsNothing);
    final secondPane = find.byKey(ValueKey('pane-todo-$secondId'));
    expect(secondPane, findsOneWidget);
    expect(
      find.descendant(of: secondPane, matching: find.text('Second task')),
      findsOneWidget,
    );
    expect(firstRow, findsOneWidget, reason: 'the list is still the same list');
    expect(secondRow, findsOneWidget);

    await unmount(tester);
  });
}
