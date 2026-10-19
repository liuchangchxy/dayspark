import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_create_page.dart';
import 'package:dayspark/ui/pages/event/event_edit_page.dart';

GoRouter _router({CalendaEventAdapter? event}) => GoRouter(
  initialLocation: event == null ? '/new' : '/edit',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: Center(child: Text('home'))),
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, __) => EventCreatePage(
            initialStart: DateTime(2026, 10, 5, 9),
            initialEnd: DateTime(2026, 10, 5, 10),
          ),
        ),
        GoRoute(
          path: 'edit',
          builder: (_, __) => EventEditPage(event: event!),
        ),
      ],
    ),
  ],
);

Widget _app(AppDatabase db, {CalendaEventAdapter? event}) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp.router(
    routerConfig: _router(event: event),
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
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  CalendaEventAdapter? event,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(db, event: event));
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder get _picker => find.byType(DropdownButtonFormField<int>);

Future<void> _chooseCalendar(WidgetTester tester, String name) async {
  await tester.tap(_picker);
  await _settle(tester);
  await tester.tap(find.text(name).last);
  await _settle(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await _settle(tester);
}

Future<int> _addCalendar(AppDatabase db, String name, int sortOrder) => db
    .into(db.calendars)
    .insert(CalendarsCompanion.insert(name: name, sortOrder: Value(sortOrder)));

/// `AppDatabase.forTesting` runs `onCreate`, which seeds one "Personal"
/// calendar; that row is the default target every test starts from.
Future<List<Calendar>> _calendars(AppDatabase db) => (db.select(
  db.calendars,
)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();

Future<Event> _event(AppDatabase db, int id) =>
    (db.select(db.events)..where((t) => t.id.equals(id))).getSingle();

Future<Event> _onlyEvent(AppDatabase db) async {
  final all = await db.select(db.events).get();
  expect(all.length, 1, reason: 'expected exactly one event row');
  return all.single;
}

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('with one calendar the picker stays out of the way', (
    tester,
  ) async {
    final seeded = await _calendars(db);
    expect(seeded.length, 1);

    await _pump(tester, db);
    expect(_picker, findsNothing, reason: 'one calendar is not a choice');

    await tester.enterText(_field('Title'), 'Solo event');
    await _save(tester);

    final created = await _onlyEvent(db);
    expect(created.calendarId, seeded.single.id);
    await _unmount(tester);
  });

  testWidgets('creating into a chosen calendar lands there', (tester) async {
    final work = await _addCalendar(db, 'Work', 1);

    await _pump(tester, db);
    expect(_picker, findsOneWidget);

    await tester.enterText(_field('Title'), 'Standup');
    await _chooseCalendar(tester, 'Work');
    await _save(tester);

    final created = await _onlyEvent(db);
    expect(created.calendarId, work);
    expect(created.summary, 'Standup');
    await _unmount(tester);
  });

  testWidgets('creating without touching the picker uses the default', (
    tester,
  ) async {
    final personal = (await _calendars(db)).single.id;
    await _addCalendar(db, 'Work', 1);

    await _pump(tester, db);
    await tester.enterText(_field('Title'), 'Default target');
    await _save(tester);

    final created = await _onlyEvent(db);
    expect(created.calendarId, personal);
    await _unmount(tester);
  });

  testWidgets('editing moves an event to another calendar', (tester) async {
    final personal = (await _calendars(db)).single.id;
    final work = await _addCalendar(db, 'Work', 1);
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: personal,
            summary: 'Retro',
            startDt: DateTime(2026, 10, 5, 9),
            endDt: DateTime(2026, 10, 5, 10),
          ),
        );
    final row = await _event(db, id);

    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(row));
    await _chooseCalendar(tester, 'Work');
    await _save(tester);

    final after = await _event(db, id);
    expect(after.calendarId, work);
    expect(after.startDt, DateTime(2026, 10, 5, 9));
    await _unmount(tester);
  });

  testWidgets('editing keeps the current calendar when it is left alone', (
    tester,
  ) async {
    final work = await _addCalendar(db, 'Work', 1);
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: work,
            summary: 'Retro',
            startDt: DateTime(2026, 10, 5, 9),
            endDt: DateTime(2026, 10, 5, 10),
          ),
        );
    final row = await _event(db, id);

    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(row));
    await tester.enterText(_field('Title'), 'Retro (renamed)');
    await _save(tester);

    final after = await _event(db, id);
    expect(after.calendarId, work);
    expect(after.summary, 'Retro (renamed)');
    await _unmount(tester);
  });

  testWidgets('an event whose calendar is gone falls back to a live one', (
    tester,
  ) async {
    final personal = (await _calendars(db)).single.id;
    // A third calendar keeps the picker on screen, so the fallback selection
    // is actually observable instead of collapsing to a hidden row.
    await _addCalendar(db, 'Work', 1);
    final doomed = await _addCalendar(db, 'Doomed', 2);
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: doomed,
            summary: 'Orphan',
            startDt: DateTime(2026, 10, 5, 9),
            endDt: DateTime(2026, 10, 5, 10),
          ),
        );
    await (db.delete(db.calendars)..where((t) => t.id.equals(doomed))).go();
    final row = await _event(db, id);

    // The picker must not offer a calendar that no longer exists, and the
    // write must not target a dangling id.
    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(row));
    expect(tester.takeException(), isNull);
    expect(
      find.text('Doomed'),
      findsNothing,
      reason: 'a calendar that no longer exists must not be offered',
    );
    expect(
      find.text('Personal'),
      findsOneWidget,
      reason: 'the picker has to show the calendar the save will target',
    );
    await tester.enterText(_field('Title'), 'Orphan (renamed)');
    await _save(tester);

    final after = await _event(db, id);
    expect(after.calendarId, personal);
    expect(after.summary, 'Orphan (renamed)');
    await _unmount(tester);
  });

  testWidgets('a reopened event reports the calendar it was saved into', (
    tester,
  ) async {
    final personal = (await _calendars(db)).single.id;
    final work = await _addCalendar(db, 'Work', 1);
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: personal,
            summary: 'Retro',
            startDt: DateTime(2026, 10, 5, 9),
            endDt: DateTime(2026, 10, 5, 10),
          ),
        );
    final row = await _event(db, id);

    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(row));
    await _chooseCalendar(tester, 'Work');
    await _save(tester);
    await _unmount(tester);

    // Reopen from the row the calendar would hand back.
    final saved = await _event(db, id);
    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(saved));
    final dropdown = tester.widget<DropdownButtonFormField<int>>(_picker);
    expect(dropdown.initialValue, work);
    await _unmount(tester);
  });
}
