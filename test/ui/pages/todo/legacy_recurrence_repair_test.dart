import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  Future<void> pumpForm(WidgetTester tester, Todo todo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TodoFormPage(todo: todo),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Unmount and flush pending timers before teardown; the form owns text
  // controllers and a dialog that would otherwise outlive the tree.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Todo> insertLegacy(
    int id, {
    required String rrule,
    DateTime? startDate,
    String? evidence,
  }) async {
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            id: Value(id),
            calendarId: calendarId,
            summary: 'Weekly review',
            startDate: Value.absentIfNull(startDate),
            rrule: Value(rrule),
            recurrenceLegacyState: const Value('unknownLegacy'),
            recurrenceEvidence: Value.absentIfNull(evidence),
          ),
        );
    return (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();
  }

  testWidgets('legacy Todo is offered a one-time repair from the form', (
    tester,
  ) async {
    final todo = await insertLegacy(
      1,
      rrule: 'FREQ=WEEKLY;BYDAY=MO',
      startDate: DateTime(2026, 10, 5, 9),
    );

    await pumpForm(tester, todo);

    expect(
      find.text('Some repeating todos need a one-time fix'),
      findsNWidgets(2),
    );
    await tester.tap(
      find.text('Some repeating todos need a one-time fix').last,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Confirm recurring Todo'), findsOneWidget);
    // The repair asks for the day the series repeats from and nothing else:
    // the rule string, the import evidence and the zone id are not questions
    // a person can answer.
    expect(
      find.textContaining('imported before the app recorded'),
      findsOneWidget,
    );
    expect(find.textContaining('FREQ='), findsNothing);
    expect(find.text('Series time zone'), findsNothing);
    await unmount(tester);
  });

  testWidgets('legacy confirmation persists only after the user confirms', (
    tester,
  ) async {
    final todo = await insertLegacy(
      2,
      rrule: 'FREQ=WEEKLY;COUNT=4',
      startDate: DateTime(2026, 10, 5, 9),
      evidence: const LegacyRecurrenceEvidence(
        source: 'ics',
        timeSemantic: 'vtimezoneConflict',
        rawTzid: 'America/New_York',
        hasVTimezone: true,
      ).encode(),
    );

    await pumpForm(tester, todo);
    await tester.tap(
      find.text('Some repeating todos need a one-time fix').last,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Confirm recurring Todo'), findsOneWidget);
    expect(find.textContaining('vtimezoneConflict'), findsNothing);
    expect(find.textContaining('VTIMEZONE data'), findsNothing);
    expect(find.text('Repeats from'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Next occurrences (preview)'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final confirmed = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(2))).getSingle();
    expect(confirmed.recurrenceLegacyState, 'knownZoned');
    // The imported series keeps the zone it was imported in; the device zone
    // would move every occurrence.
    expect(confirmed.recurrenceTimeZone, 'America/New_York');
    expect(confirmed.recurrenceAnchorValue, '2026-10-05T09:00:00');
    await unmount(tester);
  });

  testWidgets('legacy confirmation falls back to the device zone', (
    tester,
  ) async {
    final todo = await insertLegacy(
      4,
      rrule: 'FREQ=WEEKLY;COUNT=4',
      startDate: DateTime(2026, 10, 5, 9),
    );

    await pumpForm(tester, todo);
    await tester.tap(
      find.text('Some repeating todos need a one-time fix').last,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Preview'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final confirmed = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(4))).getSingle();
    expect(confirmed.recurrenceLegacyState, 'knownZoned');
    expect(confirmed.recurrenceTimeZone, tz.local.name);
    await unmount(tester);
  });

  testWidgets('unsupported legacy RRULE is reported instead of confirmed', (
    tester,
  ) async {
    final todo = await insertLegacy(
      3,
      rrule: 'NOT-A-RULE',
      startDate: DateTime(2026, 10, 5, 9),
    );

    await pumpForm(tester, todo);

    // A rule the engine cannot interpret gets no repair affordance at all —
    // offering one would write a series the app still cannot expand.
    expect(find.text('A repeating todo cannot be calculated'), findsOneWidget);
    expect(find.text('Some repeating todos need a one-time fix'), findsNothing);
    await unmount(tester);
  });
}
