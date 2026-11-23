import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

Widget _app({
  required List<Override> overrides,
  DateTime? now,
  ValueChanged<Todo>? onOpenTodo,
  ValueChanged<Todo>? onScheduleTodo,
  VoidCallback? onOpenUnplanned,
  VoidCallback? onOpenAll,
  Future<bool> Function(Todo todo, String? occurrenceId, bool completed)?
  onToggleTodo,
}) {
  return ProviderScope(
    overrides: overrides,
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
          now: now ?? DateTime(2026, 10, 6, 15),
          onOpenTodo: onOpenTodo ?? (_) {},
          onOpenEvent: (_) {},
          onToggleTodo: onToggleTodo ?? (_, __, ___) async => true,
          onOpenUnplanned: onOpenUnplanned ?? () {},
          onOpenAll: onOpenAll,
          onScheduleTodo: onScheduleTodo ?? (_) {},
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

Future<int> _createSeries(
  AppDatabase db, {
  required int calendarId,
  required String summary,
  required RecurrenceSpec spec,
}) {
  return RecordScope.run(
    db,
    (tx) => TodoWriter.create(
      db,
      tx,
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: summary,
        rrule: Value(spec.rule.canonical),
      ),
      recurrenceSpec: spec,
    ),
  );
}

Future<bool> _completeInDb(
  AppDatabase db,
  Todo todo,
  String? occurrenceId,
  bool completed,
) async {
  await RecordScope.run(
    db,
    (tx) => TodoWriter.setCompletion(
      db,
      tx,
      todo.id,
      isCompleted: completed,
      occurrenceId: occurrenceId,
    ),
  );
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late int calendarId;
  final day = DateTime(2026, 10, 6);

  setUp(() async {
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

  testWidgets('empty day shows the empty box and keeps the capture row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Nothing scheduled today'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-capture-field')), findsOneWidget);
    expect(find.text('Now'), findsNothing);
    expect(find.text('Overdue'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('today is sectioned and a planned todo appears once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Dentist',
            startDt: DateTime(2026, 10, 6, 14, 30),
            endDt: DateTime(2026, 10, 6, 15, 15),
            isAllDay: const Value(false),
          ),
        );
    final plannedId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Weekly notes',
            dueDate: Value(DateTime(2026, 10, 6, 18)),
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: plannedId,
      startAt: DateTime(2026, 10, 6, 16),
      endAt: DateTime(2026, 10, 6, 17),
    );
    container.dispose();
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Submit report',
            dueDate: Value(DateTime(2026, 10, 6, 18)),
          ),
        );
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Pay rent',
            dueDate: Value(DateTime(2026, 10, 2, 10)),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);

    expect(find.text('Dentist'), findsOneWidget);
    // Allocation leads, the deadline is secondary metadata: one row, not two.
    expect(find.text('Weekly notes'), findsOneWidget);
    expect(find.text('Submit report'), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.textContaining('Planned 16:00–17:00'), findsOneWidget);
    expect(find.textContaining('4 days late'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('capture writes a bare todo and nothing else', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('today-capture-field')),
      'Buy milk',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Buy milk');
    expect(todos.single.dueDate, isNull);
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    expect(find.text('Buy milk'), findsWidgets);

    await _unmount(tester);
  });

  testWidgets('browsing another date never moves today', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            // After the page clock (15:00), so the item is Upcoming rather
            // than Ended; the test is about dates, not about sectioning.
            summary: 'Standup',
            startDt: DateTime(2026, 10, 6, 16),
            endDt: DateTime(2026, 10, 6, 17),
            isAllDay: const Value(false),
          ),
        );

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Other day',
            startDt: DateTime(2026, 10, 9, 9),
            endDt: DateTime(2026, 10, 9, 10),
            isAllDay: const Value(false),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 10, 9)),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Other day'), findsNothing);
    expect(find.text('Upcoming'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('completed today stays folded, then undoes through the writer', (
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
            summary: 'Finished report',
            status: const Value('COMPLETED'),
            completedAt: Value(DateTime(2026, 10, 6, 14)),
          ),
        );
    final opened = <int>[];
    final toggles = <(int, String?, bool)>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onOpenTodo: (todo) => opened.add(todo.id),
        onToggleTodo: (todo, occurrenceId, completed) async {
          toggles.add((todo.id, occurrenceId, completed));
          return true;
        },
      ),
    );
    await _settle(tester);

    // Completed work is secondary, not an empty day and not a timeline block.
    expect(find.text('Nothing scheduled today'), findsNothing);
    expect(find.text('Completed Today'), findsOneWidget);
    expect(find.text('Finished report'), findsNothing);

    await tester.tap(find.text('Completed Today'));
    await _settle(tester);
    expect(find.text('Finished report'), findsOneWidget);

    await tester.tap(find.text('Finished report'));
    await _settle(tester);
    expect(opened, [id]);

    // The row is already checked; its check is the undo path.
    final completedCheck = find.byWidgetPredicate(
      (widget) =>
          widget is DsCheck &&
          widget.checked &&
          widget.label == 'Finished report',
    );
    expect(completedCheck, findsOneWidget);
    await tester.tap(completedCheck);
    await _settle(tester);
    expect(toggles, [(id, null, false)]);

    await _unmount(tester);
  });

  testWidgets('completed recurring instance keeps its occurrence id for undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(2026, 10, 6),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=3',
    );
    final seriesId = await _createSeries(
      db,
      calendarId: calendarId,
      summary: 'Daily Review',
      spec: spec,
    );
    final series = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(seriesId))).getSingle();
    const occurrenceId = 'v2:DATE:2026-10-06';
    await db
        .into(db.taskInstanceStates)
        .insert(
          TaskInstanceStatesCompanion.insert(
            syncId: 'state-review',
            todoSyncId: series.syncId!,
            todoId: Value(seriesId),
            occurrenceId: occurrenceId,
            status: const Value('completed'),
            completedAt: Value(DateTime(2026, 10, 6, 12)),
          ),
        );
    final toggles = <(int, String?, bool)>[];

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onToggleTodo: (todo, occurrence, completed) async {
          toggles.add((todo.id, occurrence, completed));
          return true;
        },
      ),
    );
    await _settle(tester);

    expect(find.text('Completed Today'), findsOneWidget);
    // The recurring series also sits in the unplanned shelf as a parent row.
    expect(find.text('Daily Review'), findsOneWidget);
    await tester.tap(find.text('Completed Today'));
    await _settle(tester);
    expect(find.text('Daily Review'), findsNWidgets(2));

    final completedCheck = find.byWidgetPredicate(
      (widget) =>
          widget is DsCheck && widget.checked && widget.label == 'Daily Review',
    );
    expect(completedCheck, findsOneWidget);
    await tester.tap(completedCheck);
    await _settle(tester);
    expect(toggles, [(seriesId, occurrenceId, false)]);

    await _unmount(tester);
  });

  testWidgets('a missed series renders one card with its missed count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(2026, 10, 1),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=7',
    );
    final seriesId = await _createSeries(
      db,
      calendarId: calendarId,
      summary: 'Daily Plan',
      spec: spec,
    );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    final card = find.byKey(ValueKey('missed-card-$seriesId'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Daily Plan')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(
          'Every day · Missed 5 times · Completing affects only this one',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Complete This Occurrence'),
      ),
      findsOneWidget,
    );
    expect(find.text('Missed'), findsNothing);
    expect(find.textContaining('Show all'), findsNothing);

    await _unmount(tester);
  });

  testWidgets(
    'an earlier missed series renders a card even when the recent window is empty',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDate(2026, 8, 1),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=100',
      );
      final seriesId = await _createSeries(
        db,
        calendarId: calendarId,
        summary: 'Long Streak',
        spec: spec,
      );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
        ),
      );
      await _settle(tester);

      // 9/6–10/5 is the recent 30-day window; the card aggregates every
      // occurrence the projection can still name.
      final card = find.byKey(ValueKey('missed-card-$seriesId'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Long Streak')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            'Every day · Missed 30 times · Completing affects only this one',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Missed'), findsNothing);
      expect(find.text('Earlier missed…'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'a missed card completes one occurrence, leaves overdue, and disappears',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final overdueId = await db.into(db.todos).insertReturning(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Late report',
              dueDate: Value(day.subtract(const Duration(days: 1))),
            ),
          );
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDate(2026, 10, 5),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=1',
      );
      final seriesId = await _createSeries(
        db,
        calendarId: calendarId,
        summary: 'Weekly notes',
        spec: spec,
      );
      final calls = <(int, String?, bool)>[];

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onToggleTodo: (todo, occurrenceId, completed) async {
            calls.add((todo.id, occurrenceId, completed));
            return _completeInDb(db, todo, occurrenceId, completed);
          },
        ),
      );
      await _settle(tester);

      final card = find.byKey(ValueKey('missed-card-$seriesId'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            'Every day · Missed 1 times · Completing affects only this one',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('overdue-$seriesId')), findsNothing);
      expect(find.byKey(ValueKey('overdue-${overdueId.id}')), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: card,
          matching: find.text('Complete This Occurrence'),
        ),
      );
      await _settle(tester);

      expect(calls, [(seriesId, 'v2:DATE:2026-10-05', true)]);
      expect(find.byKey(ValueKey('missed-card-$seriesId')), findsNothing);
      expect(find.byKey(ValueKey('overdue-${overdueId.id}')), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('a timed recurring instance shows its clock time, not all day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(2026, 10, 6, 12, 0, 0),
      ),
      timeZone: 'UTC',
      rrule: 'FREQ=DAILY;COUNT=3',
    );
    final seriesId = await _createSeries(
      db,
      calendarId: calendarId,
      summary: 'Timeboxed Review',
      spec: spec,
    );
    final series = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(seriesId))).getSingle();
    final occurrence = expandTodoOccurrences(
      series,
      startInclusive: DateTime(2026, 10, 6),
      endExclusive: DateTime(2026, 10, 7),
      maxOccurrences: 10,
    ).occurrences.single;
    final expected = DateFormatters.formatTime(
      occurrence.resolvedStartInstant!.toLocal(),
    );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Timeboxed Review'), findsNWidgets(2));
    expect(find.text(expected), findsOneWidget);
    expect(find.text('All day'), findsNothing);

    await _unmount(tester);
  });

  testWidgets(
    'desktop unplanned panel previews three and opens the full view',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (var i = 1; i <= 5; i++) {
        await db
            .into(db.todos)
            .insert(
              TodosCompanion.insert(calendarId: calendarId, summary: 'Task $i'),
            );
      }
      var openedUnplanned = 0;

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onOpenUnplanned: () => openedUnplanned++,
        ),
      );
      await _settle(tester);

      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Task 2'), findsOneWidget);
      expect(find.text('Task 3'), findsOneWidget);
      expect(find.text('Task 4'), findsNothing);
      expect(find.text('Task 5'), findsNothing);
      expect(find.text('View 2 undated'), findsOneWidget);

      await tester.tap(find.text('View 2 undated'));
      await _settle(tester);
      expect(openedUnplanned, 1);

      await _unmount(tester);
    },
  );

  testWidgets('a lone overdue item keeps its section and no empty box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Old rent',
            dueDate: Value(DateTime(2026, 10, 1, 10)),
          ),
        );

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    // Spec: the empty 70px placeholder is gone; mobileTimeSections always keeps Now + now-line + Upcoming 0.
    expect(find.text('Nothing scheduled today'), findsNothing);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Old rent'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Due today'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('upcoming collapses past three and expands', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (var i = 1; i <= 5; i++) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: 'Meeting $i',
              startDt: DateTime(2026, 10, 6, 15 + i),
              endDt: DateTime(2026, 10, 6, 15 + i, 30),
              isAllDay: const Value(false),
            ),
          );
    }

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    // T2: the upcoming section uses the shelf's exact preview language.
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Meeting 1'), findsOneWidget);
    expect(find.text('Meeting 2'), findsOneWidget);
    expect(find.text('Meeting 3'), findsOneWidget);
    expect(find.text('Meeting 4'), findsNothing);
    expect(find.text('Meeting 5'), findsNothing);
    expect(find.text('2 more · Show all'), findsOneWidget);

    await tester.tap(find.text('2 more · Show all'));
    await _settle(tester);
    expect(find.text('Meeting 4'), findsOneWidget);
    expect(find.text('Meeting 5'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('now never collapses past three blocks', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (var i = 1; i <= 4; i++) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: 'Running $i',
              startDt: DateTime(2026, 10, 6, 14),
              endDt: DateTime(2026, 10, 6, 16),
              isAllDay: const Value(false),
            ),
          );
    }

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Now'), findsOneWidget);
    for (var i = 1; i <= 4; i++) {
      expect(find.text('Running $i'), findsOneWidget);
    }
    expect(find.textContaining('more · Show all'), findsNothing);
    expect(find.text('Show less'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('overdue collapses past three and expands', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (var i = 1; i <= 5; i++) {
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Old $i',
              dueDate: Value(DateTime(2026, 10, i, 10)),
            ),
          );
    }

    var openedAll = false;
    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onOpenAll: () => openedAll = true,
      ),
    );
    await _settle(tester);

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Old 1'), findsOneWidget);
    expect(find.text('Old 2'), findsOneWidget);
    expect(find.text('Old 3'), findsOneWidget);
    expect(find.text('Old 4'), findsNothing);
    expect(find.text('Old 5'), findsNothing);
    expect(find.text('View all 5 items'), findsOneWidget);

    await tester.tap(find.text('View all 5 items'));
    await _settle(tester);
    expect(openedAll, isTrue);
    expect(find.text('Old 4'), findsNothing);
    expect(find.text('Old 5'), findsNothing);

    await _unmount(tester);
  });

  testWidgets(
    'a merged allocation tick completes the todo and records the due',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final id = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Weekly notes',
              dueDate: Value(DateTime(2026, 10, 6, 18)),
            ),
          );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await container.read(createTaskAllocationProvider)(
        todoId: id,
        startAt: DateTime(2026, 10, 6, 16),
        endAt: DateTime(2026, 10, 6, 17),
      );
      container.dispose();

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onToggleTodo: (todo, occurrenceId, completed) =>
              _completeInDb(db, todo, occurrenceId, completed),
        ),
      );
      await _settle(tester);

      expect(find.text('Weekly notes'), findsOneWidget);
      // Per requirement 7: mobile time block has no checkbox
      final check = find.descendant(
        of: find.byType(SpecTimeBlock),
        matching: find.byType(DsCheck),
      );
      expect(check, findsNothing);

      expect(
        find.descendant(
          of: find.byType(SpecTimeBlock),
          matching: find.textContaining('Due 18:00'),
        ),
        findsOneWidget,
      );

      await _unmount(tester);
    },
  );

  testWidgets(
    'a completed deadline stays in place with undo for five seconds',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // The completion writer stamps the real clock, so this test runs on the
      // real day for the record to land in Completed Today.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Pay bill',
              dueDate: Value(today),
            ),
          );

      await tester.pumpWidget(
        _app(
          now: now,
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => today),
          ],
          onToggleTodo: (todo, occurrenceId, completed) =>
              _completeInDb(db, todo, occurrenceId, completed),
        ),
      );
      await _settle(tester);

      final check = find.byWidgetPredicate(
        (widget) => widget is DsCheck && widget.label == 'Pay bill',
      );
      await tester.tap(check);
      await _settle(tester);

      // T4/D3: the projection has dropped the row, but it stays where it stood
      // with an inline undo key; the completed fold does not duplicate it yet.
      expect(find.text('Pay bill'), findsOneWidget);
      expect(find.text('Undo'), findsNWidgets(2));
      expect(find.text('Completed Today'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);

      // R6: after the window the record moves to the folded completed section.
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Pay bill'), findsNothing);
      expect(find.text('Completed Today'), findsOneWidget);
      expect(find.text('Due today'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets(
    'an occurrence completion offers an undo bound to that occurrence',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDate(2026, 10, 6),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=3',
      );
      await _createSeries(
        db,
        calendarId: calendarId,
        summary: 'Daily Review',
        spec: spec,
      );
      final calls = <(int, String?, bool)>[];

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onToggleTodo: (todo, occurrenceId, completed) async {
            calls.add((todo.id, occurrenceId, completed));
            return true;
          },
        ),
      );
      await _settle(tester);

      // Target the timeline block bound to the concrete occurrence.
      // Mobile time block has no checkbox per requirement 7
      final instanceCheck = find.descendant(
        of: find.byType(SpecTimeBlock),
        matching: find.byType(DsCheck),
      );
      expect(instanceCheck, findsNothing);
      expect(
        find.descendant(
          of: find.byType(SpecTimeBlock),
          matching: find.text('Daily Review'),
        ),
        findsOneWidget,
      );

      await _unmount(tester);
    },
  );

  testWidgets(
    'completing refreshes the unplanned count without leaving Today',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'Task A'),
          );
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'Task B'),
          );

      await tester.pumpWidget(
        _app(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
          onToggleTodo: (todo, occurrenceId, completed) =>
              _completeInDb(db, todo, occurrenceId, completed),
        ),
      );
      await _settle(tester);

      expect(find.text('Nothing scheduled today'), findsNothing);
      expect(find.text('2'), findsOneWidget);

      final check = find.byWidgetPredicate(
        (widget) => widget is DsCheck && widget.label == 'Task A',
      );
      await tester.tap(check);
      await _settle(tester);

      // R5: the projection was re-read in place, so the shelf count already
      // reflects the completion while the row is still held for undo.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Undo'), findsNWidgets(2));

      // Any other interaction closes the window without waiting out the timer.
      await tester.tap(find.text('Task B'));
      await _settle(tester);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Task A'), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets('ticking an ended allocation keeps it in Earlier today only', (
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
            summary: 'Morning review',
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: id,
      startAt: DateTime(2026, 10, 6, 12),
      endAt: DateTime(2026, 10, 6, 13),
    );
    container.dispose();

    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => day),
        ],
        onToggleTodo: (todo, occurrenceId, completed) =>
            _completeInDb(db, todo, occurrenceId, completed),
      ),
    );
    await _settle(tester);

    expect(find.text('Earlier today'), findsOneWidget);
    // Earlier today is collapsed by default on mobile
    expect(find.text('Morning review'), findsNothing);

    // Expand Earlier today
    await tester.tap(find.text('Earlier today'));
    await _settle(tester);

    expect(find.text('Morning review'), findsOneWidget);
    // Per requirement 7: mobile time block has no checkbox
    final check = find.descendant(
      of: find.byType(SpecTimeBlock),
      matching: find.byType(DsCheck),
    );
    expect(check, findsNothing);

    await _unmount(tester);
  });

  testWidgets(
    'desktop Today: an allocated todo appears only once (timeline only, not task col)',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final plannedId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Planned Task',
              dueDate: Value(DateTime(2026, 10, 6, 18)),
            ),
          );

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Unplanned Task',
            ),
          );

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await container.read(createTaskAllocationProvider)(
        todoId: plannedId,
        startAt: DateTime(2026, 10, 6, 15),
        endAt: DateTime(2026, 10, 6, 16),
      );
      container.dispose();

      await tester.pumpWidget(
        _app(
          now: DateTime(2026, 10, 6, 14),
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
        ),
      );
      await _settle(tester);

      // P0 1: One todo appears only once today!
      expect(find.text('Planned Task'), findsOneWidget);
      expect(find.text('Unplanned Task'), findsOneWidget);

      // Planned Task is in the time column via SpecTimeBlock, not left SpecTaskRow
      expect(find.byType(SpecTimeBlock), findsWidgets);
      final timeBlockFinder = find.ancestor(
        of: find.text('Planned Task'),
        matching: find.byType(SpecTimeBlock),
      );
      expect(timeBlockFinder, findsOneWidget);

      final taskRowFinder = find.ancestor(
        of: find.text('Planned Task'),
        matching: find.byType(SpecTaskRow),
      );
      expect(taskRowFinder, findsNothing);

      // Unplanned Task is in left task column via SpecTaskRow
      final unplannedRowFinder = find.ancestor(
        of: find.text('Unplanned Task'),
        matching: find.byType(SpecTaskRow),
      );
      expect(unplannedRowFinder, findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets(
    'desktop Today: asserts day head vertical layout, timeline, now line, and floating capture bar',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          now: DateTime(2026, 10, 6, 14),
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionDateProvider.overrideWith((ref) => day),
          ],
        ),
      );
      await _settle(tester);

      // Day head: title, subtitle with week number, summary
      expect(find.text('Oct 6'), findsOneWidget);
      expect(find.textContaining('Week 41'), findsOneWidget);

      // Timeline components
      expect(find.byType(SpecNowLine), findsOneWidget);

      // Floating capture bar
      expect(find.byKey(const ValueKey('desktop-capture-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-capture-expand-btn')), findsOneWidget);

      // Expanding the desktop capture bar opens the 12-state A2CapturePanel
      await tester.tap(find.byKey(const ValueKey('desktop-capture-expand-btn')));
      await _settle(tester);

      expect(find.byType(A2CapturePanel), findsOneWidget);
      expect(find.text('待办标题'), findsOneWidget);
      expect(find.text('截止'), findsOneWidget);
      expect(find.text('计划执行'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('提醒'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(A2CapturePanel), findsNothing);

      await _unmount(tester);
    },
  );
}
