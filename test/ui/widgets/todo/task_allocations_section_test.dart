import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/task_allocations_section.dart';
import 'package:dayspark/ui/pages/todo/todo_edit_page.dart';
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
          home: Scaffold(body: TaskAllocationsSection(todo: todo)),
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

    expect(find.text('Schedule time'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('legacy recurring Todo is blocked with a clear explanation', (
    tester,
  ) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Weekly review',
            rrule: const Value('FREQ=WEEKLY;BYDAY=MO'),
            recurrenceLegacyState: const Value('unknownLegacy'),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    await pumpSection(tester, todo);

    expect(find.text('Schedule time'), findsOneWidget);
    await tester.tap(find.text('Schedule time'));
    await tester.pumpAndSettle();
    expect(
      find.text('Confirm this recurrence before scheduling an occurrence.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('recurring Todo edit page exposes occurrence scheduling', (
    tester,
  ) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Weekly review',
            rrule: const Value('FREQ=WEEKLY;BYDAY=MO'),
            recurrenceLegacyState: const Value('unknownLegacy'),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TodoEditPage(todo: todo)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(TaskAllocationsSection), findsOneWidget);
    expect(find.text('Schedule time'), findsOneWidget);
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
    await tester.tap(find.text('Schedule time'));
    await tester.pumpAndSettle();
    expect(find.text('Select occurrence'), findsOneWidget);
    expect(find.textContaining('2030'), findsNothing);
    expect(find.byType(SimpleDialogOption), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
