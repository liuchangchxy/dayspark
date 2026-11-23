import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

Widget _wrap(Widget child, [AppDatabase? db]) => ProviderScope(
  overrides: [if (db != null) databaseProvider.overrideWithValue(db)],
  child: MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  ),
);

Todo _makeTodo({required int id, required String summary, DateTime? dueDate}) {
  final now = DateTime.now();
  return Todo(
    id: id,
    calendarId: 1,
    summary: summary,
    priority: 0,
    status: 'NEEDS-ACTION',
    dueDate: dueDate,
    sortOrder: 0,
    recurrenceRevision: 0,
    percentComplete: 0,
    createdAt: now,
    updatedAt: now,
    serverRev: 0,
  );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final testRange = DateTimeRange(
    start: DateTime(2026, 10, 6, 10, 0),
    end: DateTime(2026, 10, 6, 11, 0),
  );

  testWidgets('the head states the date, then the span and its source', (
    tester,
  ) async {
    var eventCreated = false;
    Todo? scheduledTodo;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () => eventCreated = true,
          onScheduleTodo: (todo, _) async => scheduledTodo = todo,
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Event'), findsOneWidget);
    expect(find.text('Schedule Task'), findsOneWidget);
    // The date is the fact; it owns the first line.
    expect(find.text('October 6 · Tue'), findsOneWidget);
    // The span is an inferred default, so it says so on the second line.
    expect(find.text('10:00–11:00 · 1 h · default, editable'), findsOneWidget);

    await tester.tap(find.text('New Event'));
    await tester.pumpAndSettle();

    expect(eventCreated, isTrue);
    expect(scheduledTodo, isNull);
  });

  testWidgets('an existing block states its span as a fact', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          isExistingBlock: true,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('10:00–11:00 · Existing event'), findsOneWidget);
    expect(find.textContaining('Duration'), findsNothing);
  });

  testWidgets('the three actions step down in weight, heaviest last', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => [_makeTodo(id: 1, summary: 'A')],
          onCreateTodoHere: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final eventRow = tester.getTopLeft(find.text('New Event')).dy;
    final createRow = tester.getTopLeft(find.text('New & schedule')).dy;
    final scheduleRow = tester.getTopLeft(find.text('Schedule Task')).dy;
    expect(eventRow, lessThan(createRow));
    expect(createRow, lessThan(scheduleRow));

    // Only "New Event" is filled; the shortcut is outlined; the heaviest
    // action is plain text.
    final solid = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('New Event'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (solid.decoration! as BoxDecoration).color,
      isNot(Colors.transparent),
    );
    expect(find.byKey(const ValueKey('slot-schedule-count')), findsOneWidget);
  });

  testWidgets('the schedule row carries the unplanned count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => [
            _makeTodo(id: 1, summary: 'A'),
            _makeTodo(id: 2, summary: 'B'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('slot-schedule-count')),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('slot-schedule-count')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(badge, isNotNull);
  });

  testWidgets('the create-and-schedule row is offered when the caller can', (
    tester,
  ) async {
    var created = false;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => [],
          onCreateTodoHere: () => created = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final createRow = find.byKey(
      const ValueKey('slot-action-create-schedule'),
    );
    expect(createRow, findsOneWidget);
    await tester.tap(createRow);
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets('an empty candidate list disables the row and says why', (
    tester,
  ) async {
    var scheduled = false;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async => scheduled = true,
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No pending tasks available to schedule'), findsOneWidget);
    await tester.tap(find.text('Schedule Task'));
    await tester.pumpAndSettle();

    // Nothing to pick, so the row never opens a second sheet.
    expect(find.text('Select a Task to Schedule'), findsNothing);
    expect(scheduled, isFalse);
    // The primary action is untouched by the empty candidate list.
    expect(find.text('New Event'), findsOneWidget);
  });

  testWidgets('a failed candidate load stays on its own row and can retry', (
    tester,
  ) async {
    var calls = 0;
    final candidate = _makeTodo(
      id: 42,
      summary: 'Prepare slides',
      dueDate: DateTime(2026, 10, 8),
    );

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async {
            calls++;
            if (calls == 1) throw StateError('boom');
            return [candidate];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('That didn\'t work. Please try again.'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-schedule-retry')), findsOneWidget);
    expect(find.text('No pending tasks available to schedule'), findsNothing);
    // The failure is isolated: the primary action is still on screen.
    expect(find.text('New Event'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-schedule-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Prepare slides'), findsNothing);
    await tester.tap(find.text('Schedule Task'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare slides'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a failed candidate load never blocks creating an event', (
    tester,
  ) async {
    var eventCreated = false;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () => eventCreated = true,
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => throw StateError('boom'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('That didn\'t work. Please try again.'), findsOneWidget);
    await tester.tap(find.text('New Event'));
    await tester.pumpAndSettle();
    expect(eventCreated, isTrue);
  });

  testWidgets(
    'Schedule Todo shows candidates and calls onScheduleTodo on tap',
    (tester) async {
      Todo? scheduledTodo;
      final candidate = _makeTodo(
        id: 42,
        summary: 'Prepare slides',
        dueDate: DateTime(2026, 10, 8),
      );

      await tester.pumpWidget(
        _wrap(
          CalendarSlotSheet(
            range: testRange,
            onCreateEvent: () {},
            onScheduleTodo: (todo, _) async => scheduledTodo = todo,
            loadSchedulableTodos: () async => [candidate],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Schedule Task'));
      await tester.pumpAndSettle();

      expect(find.text('Select a Task to Schedule'), findsOneWidget);
      // The picker repeats the resolved span so the target is never guessed.
      expect(find.textContaining('10:00–11:00'), findsOneWidget);
      expect(find.text('Prepare slides'), findsOneWidget);

      await tester.tap(find.text('Prepare slides'));
      await tester.pumpAndSettle();

      expect(scheduledTodo, isNotNull);
      expect(scheduledTodo!.id, 42);
      expect(scheduledTodo!.summary, 'Prepare slides');
    },
  );

  testWidgets('an empty picker points at creating a task instead', (
    tester,
  ) async {
    var created = false;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => [],
          onCreateTodoHere: () => created = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('slot-empty-create-schedule')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('slot-empty-create-schedule')));
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets(
    'Schedule recurring Todo opens occurrence picker and passes occurrenceId',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() => db.close());

      final cal = await db.select(db.calendars).getSingle();
      final now = DateTime.now();
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDate(now.year, now.month, now.day),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=5',
      );
      final insertedId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: cal.id,
            summary: 'Daily Standup',
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );
      final recurringTodo = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(insertedId))).getSingle();

      Todo? scheduledTodo;
      String? scheduledOccurrenceId;

      await tester.pumpWidget(
        _wrap(
          CalendarSlotSheet(
            range: testRange,
            onCreateEvent: () {},
            onScheduleTodo: (todo, [occurrenceId]) async {
              scheduledTodo = todo;
              scheduledOccurrenceId = occurrenceId;
            },
            loadSchedulableTodos: () async => [recurringTodo],
          ),
          db,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Schedule Task'));
      await tester.pumpAndSettle();

      expect(find.text('Select a Task to Schedule'), findsOneWidget);
      expect(find.text('Daily Standup'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);

      await tester.tap(find.text('Daily Standup'));
      await tester.pumpAndSettle();

      expect(find.text('Select occurrence'), findsOneWidget);
      final occurrenceTile = find
          .descendant(
            of: find.byType(DsDialog),
            matching: find.byType(DsSettingRow),
          )
          .first;
      expect(occurrenceTile, findsOneWidget);

      await tester.tap(occurrenceTile);
      await tester.pumpAndSettle();

      expect(scheduledTodo, isNotNull);
      expect(scheduledTodo!.id, recurringTodo.id);
      expect(scheduledOccurrenceId, isNotNull);
      expect(scheduledOccurrenceId, startsWith('v2:DATE:'));
    },
  );
}
