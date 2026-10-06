import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
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
  overrides: [
    if (db != null) databaseProvider.overrideWithValue(db),
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
    home: Scaffold(body: child),
  ),
);

Todo _makeTodo({
  required int id,
  required String summary,
  DateTime? dueDate,
}) {
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

  testWidgets('renders Create Event and Schedule Todo options', (tester) async {
    var eventCreated = false;
    Todo? scheduledTodo;

    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () => eventCreated = true,
          onScheduleTodo: (todo) async => scheduledTodo = todo,
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsOneWidget);
    expect(find.text('Schedule Todo'), findsOneWidget);

    await tester.tap(find.text('Create Event'));
    await tester.pumpAndSettle();

    expect(eventCreated, isTrue);
    expect(scheduledTodo, isNull);
  });

  testWidgets('Schedule Todo shows candidates and calls onScheduleTodo on tap', (
    tester,
  ) async {
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
          onScheduleTodo: (todo) async => scheduledTodo = todo,
          loadSchedulableTodos: () async => [candidate],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Schedule Todo
    await tester.tap(find.text('Schedule Todo'));
    await tester.pumpAndSettle();

    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('Prepare slides'), findsOneWidget);

    // Tap candidate
    await tester.tap(find.text('Prepare slides'));
    await tester.pumpAndSettle();

    expect(scheduledTodo, isNotNull);
    expect(scheduledTodo!.id, 42);
    expect(scheduledTodo!.summary, 'Prepare slides');
  });

  testWidgets('Schedule Todo shows empty message when no schedulable todos exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          range: testRange,
          onCreateEvent: () {},
          onScheduleTodo: (todo) async {},
          loadSchedulableTodos: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule Todo'));
    await tester.pumpAndSettle();

    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('No pending todos available to schedule'), findsOneWidget);
  });

  testWidgets('Schedule recurring Todo opens occurrence picker and passes occurrenceId', (
    tester,
  ) async {
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
    final recurringTodo = await (db.select(db.todos)..where((t) => t.id.equals(insertedId))).getSingle();

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

    // Tap Schedule Todo
    await tester.tap(find.text('Schedule Todo'));
    await tester.pumpAndSettle();

    expect(find.text('Select Todo to Schedule'), findsOneWidget);
    expect(find.text('Daily Standup'), findsOneWidget);
    expect(find.text('Recurring'), findsOneWidget);

    // Tap recurring candidate -> opens TodoOccurrencePickerSheet
    await tester.tap(find.text('Daily Standup'));
    await tester.pumpAndSettle();

    expect(find.text('Select occurrence'), findsOneWidget);
    final occurrenceTile = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ListTile),
    ).first;
    expect(occurrenceTile, findsOneWidget);

    // Tap first occurrence item in dialog
    await tester.tap(occurrenceTile);
    await tester.pumpAndSettle();

    // Verify scheduledTodo and scheduledOccurrenceId are populated
    expect(scheduledTodo, isNotNull);
    expect(scheduledTodo!.id, recurringTodo.id);
    expect(scheduledOccurrenceId, isNotNull);
    expect(scheduledOccurrenceId, startsWith('v2:DATE:'));
  });
}

