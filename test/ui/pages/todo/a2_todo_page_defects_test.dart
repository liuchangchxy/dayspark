import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';

Widget _app({
  required List<Override> overrides,
  required DateTime now,
  ValueChanged<Todo>? onOpenTodo,
  Future<bool> Function(Todo todo, String? occurrenceId, bool completed)?
  onToggleTodo,
  ValueChanged<Todo>? onScheduleTodo,
  Future<void> Function(String text)? onCapture,
  DayAgenda? dayAgenda,
  Widget Function(Widget page)? wrapPage,
}) {
  final page = A2TodoPage(
    now: now,
    dayAgenda:
        dayAgenda ??
        DayAgenda(
          day: DateTime(now.year, now.month, now.day),
          events: const [],
          allocations: const [],
          dueTodos: const [],
          overdueTodos: const [],
          instances: const [],
        ),
    onOpenTodo: onOpenTodo,
    onToggleTodo: onToggleTodo,
    onScheduleTodo: onScheduleTodo,
    onCapture: onCapture,
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: wrapPage != null ? wrapPage(page) : page,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int calendarId;
  final now = DateTime(2026, 11, 15, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
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

  testWidgets('date strip reads past days backwards and future days forwards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 10)),
        ],
        now: now,
      ),
    );
    await _settle(tester);
    expect(find.textContaining('5 days ago'), findsOneWidget);
    expect(find.textContaining('In 5 days'), findsNothing);
    await _unmount(tester);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 20)),
        ],
        now: now,
      ),
    );
    await _settle(tester);
    expect(find.textContaining('In 5 days'), findsOneWidget);
    expect(find.textContaining('5 days ago'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('inbox row opens details and schedules from its own action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Buy milk',
          ),
        );
    final opened = <int>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
        ],
        now: now,
        onOpenTodo: (todo) => opened.add(todo.id),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Buy milk'));
    await _settle(tester);
    expect(opened, [id]);

    // The right edge owns its own verb, sized as a touch target rather than a
    // word inside the row body.
    final schedule = find.byKey(ValueKey('todo-schedule-$id-series'));
    expect(schedule, findsOneWidget);
    final size = tester.getSize(schedule);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));

    await tester.tap(schedule);
    await _settle(tester);

    // The Schedule key opens the composer's existing-todo mode: title locked,
    // and the create-only rows are gone.
    expect(find.byType(A2ComposerSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('a2-composer-title')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-reminder')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-calendar')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-priority')), findsNothing);
    expect(opened, [id]);

    await _unmount(tester);
  });

  testWidgets('completing a row reports it and Undo reopens it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Buy milk',
          ),
        );
    final calls = <(String?, bool)>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
        ],
        now: now,
        onToggleTodo: (todo, occurrenceId, completed) async {
          calls.add((occurrenceId, completed));
          return true;
        },
      ),
    );
    await _settle(tester);

    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);
    expect(calls, [(null, true)]);
    expect(find.text('Completed'), findsOneWidget);

    // D3: the row does not move or disappear during the undo window; the
    // right edge turns into the undo key.
    expect(find.text('Buy milk'), findsOneWidget);
    final undo = find.byKey(ValueKey('todo-undo-$id-series'));
    expect(undo, findsOneWidget);

    await tester.tap(undo);
    await _settle(tester);
    expect(calls, [(null, true), (null, false)]);
    expect(find.byKey(ValueKey('todo-undo-$id-series')), findsNothing);
    expect(find.text('Buy milk'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the row undo key disappears after five seconds', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Buy milk',
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
        ],
        now: now,
        onToggleTodo: (todo, occurrenceId, completed) async {
          await (db.update(
            db.todos,
          )..where((row) => row.id.equals(todo.id))).write(
            TodosCompanion(
              status: Value(completed ? 'COMPLETED' : 'NEEDS-ACTION'),
            ),
          );
          return true;
        },
      ),
    );
    await _settle(tester);

    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);
    expect(find.byKey(ValueKey('todo-undo-$id-series')), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.byKey(ValueKey('todo-undo-$id-series')), findsNothing);
    expect(find.text('Buy milk'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('All keeps a completed row in place, then sinks it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final first = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Alpha',
            dueDate: Value(DateTime(2026, 11, 15, 9)),
          ),
        );
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Beta',
            dueDate: Value(DateTime(2026, 11, 15, 10)),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
        onToggleTodo: (todo, occurrenceId, completed) async {
          await (db.update(
            db.todos,
          )..where((row) => row.id.equals(todo.id))).write(
            TodosCompanion(
              status: Value(completed ? 'COMPLETED' : 'NEEDS-ACTION'),
            ),
          );
          return true;
        },
      ),
    );
    await _settle(tester);

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );

    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);
    expect(find.byKey(ValueKey('todo-undo-$first-series')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // Spec allList() (dayspark-spec.html:1493-1510): 'Completed' is an
    // independent fold group; expanding it confirms Alpha has sunk into the
    // completed group below active todos.
    await tester.tap(find.widgetWithText(A2GroupHead, 'Completed'));
    await _settle(tester);

    expect(find.byKey(ValueKey('todo-undo-$first-series')), findsNothing);
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      greaterThan(tester.getTopLeft(find.text('Beta')).dy),
    );

    await _unmount(tester);
  });

  testWidgets('a recurring row undo names its occurrence', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Water plants',
            rrule: const Value('FREQ=WEEKLY;BYDAY=SU'),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    const occurrenceId = 'v2:DATE:2026-11-15';
    final allocation = TaskAllocation(
      id: 1,
      todoId: id,
      occurrenceId: occurrenceId,
      startAt: DateTime(2026, 11, 15, 9),
      endAt: DateTime(2026, 11, 15, 10),
      state: 'active',
      createdAt: now,
      updatedAt: now,
      serverRev: 0,
    );
    final calls = <(String?, bool)>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
        ],
        now: now,
        dayAgenda: DayAgenda(
          day: DateTime(2026, 11, 15),
          events: const [],
          allocations: [
            DayItem(
              kind: DayItemKind.allocation,
              title: todo.summary,
              start: DateTime(2026, 11, 15, 9),
              end: DateTime(2026, 11, 15, 10),
              todo: todo,
              allocation: TaskAllocationCalendarItem(
                allocation: allocation,
                todo: todo,
              ),
              occurrenceId: occurrenceId,
            ),
          ],
          dueTodos: const [],
          overdueTodos: const [],
          instances: const [],
        ),
        onToggleTodo: (todo, occurrenceId, completed) async {
          calls.add((occurrenceId, completed));
          return true;
        },
      ),
    );
    await _settle(tester);

    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);

    expect(calls, [(occurrenceId, true)]);
    expect(find.text('Undo · 2026-11-15'), findsOneWidget);
    final undo = find.byKey(ValueKey('todo-undo-$id-$occurrenceId'));
    expect(undo, findsOneWidget);

    await tester.tap(undo);
    await _settle(tester);
    expect(calls, [(occurrenceId, true), (occurrenceId, false)]);

    await _unmount(tester);
  });

  testWidgets('the view switch shows mode switch control with three modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('todos-mode-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-mode-inbox')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-mode-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-mode-date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-mode-date')));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodoPage)),
      listen: false,
    );
    expect(container.read(todosViewProvider), isA<TodosDayView>());

    await _unmount(tester);
  });

  testWidgets('All empty uses its own copy, not the unplanned one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    expect(find.text('All Tasks'), findsWidgets);
    expect(find.text('No tasks here'), findsOneWidget);
    expect(find.text('Capture one — Enter puts it here'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('a dismissed occurrence picker does not report a completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Skipped tick',
            rrule: Value('FREQ=DAILY;COUNT=5'),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
        ],
        now: now,
        // The production callback returns false when the occurrence picker is
        // dismissed, so no write happened and nothing may claim one.
        onToggleTodo: (todo, occurrenceId, completed) async => false,
      ),
    );
    await _settle(tester);

    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);

    expect(find.text('Completed'), findsNothing);
    expect(find.byKey(ValueKey('todo-undo-$id-series')), findsNothing);
    expect(find.text('Skipped tick'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('desktop filter exposes 48dp hit target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 10)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    final size = tester.getSize(find.byKey(const ValueKey('todos-filter-tool')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    expect(
      tester
          .getSize(find.byKey(const ValueKey('todos-filter-tool-visual')))
          .height,
      29,
    );

    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('mobile mode switch and date cells expose 48dp hit targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 10)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    for (final key in const [
      'todo-mode-inbox',
      'todo-mode-all',
      'todo-mode-date',
      'todos-date-strip',
      'todos-date-strip-today',
      'todos-date-strip-day-2026-11-10',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }

    expect(
      tester
          .getSize(find.byKey(const ValueKey('todos-mode-switch-visual')))
          .height,
      33,
    );
    for (final key in const [
      'todo-mode-visual-inbox',
      'todo-mode-visual-all',
      'todo-mode-visual-date',
    ]) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, 27, reason: key);
    }
    expect(
      tester
          .getSize(find.byKey(const ValueKey('todos-date-strip-visual')))
          .height,
      28,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('todos-date-strip-today-visual')),
          )
          .height,
      28,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('todos-date-strip-day-visual-2026-11-10')),
      ),
      const Size(34, 44),
    );

    expect(
      tester.getSemantics(find.byKey(const ValueKey('todo-mode-inbox'))).label,
      'Unplanned',
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('todo-mode-all'))).label,
      'All',
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('todo-mode-date'))).label,
      'By date',
    );

    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets(
    'mobile todo header matches m-top 50h, 15px title, actions search/filter, and persistent mode switch',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosDayView()),
            viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 10)),
          ],
          now: now,
        ),
      );
      await _settle(tester);

      final topBarFinder = find.byKey(const ValueKey('m-top'));
      expect(topBarFinder, findsOneWidget);
      expect(tester.getSize(topBarFinder).height, 50.0);

      final titleFinder = find.descendant(
        of: topBarFinder,
        matching: find.textContaining('Nov 10'),
      );
      expect(titleFinder, findsOneWidget);
      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.style?.fontSize, 15);
      expect(
        titleWidget.style?.fontVariations?.any(
          (v) => v.axis == 'wght' && v.value == 650,
        ),
        isTrue,
      );

      final searchFinder = find.byKey(const ValueKey('todos-search-tool'));
      final filterFinder = find.byKey(const ValueKey('todos-filter-tool'));
      expect(searchFinder, findsOneWidget);
      expect(filterFinder, findsOneWidget);
      expect(tester.getSize(searchFinder), const Size(30.0, 30.0));
      expect(tester.getSize(filterFinder), const Size(30.0, 30.0));

      await tester.tap(searchFinder);
      await _settle(tester);

      await tester.tap(filterFinder);
      await _settle(tester);
      expect(find.text('Filter'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('todos-mode-switch')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-mode-inbox')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-mode-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-mode-date')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo-mode-all')));
      await _settle(tester);
      expect(
        find.descendant(of: topBarFinder, matching: find.text('All Tasks')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('todo-mode-inbox')));
      await _settle(tester);
      expect(
        find.descendant(of: topBarFinder, matching: find.text('Unplanned')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('todo-mode-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-mode-date')), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('date strip keeps its layout and the selected day is not clipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    // Seven mobile cells (34) and six 4px gaps: 262, the original layout width.
    expect(
      tester.getSize(find.byKey(const ValueKey('todos-date-strip-days'))).width,
      262,
    );

    final viewport = tester.getRect(
      find.byKey(const ValueKey('todos-date-strip-scroll')),
    );
    final selected = tester.getRect(
      find.byKey(
        const ValueKey('todos-date-strip-day-visual-2026-11-15'),
      ),
    );
    expect(selected.size, const Size(34, 44));
    expect(selected.right, lessThanOrEqualTo(viewport.right));

    // The pre-existing content scrolled 82.25px; the overlay must not add more.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('todos-date-strip-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, lessThanOrEqualTo(83));

    await _unmount(tester);
  });

  testWidgets('date strip taps map to the day under the finger', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodoPage)),
      listen: false,
    );
    final anchor = DateTime(2026, 11, 15);
    final dates = [
      for (var i = -3; i <= 3; i++) anchor.add(Duration(days: i)),
    ];

    for (final target in dates) {
      final visual = find.byKey(
        ValueKey('todos-date-strip-day-visual-${_dateKey(target)}'),
      );
      for (final inset in const [null, 3.0]) {
        container.read(viewedDateProvider.notifier).state = anchor;
        await _settle(tester);
        await tester.ensureVisible(visual);
        await tester.pumpAndSettle();
        final rect = tester.getRect(visual);
        final point = inset == null
            ? rect.center
            : Offset(rect.right - inset, rect.center.dy);
        await tester.tapAt(point);
        await _settle(tester);
        expect(
          container.read(viewedDateProvider),
          target,
          reason: '${inset == null ? 'center' : 'right-3'} $target',
        );
      }
    }

    await _unmount(tester);
  });
  testWidgets('date strip has one semantics node per day and no text noise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    final allLabels = <String>[];
    final tapLabels = <String>[];
    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (node.label.isNotEmpty) allLabels.add(node.label);
      if (data.hasAction(SemanticsAction.tap) && node.label.isNotEmpty) {
        tapLabels.add(node.label);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    final root = tester
        .binding
        .renderViews
        .first
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!;
    visit(root);

    for (final label in const [
      'Thu 12',
      'Fri 13',
      'Sat 14',
      'Sun 15',
      'Mon 16',
      'Tue 17',
      'Wed 18',
    ]) {
      expect(tapLabels.where((value) => value == label), hasLength(1));
    }

    const noise = [
      'Thu',
      'Fri',
      'Sat',
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      '12',
      '13',
      '14',
      '15',
      '16',
      '17',
      '18',
    ];
    expect(allLabels.where(noise.contains), isEmpty);

    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('mobile undo bar clears the capture bar above the 56px dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
        wrapPage: (page) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: page),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
    await _settle(tester);

    final context = tester.element(find.byType(A2TodoPage));
    showUndoBar(
      context,
      message: 'Todo completed',
      undoLabel: 'Undo',
      onUndo: () {},
    );
    await tester.pumpAndSettle();

    final undoRect = tester.getRect(
      find.byKey(const ValueKey('undo-bar-content')),
    );
    final captureRect = tester.getRect(find.byType(A2CaptureBar));

    // Spec .m-capture{bottom:62px} & .m-undo{bottom:118px}: rects must not overlap
    expect(
      undoRect.overlaps(captureRect),
      isFalse,
      reason:
          'Spec .m-capture{bottom:62px} and .m-undo{bottom:118px} must not intersect',
    );
    expect(
      undoRect.bottom,
      lessThanOrEqualTo(captureRect.top),
      reason: 'Undo bar bottom must sit above or clear capture bar top',
    );

    await _unmount(tester);
  });

  testWidgets('desktop capture bar floats over the todo list at bottom 18', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    final captureRect = tester.getRect(find.byType(A2CaptureBar));
    // Spec .capture{bottom:18px}: window height 900, capture bottom sits at 900 - 18 = 882
    expect(captureRect.bottom, 900 - 18);

    await _unmount(tester);
  });

  testWidgets(
    'P1: mobile task row geometry (title x~45, check left x~19.5, height ~50) and 48dp hit targets on 390 screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final id = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Spec task row check',
            ),
          );

      var toggleCount = 0;
      var detailCount = 0;
      var scheduleCount = 0;

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosAllView()),
          ],
          now: now,
          onOpenTodo: (_) => detailCount++,
          onScheduleTodo: (_) => scheduleCount++,
          onToggleTodo: (_, __, ___) async {
            toggleCount++;
            return true;
          },
        ),
      );
      await _settle(tester);

      // 1. Title start x ≈ 45 ± 1
      final title = find.text('Spec task row check');
      final titleLeft = tester.getTopLeft(title).dx;
      expect(titleLeft, closeTo(45.0, 1.0));

      // 2. Checkbox visual left edge ≈ 19.5 ± 1
      final check = find.byType(DsCheck).first;
      final checkCenter = tester.getCenter(check);
      expect(checkCenter.dx, closeTo(27.0, 1.0));
      // Visual circle r = 7.5 (size 15), visual left edge is checkCenter.dx - 7.5
      final visualLeft = checkCenter.dx - 7.5;
      expect(visualLeft, closeTo(19.5, 1.0));

      // 3. Row height ≈ 50 ± 1
      final row = find.ancestor(
        of: title,
        matching: find.byType(GestureDetector),
      ).first;
      final rowSize = tester.getSize(row);
      expect(rowSize.height, closeTo(50.0, 1.0));

      // 4. Checkbox center - 18px (dx = 9) tap toggles, does not open detail
      await tester.tapAt(Offset(checkCenter.dx - 18, checkCenter.dy));
      await _settle(tester);
      expect(toggleCount, 1);
      expect(detailCount, 0);
      expect(scheduleCount, 0);

      // 5. Checkbox center + 18px (dx = 45) tap toggles, does not open detail
      await tester.tapAt(Offset(checkCenter.dx + 18, checkCenter.dy));
      await _settle(tester);
      expect(toggleCount, 2);
      expect(detailCount, 0);
      expect(scheduleCount, 0);

      // 6. Trailing calendar action hit target size >= 48
      final scheduleFinder = find.byKey(ValueKey('todo-schedule-$id-series'));
      expect(scheduleFinder, findsOneWidget);
      final scheduleSize = tester.getSize(scheduleFinder);
      expect(scheduleSize.width, greaterThanOrEqualTo(48.0));
      expect(scheduleSize.height, greaterThanOrEqualTo(48.0));

      // 7. Trailing calendar center ± 18px tap schedules
      final calendarIcon = find.byIcon(CupertinoIcons.calendar);
      final scheduleVisualCenter = tester.getCenter(calendarIcon);
      expect(scheduleVisualCenter.dx, closeTo(358.0, 1.0));

      await tester.tapAt(Offset(scheduleVisualCenter.dx - 18, scheduleVisualCenter.dy));
      await _settle(tester);
      expect(scheduleCount, 1);
      expect(toggleCount, 2);
      expect(detailCount, 0);

      await tester.tapAt(Offset(scheduleVisualCenter.dx + 18, scheduleVisualCenter.dy));
      await _settle(tester);
      expect(scheduleCount, 2);
      expect(toggleCount, 2);
      expect(detailCount, 0);

      // 8. Tapping row body (title) opens detail
      await tester.tap(title);
      await _settle(tester);
      expect(detailCount, 1);
      expect(toggleCount, 2);
      expect(scheduleCount, 2);

      await _unmount(tester);
    },
  );

  testWidgets(
    'desktop geometry preserves row height ~58 and title start x ~63 without regression',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Desktop geometry task',
            ),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosAllView()),
          ],
          now: now,
        ),
      );
      await _settle(tester);

      final title = find.text('Desktop geometry task');
      final titleLeft = tester.getTopLeft(title).dx;
      // Desktop: list left 28 + task row padding 3 + check col 24 + gap 8 = 63.0
      expect(titleLeft, closeTo(63.0, 1.0));

      final specTaskRow = find.byType(SpecTaskRow);
      expect(specTaskRow, findsOneWidget);
      final rowSize = tester.getSize(specTaskRow);
      // Desktop: row height minHeight 55 + padding 7*2 ~ 58
      expect(rowSize.height, closeTo(58.0, 3.0));

      await _unmount(tester);
    },
  );

  testWidgets(
    'P2: mobile capture bar visible size 366x48 and left 12, list top padding 14 (8 on desktop)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Capture and padding test task',
            ),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosAllView()),
          ],
          now: now,
        ),
      );
      await _settle(tester);

      // Mobile capture bar visible pill (margin: 12, height: 48)
      final visibleCapture = find
          .descendant(
            of: find.byType(A2CaptureBar),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final captureRect = tester.getRect(visibleCapture);
      expect(captureRect.left, 12.0);
      expect(captureRect.width, 366.0);
      expect(captureRect.height, 48.0);

      // Mobile list top padding 14
      final list = tester.widget<ListView>(find.byType(ListView).first);
      final padding = list.padding as EdgeInsets;
      expect(padding.top, 14.0);

      await _unmount(tester);

      // Switch to desktop 1440x900
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosAllView()),
          ],
          now: now,
        ),
      );
      await _settle(tester);

      final desktopList = tester.widget<ListView>(find.byType(ListView).first);
      final desktopPadding = desktopList.padding as EdgeInsets;
      expect(desktopPadding.top, 8.0);

      await _unmount(tester);
    },
  );

  testWidgets(
    'mobile capture bar send button: visual 32x32, hit target >= 48dp, tapping 8px outside visual submits; desktop visual 34x34',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final captured = <String>[];
      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosAllView()),
          ],
          now: now,
          onCapture: (text) async {
            captured.add(text);
            await db.into(db.todos).insert(
              TodosCompanion.insert(
                calendarId: calendarId,
                summary: text,
              ),
            );
          },
        ),
      );
      await _settle(tester);

      // Mobile: visual is 32x32
      final visualSend = find.byKey(const ValueKey('capture-send-visual'));
      expect(visualSend, findsOneWidget);
      final visualSize = tester.getSize(visualSend);
      expect(visualSize.width, 32.0);
      expect(visualSize.height, 32.0);

      // Mobile: hit target is >= 48dp
      final hitTarget = find.byKey(const ValueKey('capture-send-target'));
      expect(hitTarget, findsOneWidget);
      final hitSize = tester.getSize(hitTarget);
      expect(hitSize.width, greaterThanOrEqualTo(48.0));
      expect(hitSize.height, greaterThanOrEqualTo(48.0));

      // Tapping 8px outside the visual circle (left edge - 8px) submits
      final visualCenter = tester.getCenter(visualSend);
      final captureField = find.descendant(
        of: find.byType(A2CaptureBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(captureField, 'Tap outside 8px item');
      await tester.pump();

      // 8px outside visual circle to the left: center.dx - 16 - 8 = center.dx - 24
      await tester.tapAt(Offset(visualCenter.dx - 24, visualCenter.dy));
      await _settle(tester);

      final todosAfterOutsideTap = await db.select(db.todos).get();
      expect(
        todosAfterOutsideTap.any((t) => t.summary == 'Tap outside 8px item'),
        isTrue,
        reason: 'Tapping 8px outside send button visual edge must submit',
      );

      // Tapping visual center also submits
      await tester.enterText(captureField, 'Tap center item');
      await tester.pump();
      await tester.tapAt(visualCenter);
      await _settle(tester);

      final todosAfterCenterTap = await db.select(db.todos).get();
      expect(
        todosAfterCenterTap.any((t) => t.summary == 'Tap center item'),
        isTrue,
        reason: 'Tapping center of send button must submit',
      );

      await _unmount(tester);

      // Switch to desktop 1440x900
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todosViewProvider.overrideWith((ref) => const TodosAllView()),
          ],
          now: now,
        ),
      );
      await _settle(tester);

      final desktopVisualSend = find.byKey(const ValueKey('capture-send-visual'));
      expect(desktopVisualSend, findsOneWidget);
      final desktopVisualSize = tester.getSize(desktopVisualSend);
      expect(desktopVisualSize.width, 34.0);
      expect(desktopVisualSize.height, 34.0);

      await _unmount(tester);
    },
  );

  testWidgets('the Todo capture bar opens the unified composer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    final send = find.byKey(const ValueKey('capture-send-target'));
    expect(send, findsOneWidget);
    await tester.tap(send);
    await _settle(tester);

    expect(find.byType(A2ComposerSheet), findsOneWidget);

    await _unmount(tester);
  });
}

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
