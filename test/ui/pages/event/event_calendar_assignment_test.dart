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
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';

GoRouter _router({CalendaEventAdapter? event}) => GoRouter(
  initialLocation: event == null ? '/new' : '/edit',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: Center(child: Text('home'))),
      routes: [
        GoRoute(
          path: 'new',
          builder: (_, __) => EventFormPage(
            initialStart: DateTime(2026, 10, 5, 9),
            initialEnd: DateTime(2026, 10, 5, 10),
          ),
        ),
        GoRoute(
          path: 'edit',
          builder: (_, __) => EventFormPage(event: event!),
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

Finder _field(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

Finder get _picker => find.text('Calendar');

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

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase db,
  Event event, {
  bool embedded = false,
}) async {
  tester.view.physicalSize = embedded
      ? const Size(1400, 1000)
      : const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = CalendaEventAdapter.fromDrift(event);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: embedded
              ? EventDetailPane(event: adapter, embedded: true)
              : EventDetailPage(event: adapter),
        ),
      ),
    ),
  );
  await _settle(tester);
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

  testWidgets('detail calendar picker scrolls on a small screen', (
    tester,
  ) async {
    final personal = (await _calendars(db)).single.id;
    var lastId = 0;
    for (var i = 0; i < 18; i++) {
      lastId = await _addCalendar(db, 'Calendar $i', i + 1);
    }
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: personal,
            summary: 'Meeting',
            startDt: DateTime(2026, 10, 5, 9),
            endDt: DateTime(2026, 10, 5, 10),
          ),
        );
    await _pumpDetail(tester, db, await _event(db, id));
    await tester.tap(_picker);
    await _settle(tester);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -1500),
    );
    await _settle(tester);
    await tester.tap(find.text('Calendar 17'));
    await _settle(tester);
    expect((await _event(db, id)).calendarId, lastId);
    await _unmount(tester);
  });

  for (final embedded in [false, true]) {
    testWidgets(
      'detail changes calendar on ${embedded ? 'desktop' : 'mobile'}',
      (tester) async {
        final personal = (await _calendars(db)).single.id;
        final work = await _addCalendar(db, 'Work', 1);
        final id = await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                calendarId: personal,
                summary: 'Series',
                startDt: DateTime(2026, 10, 5, 9),
                endDt: DateTime(2026, 10, 5, 10),
                rrule: const Value('RRULE:FREQ=DAILY;COUNT=5'),
              ),
            );
        await _pumpDetail(tester, db, await _event(db, id), embedded: embedded);
        await _chooseCalendar(tester, 'Work');
        final saved = await _event(db, id);
        expect(saved.calendarId, work);
        expect(saved.startDt, DateTime(2026, 10, 5, 9));
        expect(saved.endDt, DateTime(2026, 10, 5, 10));
        expect(saved.rrule, 'RRULE:FREQ=DAILY;COUNT=5');
        expect(find.text('Work'), findsOneWidget);
        await _unmount(tester);
      },
    );
  }

  testWidgets('detail cancel keeps the original calendar', (tester) async {
    final personal = (await _calendars(db)).single.id;
    await _addCalendar(db, 'Work', 1);
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: personal,
            summary: 'Event',
            startDt: DateTime(2026, 10, 5, 9),
            endDt: DateTime(2026, 10, 5, 10),
          ),
        );
    await _pumpDetail(tester, db, await _event(db, id));
    await tester.tap(_picker);
    await _settle(tester);
    Navigator.of(tester.element(find.text('Work').last)).pop();
    await _settle(tester);
    expect((await _event(db, id)).calendarId, personal);
    await _unmount(tester);
  });

  testWidgets('detail allows replacing an unavailable calendar', (
    tester,
  ) async {
    final personal = (await _calendars(db)).single.id;
    final doomed = await _addCalendar(db, 'Doomed', 1);
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
    await _pumpDetail(tester, db, await _event(db, id));
    expect(
      find.text('Calendar unavailable. Please choose another calendar.'),
      findsOneWidget,
    );
    await _chooseCalendar(tester, 'Personal');
    expect((await _event(db, id)).calendarId, personal);
    await _unmount(tester);
  });

  testWidgets('with one calendar the picker stays out of the way', (
    tester,
  ) async {
    final seeded = await _calendars(db);
    expect(seeded.length, 1);

    await _pump(tester, db);
    // The row still says which calendar receives the event; it just has
    // nothing to choose from, so tapping it opens no sheet.
    expect(_picker, findsOneWidget);
    await tester.tap(_picker);
    await _settle(tester);
    expect(find.byType(ListTile), findsNothing);

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

  testWidgets('an event whose calendar is gone prompts to re-select', (
    tester,
  ) async {
    final personal = (await _calendars(db)).single.id;
    // A third calendar keeps the picker on screen
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

    // The picker must not silently fall back to another calendar; it should
    // prompt that calendar is unavailable and require explicit selection.
    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(row));
    expect(tester.takeException(), isNull);
    expect(
      find.text('Doomed'),
      findsNothing,
      reason: 'a calendar that no longer exists must not be offered',
    );
    expect(
      find.text('Calendar unavailable. Please choose another calendar.'),
      findsAtLeastNWidgets(1),
    );

    // Re-select Personal explicitly
    await _chooseCalendar(tester, 'Personal');
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
    expect(saved.calendarId, work);
    await _pump(tester, db, event: CalendaEventAdapter.fromDrift(saved));
    expect(find.text('Work'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'when calendarsProvider is prewarmed, dangling calendarId prompts without assertion',
    (tester) async {
      final personal = (await _calendars(db)).single.id;
      final doomed = await _addCalendar(db, 'Doomed', 1);
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: doomed,
              summary: 'Prewarmed orphan',
              startDt: DateTime(2026, 10, 5, 9),
              endDt: DateTime(2026, 10, 5, 10),
            ),
          );
      // Remove the doomed calendar so doomed id is dangling
      await (db.delete(db.calendars)..where((t) => t.id.equals(doomed))).go();
      final row = await _event(db, id);

      // Prewarm the provider by building a widget that reads calendarsProvider
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await container.read(calendarsProvider.future);

      // Pump the event edit page with prewarmed state
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _router(event: CalendaEventAdapter.fromDrift(row)),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Calendar unavailable. Please choose another calendar.'),
        findsAtLeastNWidgets(1),
      );
      await _chooseCalendar(tester, 'Personal');
      await tester.enterText(_field('Title'), 'Prewarmed orphan (saved)');
      await _save(tester);

      final after = await _event(db, id);
      expect(after.calendarId, personal);
      expect(after.summary, 'Prewarmed orphan (saved)');
      await _unmount(tester);
    },
  );
}
