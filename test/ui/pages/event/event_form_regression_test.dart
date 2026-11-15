import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

(GoRouter, Widget) _app(
  AppDatabase db,
  CalendaEventAdapter event, {
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('calendar')),
      ),
      GoRoute(path: '/event/edit', builder: (_, __) => EventFormPage(event: event)),
    ],
  );
  return (
    router,
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), ...overrides],
      child: MaterialApp.router(
        routerConfig: router,
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
}

Future<void> _open(WidgetTester tester, GoRouter router, Widget app) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await _settle(tester);
  router.push('/event/edit');
  await _settle(tester);
}

Future<Event> _row(AppDatabase db, int id) =>
    (db.select(db.events)..where((row) => row.id.equals(id))).getSingle();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CalendaEventAdapter event;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = (await db.select(db.calendars).get()).single.id;
    final id = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Original event',
            startDt: DateTime(2026, 11, 15, 9),
            endDt: DateTime(2026, 11, 15, 10),
          ),
        );
    event = CalendaEventAdapter.fromDrift(await _row(db, id));
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('a failed association read blocks Save until retried', (
    tester,
  ) async {
    var fail = true;
    final (router, app) = _app(
      db,
      event,
      overrides: [
        eventTagsProvider(event.drifId).overrideWith(
          (ref) => fail
              ? Stream<List<Tag>>.error(StateError('tags failed'))
              : Stream<List<Tag>>.value(const []),
        ),
      ],
    );
    await _open(tester, router, app);

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.byType(EventFormPage), findsOneWidget);
    expect((await _row(db, event.drifId)).summary, 'Original event');

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(
      find.text('Discard changes?'),
      findsOneWidget,
      reason: 'an unloaded form has no honest baseline to discard',
    );
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);

    fail = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Recovered event');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect((await _row(db, event.drifId)).summary, 'Recovered event');
    await _unmount(tester);
  });
}
