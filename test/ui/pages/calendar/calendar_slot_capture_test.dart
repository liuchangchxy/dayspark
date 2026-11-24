import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';

Widget _wrap(Widget child, AppDatabase db) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  ),
);

/// The calendar list is a drift stream, so its first emission lands on a later
/// microtask/frame. `pumpAndSettle` can stop before that stream schedules its
/// rebuild; explicit pumps let the query deliver its rows.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Disposing the ProviderScope cancels the drift query, which schedules a
/// zero-duration timer. Flush it before the test binding verifies that no
/// timers are pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  final range = DateTimeRange(
    start: DateTime(2026, 11, 20, 11),
    end: DateTime(2026, 11, 20, 12),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // The schema seeds a "Personal" calendar on create. These tests want the
    // capture row to name a known single calendar, so replace the seed.
    await db.delete(db.calendars).go();
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#5F7183'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the capture panel prefills time and calendar, then writes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          capture: true,
          range: range,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => const [],
        ),
        db,
      ),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('slot-capture-panel')), findsOneWidget);
    expect(find.text('New Event'), findsOneWidget);
    expect(find.textContaining('11:00–12:00'), findsWidgets);
    expect(find.text('Work'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('slot-capture-title')),
      'Design review',
    );
    await tester.tap(find.byKey(const ValueKey('slot-capture-create')));
    await _settle(tester);

    final events = await db.select(db.events).get();
    expect(events, hasLength(1));
    expect(events.single.summary, 'Design review');
    expect(events.single.startDt, DateTime(2026, 11, 20, 11));
    expect(events.single.endDt, DateTime(2026, 11, 20, 12));

    // The 15-minute default reminder is written with the event, same as the
    // NewItemPage save model.
    final reminders = await db.select(db.reminders).get();
    expect(reminders, hasLength(1));
    expect(reminders.single.parentType, 'event');
    expect(reminders.single.parentId, events.single.id);
    expect(
      reminders.single.triggerTime,
      DateTime(2026, 11, 20, 10, 45),
    );

    await _unmount(tester);
  });

  testWidgets('an empty title refuses to write and says which field', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          capture: true,
          range: range,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => const [],
        ),
        db,
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('slot-capture-create')));
    await _settle(tester);

    expect(find.text('Title cannot be empty.'), findsOneWidget);
    expect(await db.select(db.events).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets('the two todo paths stay reachable below the capture form', (
    tester,
  ) async {
    var createdTodoPath = false;
    await tester.pumpWidget(
      _wrap(
        CalendarSlotSheet(
          capture: true,
          range: range,
          onCreateEvent: () {},
          onScheduleTodo: (todo, _) async {},
          loadSchedulableTodos: () async => const [],
          onCreateTodoHere: () => createdTodoPath = true,
        ),
        db,
      ),
    );
    await _settle(tester);

    expect(find.text('Other scheduling options'), findsOneWidget);
    expect(find.text('New & schedule'), findsOneWidget);
    expect(find.text('Schedule Task'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-capture-create-schedule')));
    await _settle(tester);
    expect(createdTodoPath, isTrue);

    await _unmount(tester);
  });
}
