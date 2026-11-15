import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Widget _app({
  required List<Override> overrides,
  required DateTime now,
  ValueChanged<Todo>? onOpenTodo,
  Future<void> Function(Todo todo, String? occurrenceId, bool completed)?
  onToggleTodo,
  ValueChanged<Todo>? onScheduleTodo,
  DayAgenda? dayAgenda,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: A2TodoPage(
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

  testWidgets('the view switch shows a visible chevron that opens the sheet', (
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

    expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
    await _settle(tester);
    expect(find.text('By date'), findsOneWidget);

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
    expect(find.text('No pending tasks'), findsOneWidget);
    expect(find.text('Capture one — Enter puts it here'), findsNothing);

    await _unmount(tester);
  });
}
