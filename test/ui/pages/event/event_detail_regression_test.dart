import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Widget _app(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    ),
  );
}

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
            summary: 'Planning',
            startDt: DateTime(2026, 11, 15, 9),
            endDt: DateTime(2026, 11, 15, 10),
          ),
        );
    event = CalendaEventAdapter.fromDrift(
      await (db.select(db.events)..where((row) => row.id.equals(id))).getSingle(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('a failed live read shows retry instead of a spinner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        EventDetailPage(event: event),
        overrides: [
          databaseProvider.overrideWithValue(db),
          liveEventProvider(event.drifId).overrideWith(
            (ref) =>
                Stream<CalendaEventAdapter?>.error(StateError('load failed')),
          ),
        ],
      ),
    );
    await _settle(tester);

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failed detail delete keeps the page and re-enables delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        EventDetailPage(event: event),
        overrides: [
          databaseProvider.overrideWithValue(db),
          deleteEventProvider.overrideWithValue((id) async {
            attempts++;
            throw StateError('delete failed');
          }),
        ],
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(DsButton, 'Move to Trash'));
    await _settle(tester);

    expect(attempts, 1);
    expect(find.text("That didn't work. Please try again."), findsOneWidget);
    expect(find.byKey(const ValueKey('event-detail-title')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    await tester.tap(find.text('Move to Trash'));
    await _settle(tester);
    expect(find.byType(DsDialog), findsOneWidget);
    expect(attempts, 1);
    await _unmount(tester);
  });

  testWidgets('detail shows reminders and always opens the shared picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        EventDetailPage(event: event),
        overrides: [databaseProvider.overrideWithValue(db)],
      ),
    );
    await _settle(tester);

    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Add Reminder'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-picker')));
    await _settle(tester);

    // One calendar is still a calendar question; creating another is offered.
    expect(find.text('Personal'), findsWidgets);
    expect(find.text('+ New calendar'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the read drawer footer offers only edit and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calendarId = (await db.select(db.calendars).get()).single.id;
    final allDayId = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Holiday',
            startDt: DateTime(2026, 11, 15),
            endDt: DateTime(2026, 11, 16),
            isAllDay: const Value(true),
          ),
        );
    final allDay = CalendaEventAdapter.fromDrift(
      await (db.select(db.events)..where((row) => row.id.equals(allDayId)))
          .getSingle(),
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: EventDetailPane(event: allDay, inlineSummary: true),
        ),
        overrides: [databaseProvider.overrideWithValue(db)],
      ),
    );
    await _settle(tester);

    // Spec: the read drawer is 编辑 / 删除. Time is an editable field, so the
    // shortcut that silently wrote start/end without marking the form dirty is
    // gone.
    expect(find.byKey(const ValueKey('event-detail-edit')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('event-detail-delete-summary')),
      findsOneWidget,
    );
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byKey(const ValueKey('event-detail-schedule')), findsNothing);
    expect(find.text('Add execution time'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('event-detail-edit')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('event-detail-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-detail-title')), findsOneWidget);

    await _unmount(tester);
  });
}
