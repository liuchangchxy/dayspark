import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

Widget _wrapWithApp({
  required Widget child,
  required List<Override> overrides,
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
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late int calendarId;
  final fixedDate = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('renders empty state when projection is empty', (tester) async {
    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    // Pump to settle drift stream providers
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('No events, scheduled tasks, or deadlines for today.'),
      findsOneWidget,
    );
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('0 unplanned'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('visually distinguishes Event, Planned Allocation, and Deadline', (
    tester,
  ) async {
    // 1. Event
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Client Call',
            startDt: DateTime(2026, 10, 6, 10, 0),
            endDt: DateTime(2026, 10, 6, 11, 0),
            isAllDay: const Value(false),
          ),
        );

    // 2. Ordinary Todo with TaskAllocation
    final scheduledTodoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Write Spec',
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: scheduledTodoId,
      startAt: DateTime(2026, 10, 6, 14, 0),
      endAt: DateTime(2026, 10, 6, 15, 30),
    );
    container.dispose();

    // 3. Ordinary Todo due today
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Submit Invoice',
            dueDate: Value(DateTime(2026, 10, 6, 18, 0)),
          ),
        );

    // 4. Overdue Todo with past deadline
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Fix Bug',
            dueDate: Value(DateTime(2026, 10, 2, 9, 0)),
          ),
        );

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Overdue section
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Fix Bug'), findsOneWidget);
    expect(find.text('Deadline: 2026-10-02'), findsOneWidget);

    // Today's schedule section
    expect(find.text("Today's Schedule"), findsOneWidget);
    expect(find.text('Client Call'), findsOneWidget);
    expect(find.text('10:00 – 11:00 · Event'), findsOneWidget);

    expect(find.text('Write Spec'), findsOneWidget);
    expect(find.text('14:00 – 15:30 · Planned'), findsOneWidget);

    // Due Today section
    expect(find.text('Due Today (1)'), findsOneWidget);
    expect(find.text('Submit Invoice'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('checking allocation checkbox completes ordinary todo without mutating dueDate', (
    tester,
  ) async {
    final originalDueDate = DateTime(2026, 10, 6, 23, 59);
    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Ship Feature',
            dueDate: Value(originalDueDate),
          ),
        );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await container.read(createTaskAllocationProvider)(
      todoId: todoId,
      startAt: DateTime(2026, 10, 6, 9, 0),
      endAt: DateTime(2026, 10, 6, 10, 0),
    );
    container.dispose();

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Find checkbox in today's schedule for Ship Feature and tap it
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsWidgets);

    // Tap the first checkbox (Ship Feature in timeline)
    await tester.tap(checkboxes.first);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify in DB that the todo is COMPLETED and dueDate is UNMUTED
    final updatedTodo = await (db.select(db.todos)
          ..where((t) => t.id.equals(todoId)))
        .getSingle();
    expect(updatedTodo.status, 'COMPLETED');
    expect(updatedTodo.dueDate, originalDueDate);

    await _unmount(tester);
  });

  testWidgets('tapping Inbox card invokes onNavigateToTodos callback', (
    tester,
  ) async {
    var navigated = false;
    await tester.pumpWidget(
      _wrapWithApp(
        child: ActionSection(
          onNavigateToTodos: () => navigated = true,
        ),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Inbox'));
    await tester.pump();

    expect(navigated, isTrue);

    await _unmount(tester);
  });

  testWidgets('Phase 2: renders today recurring instance and checkbox completes exact instance', (
    tester,
  ) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final occId = 'v2:DATE:$todayStr';

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(today.year, today.month, today.day),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Daily Yoga',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => todayDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Daily Yoga'), findsOneWidget);
    expect(find.text("Today's Tasks (1)"), findsOneWidget);

    // Find and tap the checkbox for Daily Yoga
    final checkbox = find.byType(Checkbox);
    expect(checkbox, findsOneWidget);
    await tester.tap(checkbox);

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify parent series remains NEEDS-ACTION
    final parent = await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
    expect(parent.status, 'NEEDS-ACTION');

    // Verify taskInstanceState has completed
    final state = await (db.select(db.taskInstanceStates)
          ..where((s) => s.todoSyncId.equals(parent.syncId!) & s.occurrenceId.equals(occId)))
        .getSingle();
    expect(state.status, 'completed');

    // Verify UI moved Daily Yoga into Completed Today
    expect(find.text('Completed Today (1)'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Phase 2 regression: earlier missed tiles carry exact series identity for multiple series', (
    tester,
  ) async {
    final specA = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 8, 20),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=5',
    );
    final seriesAId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Series Alpha',
          rrule: Value(specA.rule.canonical),
        ),
        recurrenceSpec: specA,
      ),
    );

    final specB = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 8, 20),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=5',
    );
    final seriesBId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Series Beta',
          rrule: Value(specB.rule.canonical),
        ),
        recurrenceSpec: specB,
      ),
    );

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(ValueKey('earlier-missed-$seriesAId')), findsOneWidget);
    expect(find.byKey(ValueKey('earlier-missed-$seriesBId')), findsOneWidget);
    expect(find.text('Earlier missed… · Series Alpha'), findsOneWidget);
    expect(find.text('Earlier missed… · Series Beta'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Phase 2 regression: expansion failure shows dedicated error tile without legacy confirmation card', (
    tester,
  ) async {
    await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: 'Corrupted Series',
        rrule: const Value('INVALID'),
        recurrenceLegacyState: const Value('knownZoned'),
        recurrenceRule: const Value('INVALID'),
        recurrenceAnchorSource: const Value('due'),
        recurrenceValueType: const Value('date'),
        recurrenceAnchorValue: const Value('2026-10-06'),
        recurrenceTimeZone: const Value('UTC'),
      ),
    );

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
        ],
      ),
    );

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Corrupted Series'), findsOneWidget);
    expect(find.textContaining('need confirmation'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('Phase 2 regression: earlier history tile renders distinct key and label for unprobed series', (
    tester,
  ) async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2024, 7, 28),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Ancient Habit',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );
    final series = await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();

    await tester.pumpWidget(
      _wrapWithApp(
        child: const ActionSection(),
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDateProvider.overrideWith((ref) => fixedDate),
          actionProjectionProvider.overrideWith(
            (ref) => AsyncValue.data(
              ActionProjectionData(
                earlierHistorySeries: [series],
                hasEarlierHistory: true,
              ),
            ),
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('earlier-history-$seriesId')), findsOneWidget);
    expect(find.text('Earlier history… · Ancient Habit'), findsOneWidget);

    await _unmount(tester);
  });
}
