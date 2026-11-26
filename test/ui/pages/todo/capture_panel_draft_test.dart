import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/pages/todo/capture_panel_submit.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

Widget _app({
  required AppDatabase db,
  List<A2CaptureDraft>? recorded,
  List<Override> overrides = const [],
}) {
  final now = DateTime(2026, 11, 15, 10);
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      todosViewProvider.overrideWith((ref) => const TodosAllView()),
      ...overrides,
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
        body: Consumer(
          builder: (context, ref, _) => A2TodoPage(
            now: now,
            dayAgenda: DayAgenda(
              day: DateTime(now.year, now.month, now.day),
              events: const [],
              allocations: const [],
              dueTodos: const [],
              overdueTodos: const [],
              instances: const [],
            ),
            onCaptureDraft: (text, draft) {
              recorded?.add(draft);
              return submitTodoCapture(ref, context, text, draft);
            },
          ),
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
  final field = find.descendant(
    of: find.byType(A2CaptureBar),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, title);
  await tester.tap(find.byKey(const ValueKey('capture-send-target')));
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
  late int homeId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    homeId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Home',
            color: const Value('#E39A3B'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('Todo capture panel writes date and calendar through the real path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final drafts = <A2CaptureDraft>[];
    await tester.pumpWidget(_app(db: db, recorded: drafts));
    await _settle(tester);

    await _openPanel(tester, 'Todo capture');
    await tester.tap(_inPanel('Deadline'));
    await _settle(tester);
    await tester.tap(_inPanel('Tomorrow'));
    await _settle(tester);
    await tester.tap(_inPanel('Calendar'));
    await _settle(tester);
    await tester.tap(_inPanel('Home'));
    await _settle(tester);
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.summary, 'Todo capture');
    expect(todo.dueDate, _tomorrow());
    expect(todo.calendarId, homeId);
    expect(drafts.single.dueDate, _tomorrow());
    expect(drafts.single.calendarId, homeId);

    await _unmount(tester);
  });

  testWidgets('Todo capture panel writes a bare todo by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final drafts = <A2CaptureDraft>[];
    await tester.pumpWidget(_app(db: db, recorded: drafts));
    await _settle(tester);

    await _openPanel(tester, 'Bare todo');
    await _submitPanel(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.dueDate, isNull);
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    expect(await db.select(db.reminders).get(), isEmpty);
    expect(drafts.single.isEmpty, isTrue);

    await _unmount(tester);
  });

  testWidgets('parsed capture writes the parsed title and its preselected plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final drafts = <A2CaptureDraft>[];
    await tester.pumpWidget(_app(db: db, recorded: drafts));
    await _settle(tester);

    // Entering a sentence with a time opens the parsed panel; its primary must
    // write the plan it showed, not merely re-open the same panel.
    await _openPanel(tester, '明天下午三点交报告');
    expect(find.byType(A2CapturePanel), findsOneWidget);
    expect(_inPanel('Save task'), findsOneWidget);
    await tester.tap(_inPanel('Save task'));
    await _settle(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.summary, '交报告');
    final allocation = (await db.select(db.taskAllocations).get()).single;
    expect(allocation.todoId, todo.id);
    expect(drafts.single.planStart, isNotNull);
    expect(drafts.single.planEnd, isNotNull);
    expect(find.byType(A2CapturePanel), findsNothing);

    await _unmount(tester);
  });

  testWidgets('parsed capture can drop its time suggestion and writes no plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final drafts = <A2CaptureDraft>[];
    await tester.pumpWidget(_app(db: db, recorded: drafts));
    await _settle(tester);

    await _openPanel(tester, '明天下午三点交报告');
    await tester.tap(_inPanel('Remove'));
    await _settle(tester);
    await tester.tap(_inPanel('Save task'));
    await _settle(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.summary, '交报告');
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    expect(drafts.single.planStart, isNull);

    await _unmount(tester);
  });

  testWidgets('event capture creates an event with the chosen time and repeat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db: db));
    await _settle(tester);

    await _openPanel(tester, '明天下午三点和设计团队评审方案');
    await tester.tap(_inPanel('Change to Event'));
    await _settle(tester);
    expect(_inPanel('New Event'), findsOneWidget);

    // The repeat row cycles through real rules; changing it must not bounce
    // the panel back to Todo mode.
    await tester.tap(_inPanel('Repeat'));
    await _settle(tester);
    await tester.tap(_inPanel('Repeat'));
    await _settle(tester);
    expect(_inPanel('Every week'), findsOneWidget);
    expect(_inPanel('New Event'), findsOneWidget);

    await tester.tap(_inPanel('Create Event'));
    await _settle(tester);

    final event = (await db.select(db.events).get()).single;
    expect(event.summary, '和设计团队评审方案');
    expect(event.rrule, 'FREQ=WEEKLY');
    expect(await db.select(db.todos).get(), isEmpty);
    expect(find.byType(A2CapturePanel), findsNothing);

    await _unmount(tester);
  });

  testWidgets('capture on a browsed day writes that day\'s plan', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final browsed = DateTime(2026, 11, 20);
    final drafts = <A2CaptureDraft>[];
    await tester.pumpWidget(
      _app(
        db: db,
        recorded: drafts,
        overrides: [
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => browsed),
        ],
      ),
    );
    await _settle(tester);

    // The bar promises "Plan on 11/20"; a quick capture must land there.
    expect(find.textContaining('Plan on 11/20'), findsWidgets);
    final field = find.descendant(
      of: find.byType(A2CaptureBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'Browsed-day task');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    final todo = (await db.select(db.todos).get()).single;
    final allocation = (await db.select(db.taskAllocations).get()).single;
    expect(allocation.todoId, todo.id);
    final start = allocation.startAt.toLocal();
    expect(start.year, browsed.year);
    expect(start.month, browsed.month);
    expect(start.day, browsed.day);
    expect(drafts.single.planStart, isNotNull);

    await _unmount(tester);
  });

  testWidgets('a failing write keeps the panel open and the draft intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        db: db,
        overrides: [
          createTodoProvider.overrideWith((ref) {
            return ({
              required int calendarId,
              required String summary,
              required int priority,
              required String status,
              DateTime? dueDate,
              DateTime? startDate,
              String? description,
              String? rrule,
              RecurrenceSpec? recurrenceSpec,
              int? parentId,
            }) async {
              throw StateError('offline');
            };
          }),
        ],
      ),
    );
    await _settle(tester);

    await _openPanel(tester, 'Offline write');
    await tester.tap(_inPanel('Deadline'));
    await _settle(tester);
    await tester.tap(_inPanel('Tomorrow'));
    await _settle(tester);
    await _submitPanel(tester);

    expect(find.byType(A2CapturePanel), findsOneWidget);
    expect(_inPanel('Save Failed'), findsOneWidget);
    final field = find.descendant(
      of: find.byType(A2CaptureBar),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, 'Offline write');

    await _unmount(tester);
  });
}
