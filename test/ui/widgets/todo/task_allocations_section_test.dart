import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  late AppDatabase db;
  late int calendarId;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async => db.close());

  Future<void> pumpSection(WidgetTester tester, Todo todo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ExecutionScheduleSection(todo: todo)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('offers scheduling for a regular Todo', (tester) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Draft'),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    await pumpSection(tester, todo);

    expect(find.text('Scheduled time'), findsOneWidget);
    expect(find.text('Add execution time'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('renders TaskAllocation instants in local time with both dates', (
    tester,
  ) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Draft'),
        );
    final localStart = DateTime(2026, 10, 5, 16);
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    await db
        .into(db.taskAllocations)
        .insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(id),
            startAt: localStart.toUtc(),
            endAt: localStart.add(const Duration(days: 1)).toUtc(),
          ),
        );

    await pumpSection(tester, todo);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(
        DateFormatters.formatTaskAllocationRange(
          localStart.toUtc(),
          localStart.add(const Duration(days: 1)).toUtc(),
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('known recurring Todo opens a finite occurrence selector', (
    tester,
  ) async {
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          9,
          0,
          0,
        ),
      ),
      timeZone: 'UTC',
      rrule: 'FREQ=DAILY',
    );
    final todoId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Daily review',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();
    await pumpSection(tester, todo);
    await tester.tap(find.text('Add execution time'));
    await tester.pumpAndSettle();
    expect(find.text('Select occurrence'), findsOneWidget);
    expect(find.textContaining('next 90 days'), findsOneWidget);
    expect(find.byType(SimpleDialogOption), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
