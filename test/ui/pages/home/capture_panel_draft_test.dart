import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';

Widget _app(AppDatabase db) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      actionDateProvider.overrideWith((ref) => DateTime(2026, 10, 6)),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: A2TodayPage(
          now: DateTime(2026, 10, 6, 15),
          onOpenTodo: (_) {},
          onOpenEvent: (_) {},
          onToggleTodo: (_, __, ___) async => true,
          onOpenUnplanned: () {},
          onScheduleTodo: (_) {},
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Finder _inPanel(String text) {
  return find.descendant(
    of: find.byType(A2CapturePanel),
    matching: find.text(text),
  );
}

Future<void> _openPanel(WidgetTester tester, String title) async {
  await tester.enterText(
    find.byKey(const ValueKey('desktop-capture-input')),
    title,
  );
  await tester.tap(find.byKey(const ValueKey('desktop-capture-expand-btn')));
  await _settle(tester);
  expect(find.byType(A2CapturePanel), findsOneWidget);
}

Future<void> _submitPanel(WidgetTester tester) async {
  await tester.tap(_inPanel('Save task'));
  await _settle(tester);
}

DateTime _tomorrow() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('choosing Tomorrow then submit writes dueDate', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'Bare plan');
    await tester.tap(_inPanel('Deadline'));
    await _settle(tester);
    await tester.tap(_inPanel('Tomorrow'));
    await _settle(tester);
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.dueDate, _tomorrow());

    await _unmount(tester);
  });

  testWidgets('choosing a calendar writes that calendarId', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final homeId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Home',
            color: const Value('#E39A3B'),
          ),
        );

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'Home task');
    await tester.tap(_inPanel('Calendar'));
    await _settle(tester);
    await tester.tap(_inPanel('Home'));
    await _settle(tester);
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.calendarId, homeId);

    await _unmount(tester);
  });

  testWidgets('choosing a reminder writes a reminder row', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'Remember me');
    await tester.tap(_inPanel('Deadline'));
    await _settle(tester);
    await tester.tap(_inPanel('Tomorrow'));
    await _settle(tester);
    await tester.tap(_inPanel('Reminder'));
    await _settle(tester);
    await tester.tap(_inPanel('15 minutes before'));
    await _settle(tester);
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    final reminder = (await db.select(db.reminders).get()).single;
    expect(reminder.parentType, 'todo');
    expect(reminder.parentId, todo.id);
    expect(
      reminder.triggerTime,
      todo.dueDate!.subtract(const Duration(minutes: 15)),
    );

    await _unmount(tester);
  });

  testWidgets('choosing a plan writes an allocation', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'Plan the work');
    await tester.tap(_inPanel('Planned execution'));
    await _settle(tester);
    await tester.tap(_inPanel('Apply'));
    await _settle(tester);
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    final allocation = (await db.select(db.taskAllocations).get()).single;
    final start = allocation.startAt.toLocal();
    final end = allocation.endAt.toLocal();
    final now = DateTime.now();
    expect(allocation.todoId, todo.id);
    expect(start.year, now.year);
    expect(start.month, now.month);
    expect(start.day, now.day);
    expect(start.hour, 15);
    expect(start.minute, 15);
    expect(end.hour, 16);
    expect(end.minute, 0);

    await _unmount(tester);
  });

  testWidgets('cancelling the plan leaves no allocation', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'No plan here');
    await tester.tap(_inPanel('Planned execution'));
    await _settle(tester);
    await tester.tap(_inPanel('Cancel'));
    await _settle(tester);
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.id, isPositive);
    expect(await db.select(db.taskAllocations).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets(
    'parsed capture on Today writes its plan in one tap instead of re-parsing',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(db));
      await _settle(tester);

      // "明天下午三点交报告": the panel shows a preselected plan; its primary
      // must write it, not bounce back into the same parsed panel.
      await _openPanel(tester, '明天下午三点交报告');
      expect(find.byType(A2CapturePanel), findsOneWidget);
      expect(_inPanel('Save task'), findsOneWidget);
      await tester.tap(_inPanel('Save task'));
      await _settle(tester);

      final todo = (await db.select(db.todos).get()).single;
      expect(todo.summary, '交报告');
      expect(todo.dueDate, isNull, reason: 'a time suggestion is not a deadline');
      final allocation = (await db.select(db.taskAllocations).get()).single;
      expect(allocation.todoId, todo.id);
      expect(find.byType(A2CapturePanel), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'event capture on Today writes an event with the chosen repeat',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(db));
      await _settle(tester);

      await _openPanel(tester, '明天下午三点和设计团队评审方案');
      await tester.tap(_inPanel('Change to Event'));
      await _settle(tester);
      expect(_inPanel('New Event'), findsOneWidget);

      await tester.tap(_inPanel('Repeat'));
      await _settle(tester);
      await tester.tap(_inPanel('Repeat'));
      await _settle(tester);
      expect(_inPanel('Every week'), findsOneWidget);

      await tester.tap(_inPanel('Create Event'));
      await _settle(tester);

      final event = (await db.select(db.events).get()).single;
      expect(event.summary, '和设计团队评审方案');
      expect(event.rrule, 'FREQ=WEEKLY');
      expect(await db.select(db.todos).get(), isEmpty);
      expect(find.byType(A2CapturePanel), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets('plan-only capture anchors a reminder to the plan start', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'Plan without due');
    await tester.tap(_inPanel('Planned execution'));
    await _settle(tester);
    await tester.tap(_inPanel('Apply'));
    await _settle(tester);
    await tester.tap(_inPanel('Reminder'));
    await _settle(tester);
    await tester.tap(_inPanel('15 minutes before'));
    await _settle(tester);
    expect(
      find.text(
        'Set a deadline or start time first, then reminders can be relative to it.',
      ),
      findsNothing,
    );
    await _submitPanel(tester);

    expect(await db.select(db.taskAllocations).get(), hasLength(1));
    final allocation = (await db.select(db.taskAllocations).get()).single;
    final reminder = (await db.select(db.reminders).get()).single;
    expect(reminder.parentType, 'todo');
    expect(reminder.parentId, allocation.todoId);
    expect(
      reminder.triggerTime,
      allocation.startAt.toLocal().subtract(const Duration(minutes: 15)),
    );

    await _unmount(tester);
  });

  testWidgets('default capture writes null dueDate and no allocation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await _openPanel(tester, 'Just a title');
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    final personal = (await db.select(db.calendars).get()).firstWhere(
      (calendar) => calendar.name == 'Personal',
    );
    expect(todo.dueDate, isNull);
    expect(todo.calendarId, personal.id);
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    expect(await db.select(db.reminders).get(), isEmpty);

    await _unmount(tester);
  });
}
