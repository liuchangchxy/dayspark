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
import 'package:dayspark/ui/pages/home/home_page.dart';

Widget _app({required AppDatabase db, required DateTime Function() clock}) {
  return ProviderScope(
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
      home: HomePage(clock: clock),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int calendarId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Default',
            color: const Value('#2196F3'),
          ),
        );
    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Dinner'),
        );
    await db
        .into(db.taskAllocations)
        .insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(todoId),
            startAt: DateTime(2026, 10, 6, 15).toUtc(),
            endAt: DateTime(2026, 10, 6, 15, 22).toUtc(),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('Today clock advances when the minute turns', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var currentTime = DateTime(2026, 10, 6, 15, 21);
    await tester.pumpWidget(_app(db: db, clock: () => currentTime));
    await _settle(tester);

    expect(find.text('15:21'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Earlier today'), findsNothing);

    currentTime = DateTime(2026, 10, 6, 15, 22);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await _settle(tester);

    expect(find.text('15:22'), findsOneWidget);
    expect(find.text('15:21'), findsNothing);
    expect(find.text('Earlier today'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Ticker is cancelled when HomePage is disposed', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var currentTime = DateTime(2026, 10, 6, 15, 21);
    await tester.pumpWidget(_app(db: db, clock: () => currentTime));
    await _settle(tester);

    // Switch to Tasks, where the minute ticker must not rebuild Today's
    // snapshot, then return: Today re-reads the clock on its own build.
    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    expect(find.text('15:21'), findsNothing);
    currentTime = DateTime(2026, 10, 6, 15, 22);
    await tester.pump(const Duration(seconds: 30));
    await _settle(tester);
    await tester.tap(find.text('Today').last);
    await _settle(tester);
    expect(find.text('15:22'), findsOneWidget);
    expect(find.text('Earlier today'), findsOneWidget);

    await _unmount(tester);

    // If dispose left the ticker armed, pumping past its next fire would make
    // the test end with a pending timer.
    currentTime = DateTime(2026, 10, 6, 15, 25);
    await tester.pump(const Duration(minutes: 3));
    expect(tester.takeException(), isNull);
  });
}
