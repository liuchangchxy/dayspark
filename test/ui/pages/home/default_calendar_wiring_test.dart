import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/today_page.dart';

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: A2TodayPage(
          now: DateTime(2026, 10, 6, 15),
          onOpenTodo: (_) {},
          onOpenEvent: (_) {},
          onToggleTodo: (_, __, ___) async => true,
          onOpenUnplanned: () {},
          onScheduleTodo: (_) {},
        ),
      ),
    ),
  );
}

ProviderContainer _container(AppDatabase db, DateTime day) {
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      actionDateProvider.overrideWith((ref) => day),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _capture(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('today-capture-field')),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late int firstId;
  late int secondId;
  final day = DateTime(2026, 10, 6);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.delete(db.calendars).go();
    firstId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'First',
            color: const Value('#2196F3'),
          ),
        );
    secondId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Second',
            color: const Value('#4CAF50'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('resolveNewEntryCalendarId', () {
    test('prefers the stored calendar while it still exists', () async {
      final calendars = await db.select(db.calendars).get();
      expect(
        resolveNewEntryCalendarId(calendars: calendars, preferredId: secondId),
        secondId,
      );
    });

    test(
      'falls back to the first calendar when the preference is gone',
      () async {
        final calendars = await db.select(db.calendars).get();
        expect(
          resolveNewEntryCalendarId(calendars: calendars, preferredId: 9999),
          firstId,
        );
        expect(
          resolveNewEntryCalendarId(calendars: calendars, preferredId: null),
          firstId,
        );
      },
    );

    test('returns null when there is no calendar', () {
      expect(
        resolveNewEntryCalendarId(calendars: const [], preferredId: 1),
        isNull,
      );
    });
  });

  testWidgets('capture writes to the stored default calendar', (tester) async {
    SharedPreferences.setMockInitialValues({'default_calendar_id': secondId});
    final container = _container(db, day);
    await container.read(defaultCalendarIdProvider.notifier).ensureLoaded();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _capture(tester, 'Buy milk');

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.calendarId, secondId);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets(
    'capture falls back to the first calendar when the default was deleted',
    (tester) async {
      SharedPreferences.setMockInitialValues({'default_calendar_id': 9999});
      final container = _container(db, day);
      await container.read(defaultCalendarIdProvider.notifier).ensureLoaded();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await _capture(tester, 'Buy milk');

      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(1));
      expect(todos.single.calendarId, firstId);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
