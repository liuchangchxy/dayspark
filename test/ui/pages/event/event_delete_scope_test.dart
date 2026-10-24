import 'package:drift/drift.dart' show Value;
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
import 'package:dayspark/domain/utils/recurring_event_helper.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';

/// "Delete" on a recurring series has two very different meanings. The detail
/// page asks which one first; picking a single occurrence must leave the row
/// alive and only exclude that date (RFC 5545 EXDATE).
(GoRouter, Widget) _app(AppDatabase db, CalendaEventAdapter event) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('calendar')),
      ),
      GoRoute(
        path: '/event/detail',
        builder: (_, __) => EventDetailPage(event: event),
      ),
    ],
  );
  return (
    router,
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Future<({int id, CalendaEventAdapter occurrence})> _seedSeries(
  AppDatabase db,
) async {
  final calId = await db
      .into(db.calendars)
      .insert(CalendarsCompanion.insert(name: 'Personal'));
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
  final expanded = expandRecurringEvents(
    rows,
    before: DateTime(2026, 10, 1),
    after: DateTime(2026, 10, 31),
  );
  return (id: id, occurrence: expanded[2]);
}

Future<void> _openDeleteDialog(
  WidgetTester tester,
  AppDatabase db,
  CalendaEventAdapter event,
) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final (router, app) = _app(db, event);
  await tester.pumpWidget(app);
  await _settle(tester);
  router.push('/event/detail');
  await _settle(tester);

  await tester.tap(find.text('Move to Trash'));
  await _settle(tester);
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

  testWidgets('deleting one occurrence excludes that date, keeps the series', (
    tester,
  ) async {
    final seeded = await _seedSeries(db);
    await _openDeleteDialog(tester, db, seeded.occurrence);

    expect(find.text('Delete which?'), findsOneWidget);
    expect(find.text('This occurrence only'), findsOneWidget);
    expect(find.text('The whole series'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'This occurrence only'));
    await _settle(tester);

    final after = await _row(db, seeded.id);
    expect(after.deletedAt, isNull, reason: 'the series itself survives');
    expect(
      parseExdates(after.exdates),
      contains(seeded.occurrence.start),
      reason: 'only the chosen date is excluded',
    );
    expect(after.rrule, 'RRULE:FREQ=DAILY;COUNT=5');
    await _unmount(tester);
  });

  testWidgets('deleting the whole series moves the row to the trash', (
    tester,
  ) async {
    final seeded = await _seedSeries(db);
    await _openDeleteDialog(tester, db, seeded.occurrence);

    await tester.tap(find.widgetWithText(TextButton, 'The whole series'));
    await _settle(tester);

    final after = await _row(db, seeded.id);
    expect(after.deletedAt, isNotNull);
    expect(
      parseExdates(after.exdates),
      isEmpty,
      reason: 'the whole series is not an exclusion',
    );
    final all = await db.select(db.events).get();
    expect(all, hasLength(1), reason: 'a series is one row, not five');
    await _unmount(tester);
  });

  testWidgets('cancelling the scope question deletes nothing', (tester) async {
    final seeded = await _seedSeries(db);
    final before = await _row(db, seeded.id);
    await _openDeleteDialog(tester, db, seeded.occurrence);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester);

    final after = await _row(db, seeded.id);
    expect(after.deletedAt, before.deletedAt);
    expect(after.exdates, before.exdates);
    await _unmount(tester);
  });
}
