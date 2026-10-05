import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/task_allocations_section.dart';
import 'package:dayspark/ui/pages/todo/todo_edit_page.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
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

  testWidgets('legacy recurring Todo asks for an explicit interpretation', (
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
    expect(find.text('Confirm recurring Todo'), findsOneWidget);
    expect(find.textContaining('no reliable time zone'), findsOneWidget);
    expect(
      find.textContaining('No import evidence is available'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('legacy confirmation persists only after the user confirms', (
    tester,
  ) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Legacy with date',
            startDate: Value(DateTime(2026, 10, 5, 9)),
            rrule: const Value('FREQ=WEEKLY;COUNT=4'),
            recurrenceLegacyState: const Value('unknownLegacy'),
            recurrenceEvidence: Value(
              const LegacyRecurrenceEvidence(
                source: 'ics',
                timeSemantic: 'vtimezoneConflict',
                rawTzid: 'America/New_York',
                hasVTimezone: true,
              ).encode(),
            ),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    await pumpSection(tester, todo);
    await tester.tap(find.text('Schedule time'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm recurring Todo'), findsOneWidget);
    expect(find.text('Series time zone'), findsOneWidget);
    expect(find.textContaining('vtimezoneConflict'), findsOneWidget);
    expect(find.textContaining('VTIMEZONE data'), findsOneWidget);
    expect(find.text('Series anchor date and time'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Next occurrences (preview)'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final confirmed = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(confirmed.recurrenceLegacyState, 'knownZoned');
    expect(confirmed.recurrenceTimeZone, isNotEmpty);
    expect(confirmed.recurrenceAnchorValue, '2026-10-05T09:00:00');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('unsupported legacy RRULE is blocked before confirmation', (
    tester,
  ) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Unsupported legacy',
            startDate: Value(DateTime(2026, 10, 5, 9)),
            rrule: const Value('FREQ=DAILY;BYHOUR=9'),
            recurrenceLegacyState: const Value('unknownLegacy'),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    await pumpSection(tester, todo);
    await tester.tap(find.text('Schedule time'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('unsupported or invalid syntax'),
      findsOneWidget,
    );
    expect(find.text('Confirm recurring Todo'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('recurring Todo edit page exposes legacy confirmation', (
    tester,
  ) async {
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Weekly review',
            startDate: Value(DateTime.now().subtract(const Duration(days: 1))),
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
    expect(
      find.byKey(const ValueKey('confirm-legacy-recurrence')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('confirm-legacy-recurrence')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm recurring Todo'), findsNWidgets(2));
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Next occurrences (preview)'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final confirmed = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(confirmed.recurrenceLegacyState, 'knownZoned');
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
    expect(find.textContaining('next 90 days'), findsOneWidget);
    expect(find.textContaining('2030'), findsNothing);
    expect(find.byType(SimpleDialogOption), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'known recurrence edit changes series zone without changing anchor',
    (tester) async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2026, 11, 2, 9, 0, 0),
        ),
        timeZone: 'America/New_York',
        rrule: 'FREQ=WEEKLY;COUNT=3',
      );
      final todoId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Zoned review',
            startDate: Value(DateTime.utc(2026, 11, 2, 9)),
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ),
      );
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
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
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('recurrence-time-zone')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final zoneField = tester.widget<TextField>(
        find.byKey(const ValueKey('recurrence-time-zone')),
      );
      expect(zoneField.controller?.text, 'America/New_York');
      expect(find.textContaining('2026-11-02T09:00:00'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('recurrence-time-zone')),
        'Asia/Shanghai',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      expect(saved.recurrenceTimeZone, 'Asia/Shanghai');
      expect(saved.recurrenceAnchorValue, '2026-11-02T09:00:00');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
