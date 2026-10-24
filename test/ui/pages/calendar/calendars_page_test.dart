import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/calendar/calendars_page.dart';

void main() {
  group('CalendarsPage widget test', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Widget createWidget({List<Calendar>? calendars}) {
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (calendars != null)
            calendarsProvider.overrideWith((ref) => Stream.value(calendars)),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CalendarsPage(),
        ),
      );
    }

    testWidgets('renders initial seeded Personal calendar', (tester) async {
      final calendar = Calendar(
        id: 1,
        name: 'Personal',
        color: '#2563EB',
        timezone: 'UTC',
        isActive: true,
        sortOrder: 0,
      );
      await tester.pumpWidget(createWidget(calendars: [calendar]));
      await tester.pump();

      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Manage Calendars'), findsOneWidget);
    });

    testWidgets('can open create calendar dialog', (tester) async {
      final calendar = Calendar(
        id: 1,
        name: 'Personal',
        color: '#2563EB',
        timezone: 'UTC',
        isActive: true,
        sortOrder: 0,
      );
      await tester.pumpWidget(createWidget(calendars: [calendar]));
      await tester.pump();

      // Tap + button
      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pump();

      expect(find.text('New Calendar'), findsOneWidget);
      expect(find.text('Calendar Name'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('deleting a calendar asks where its contents go', (
      tester,
    ) async {
      // onCreate seeds one calendar; every database has at least that one.
      final personal = (await db.select(db.calendars).get()).single.id;
      final work = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Work'));
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: work, summary: 'From work'),
          );

      await tester.pumpWidget(
        createWidget(
          calendars: [
            Calendar(
              id: personal,
              name: 'Personal',
              color: '#2563EB',
              timezone: 'UTC',
              isActive: true,
              sortOrder: 0,
            ),
            Calendar(
              id: work,
              name: 'Work',
              color: '#16A34A',
              timezone: 'UTC',
              isActive: true,
              sortOrder: 1,
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(CupertinoIcons.trash).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('This calendar holds 0 events and 1 tasks.'),
        findsOneWidget,
      );
      expect(find.text('Move them to'), findsOneWidget);
      expect(find.text('Delete them with the calendar'), findsOneWidget);

      await tester.tap(find.text('Delete them with the calendar'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final calendars = await db.select(db.calendars).get();
      expect(calendars.map((c) => c.name), ['Personal']);
      expect(calendars.single.id, personal);
      final todo = (await db.select(db.todos).get()).single;
      expect(todo.deletedAt, isNotNull, reason: 'contents go to the trash');
    });

    testWidgets('moving contents keeps them, pointed at the other calendar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // onCreate seeds one calendar; every database has at least that one.
      final personal = (await db.select(db.calendars).get()).single.id;
      final work = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Work'));
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: work, summary: 'From work'),
          );

      await tester.pumpWidget(
        createWidget(
          calendars: [
            Calendar(
              id: personal,
              name: 'Personal',
              color: '#2563EB',
              timezone: 'UTC',
              isActive: true,
              sortOrder: 0,
            ),
            Calendar(
              id: work,
              name: 'Work',
              color: '#16A34A',
              timezone: 'UTC',
              isActive: true,
              sortOrder: 1,
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(CupertinoIcons.trash).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Move them to'));
      // The sheet slides in; tapping mid-animation lands off-screen.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Personal'),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final todo = (await db.select(db.todos).get()).single;
      expect(todo.calendarId, personal, reason: 'moved, not deleted');
      expect(todo.deletedAt, isNull);
    });
  });
}
