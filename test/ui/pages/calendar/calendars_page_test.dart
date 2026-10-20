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
  });
}
