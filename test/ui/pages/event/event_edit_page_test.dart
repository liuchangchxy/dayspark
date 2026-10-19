import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_edit_page.dart';

/// `/edit` is a child of `/` so `context.pop()` after saving has somewhere to
/// land, exactly like the real router stack.
GoRouter _router(CalendaEventAdapter event) => GoRouter(
  initialLocation: '/edit',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: Center(child: Text('home'))),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (_, __) => EventEditPage(event: event),
        ),
      ],
    ),
  ],
);

Widget _app(AppDatabase db, CalendaEventAdapter event) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp.router(
    routerConfig: _router(event),
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  // Drift broadcast streams never complete, so pump a fixed number of frames
  // instead of pumpAndSettle.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  CalendaEventAdapter e,
) async {
  // The form is a lazy ListView; a phone-sized surface leaves the lower
  // fields unbuilt and taps on them silently miss.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(db, e));
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await _settle(tester);
}

/// Picks [day] in the date picker, scoped to the dialog: the recurrence editor
/// on the page behind it also renders bare numbers like "5".
Future<void> _pickDateOnly(
  WidgetTester tester,
  String label,
  String day,
) async {
  await tester.tap(find.text(label));
  await _settle(tester);
  final dialog = find.byType(DatePickerDialog);
  expect(dialog, findsOneWidget, reason: 'date picker did not open for $label');
  await tester.tap(find.descendant(of: dialog, matching: find.text(day)));
  await tester.pump();
  await tester.tap(find.descendant(of: dialog, matching: find.text('OK')));
  await _settle(tester);
}

/// Same, then accepts the wheel time picker that a timed event asks for next.
Future<void> _pickDate(WidgetTester tester, String label, String day) async {
  await _pickDateOnly(tester, label, day);
  final sheet = find.byType(BottomSheet);
  if (sheet.evaluate().isEmpty) return;
  await tester.tap(find.descendant(of: sheet, matching: find.text('OK')));
  await _settle(tester);
}

Future<int> _seedCalendar(AppDatabase db) =>
    db.into(db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));

/// Seeds one daily series (2026-10-01 09:00–09:30, five occurrences) and
/// returns the adapter for the third occurrence, as the calendar hands it over.
Future<({int id, CalendaEventAdapter occurrence})> _seedSeries(
  AppDatabase db, {
  String rrule = 'RRULE:FREQ=DAILY;COUNT=5',
  String summary = 'Daily standup',
  String? description,
  String? location,
}) async {
  final calId = await _seedCalendar(db);
  final id = await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: summary,
          startDt: DateTime(2026, 10, 1, 9),
          endDt: DateTime(2026, 10, 1, 9, 30),
          description: Value(description),
          location: Value(location),
          rrule: Value(rrule),
        ),
      );
  final rows = await db.select(db.events).get();
  final expanded = expandRecurringEvents(
    rows,
    before: DateTime(2026, 10, 1),
    after: DateTime(2026, 10, 31),
  );
  return (id: id, occurrence: expanded[2]);
}

Future<Event> _row(AppDatabase db, int id) =>
    (db.select(db.events)..where((t) => t.id.equals(id))).getSingle();

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('recurring series edits', () {
    testWidgets('renaming the third occurrence leaves DTSTART/DTEND alone', (
      tester,
    ) async {
      final seeded = await _seedSeries(db);
      final before = await _row(db, seeded.id);
      expect(seeded.occurrence.start, DateTime(2026, 10, 3, 9));

      await _pump(tester, db, seeded.occurrence);
      await tester.enterText(_field('Title'), 'Renamed standup');
      await _save(tester);

      final after = await _row(db, seeded.id);
      expect(after.summary, 'Renamed standup');
      expect(
        after.startDt,
        DateTime(2026, 10, 1, 9),
        reason: 'the tapped occurrence date must never land in DTSTART',
      );
      expect(after.endDt, DateTime(2026, 10, 1, 9, 30));
      expect(after.rrule, before.rrule);
      expect(after.isAllDay, isFalse);
      expect(after.deletedAt, isNull);
      await _unmount(tester);
    });

    testWidgets('clearing description and location actually clears them', (
      tester,
    ) async {
      final seeded = await _seedSeries(
        db,
        description: 'old notes',
        location: 'old room',
      );

      await _pump(tester, db, seeded.occurrence);
      await tester.enterText(_field('Description'), '');
      await tester.enterText(_field('Location'), '');
      await _save(tester);

      final after = await _row(db, seeded.id);
      expect(after.description, isNull);
      expect(after.location, isNull);
      expect(after.startDt, DateTime(2026, 10, 1, 9));
      await _unmount(tester);
    });

    testWidgets('the page says the whole series is what gets edited', (
      tester,
    ) async {
      final seeded = await _seedSeries(db);

      await _pump(tester, db, seeded.occurrence);

      expect(find.textContaining('changes the whole series'), findsOneWidget);
      expect(
        find.textContaining('not supported yet'),
        findsOneWidget,
        reason:
            'the single-occurrence limitation has to be stated, not implied',
      );
      await _unmount(tester);
    });

    testWidgets('the page edits the series start, not the tapped occurrence', (
      tester,
    ) async {
      final seeded = await _seedSeries(db);
      expect(seeded.occurrence.start, DateTime(2026, 10, 3, 9));

      await _pump(tester, db, seeded.occurrence);

      // The tapped occurrence renders at 2026-10-03; the fields must show the
      // row's own DTSTART so the write cannot smuggle the tapped date in.
      expect(find.text('2026-10-01 09:00'), findsOneWidget);
      expect(find.text('2026-10-03 09:00'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a plain event shows no series notice', (tester) async {
      final calId = await _seedCalendar(db);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'One-off',
              startDt: DateTime(2026, 10, 1, 9),
              endDt: DateTime(2026, 10, 1, 10),
            ),
          );
      final row = await _row(db, id);

      await _pump(tester, db, CalendaEventAdapter.fromDrift(row));

      expect(find.textContaining('changes the whole series'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('editing the series start and end sets DTSTART/DTEND exactly', (
      tester,
    ) async {
      final seeded = await _seedSeries(db);

      await _pump(tester, db, seeded.occurrence);

      // Start 2026-10-01 -> 2026-10-05, time kept (09:00).
      await _pickDate(tester, 'Starts at', '5');
      // End 2026-10-01 -> 2026-10-07, time kept (09:30).
      await _pickDate(tester, 'Ends at', '7');

      await _save(tester);

      final after = await _row(db, seeded.id);
      expect(after.startDt, DateTime(2026, 10, 5, 9));
      expect(after.endDt, DateTime(2026, 10, 7, 9, 30));
      expect(after.rrule, 'RRULE:FREQ=DAILY;COUNT=5');
      await _unmount(tester);
    });

    testWidgets('changing the recurrence rule keeps the series anchor', (
      tester,
    ) async {
      final seeded = await _seedSeries(db);

      await _pump(tester, db, seeded.occurrence);

      // Switch Daily -> Weekly through the real rule editor.
      await tester.tap(find.text('Daily').last);
      await _settle(tester);
      await tester.tap(find.text('Weekly').last);
      await _settle(tester);
      await _save(tester);

      final after = await _row(db, seeded.id);
      expect(after.rrule, contains('FREQ=WEEKLY'));
      expect(
        after.startDt,
        DateTime(2026, 10, 1, 9),
        reason: 'changing the rule must not move the time base',
      );
      expect(after.endDt, DateTime(2026, 10, 1, 9, 30));
      await _unmount(tester);
    });

    testWidgets('deleting says the whole series goes, and takes the row', (
      tester,
    ) async {
      final seeded = await _seedSeries(db);

      await _pump(tester, db, seeded.occurrence);
      await tester.tap(find.byIcon(CupertinoIcons.delete));
      await _settle(tester);

      expect(
        find.textContaining('whole recurring series'),
        findsOneWidget,
        reason: 'the dialog must not read as "delete this one occurrence"',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await _settle(tester);

      final after = await _row(db, seeded.id);
      expect(after.deletedAt, isNotNull);
      final all = await db.select(db.events).get();
      expect(all.length, 1, reason: 'a series is one row, not five');
      await _unmount(tester);
    });

    testWidgets('cancelling the edit writes nothing', (tester) async {
      final seeded = await _seedSeries(db);
      final before = await _row(db, seeded.id);

      await _pump(tester, db, seeded.occurrence);
      await tester.enterText(_field('Title'), 'Discarded');
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await _settle(tester);

      final after = await _row(db, seeded.id);
      expect(after.summary, before.summary);
      expect(after.startDt, before.startDt);
      expect(after.endDt, before.endDt);
      expect(after.updatedAt, before.updatedAt);
      await _unmount(tester);
    });

    testWidgets('editing the series row itself keeps its anchor', (
      tester,
    ) async {
      final calId = await _seedCalendar(db);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Daily standup',
              startDt: DateTime(2026, 10, 1, 9),
              endDt: DateTime(2026, 10, 1, 9, 30),
              rrule: const Value('RRULE:FREQ=DAILY;COUNT=5'),
            ),
          );
      final rows = await db.select(db.events).get();
      final series = CalendaEventAdapter.fromDrift(rows.single);

      await _pump(tester, db, series);
      await tester.enterText(_field('Title'), 'Renamed series');
      await _save(tester);

      final after = await _row(db, id);
      expect(after.summary, 'Renamed series');
      expect(after.startDt, DateTime(2026, 10, 1, 9));
      expect(after.endDt, DateTime(2026, 10, 1, 9, 30));
      expect(after.rrule, 'RRULE:FREQ=DAILY;COUNT=5');
      await _unmount(tester);
    });
  });

  group('plain event edits', () {
    testWidgets('title-only edit leaves times and rule untouched', (
      tester,
    ) async {
      final calId = await _seedCalendar(db);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Dentist',
              startDt: DateTime(2026, 10, 5, 14),
              endDt: DateTime(2026, 10, 5, 15),
            ),
          );
      final row = await _row(db, id);

      await _pump(tester, db, CalendaEventAdapter.fromDrift(row));
      await tester.enterText(_field('Title'), 'Dentist (moved)');
      await _save(tester);

      final after = await _row(db, id);
      expect(after.summary, 'Dentist (moved)');
      expect(after.startDt, DateTime(2026, 10, 5, 14));
      expect(after.endDt, DateTime(2026, 10, 5, 15));
      expect(after.rrule, isNull);
      await _unmount(tester);
    });

    testWidgets('a plain event still moves when its dates are edited', (
      tester,
    ) async {
      final calId = await _seedCalendar(db);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Dentist',
              startDt: DateTime(2026, 10, 5, 14),
              endDt: DateTime(2026, 10, 5, 15),
            ),
          );
      final row = await _row(db, id);

      await _pump(tester, db, CalendaEventAdapter.fromDrift(row));
      await _pickDate(tester, 'Starts at', '9');
      await _pickDate(tester, 'Ends at', '9');
      await _save(tester);

      final after = await _row(db, id);
      expect(after.startDt, DateTime(2026, 10, 9, 14));
      expect(after.endDt, DateTime(2026, 10, 9, 15));
      await _unmount(tester);
    });

    testWidgets('an end before the start is refused for a plain event too', (
      tester,
    ) async {
      final calId = await _seedCalendar(db);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Dentist',
              startDt: DateTime(2026, 10, 5, 14),
              endDt: DateTime(2026, 10, 5, 15),
            ),
          );
      final row = await _row(db, id);

      await _pump(tester, db, CalendaEventAdapter.fromDrift(row));
      await _pickDate(tester, 'Starts at', '9');
      await _save(tester);

      expect(find.text('End time must be after start time'), findsOneWidget);
      final after = await _row(db, id);
      expect(after.startDt, DateTime(2026, 10, 5, 14));
      await _unmount(tester);
    });

    testWidgets('an all-day end before its start is refused', (tester) async {
      final calId = await _seedCalendar(db);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Holiday',
              startDt: DateTime(2026, 10, 5),
              endDt: DateTime(2026, 10, 5),
              isAllDay: const Value(true),
            ),
          );
      final row = await _row(db, id);

      await _pump(tester, db, CalendaEventAdapter.fromDrift(row));
      await _pickDateOnly(tester, 'Starts at', '9');
      await _save(tester);

      expect(find.text('End time must be after start time'), findsOneWidget);
      final after = await _row(db, id);
      expect(after.startDt, DateTime(2026, 10, 5));
      await _unmount(tester);
    });
  });
}
