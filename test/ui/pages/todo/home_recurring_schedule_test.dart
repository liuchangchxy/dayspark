import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

/// Scheduling a recurring todo from its row button used to reach the writer
/// with no occurrence and throw `StateError`; the row must resolve the current
/// occurrence and bind the block to it instead.
GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage(initialTab: 2)),
    GoRoute(
      path: '/todo/detail',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
  ],
);

Widget _app(AppDatabase db) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp.router(
    routerConfig: _router(),
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late Todo series;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final now = DateTime.now();
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(now.year, now.month, now.day),
      ),
      timeZone: 'UTC',
      rrule: 'FREQ=DAILY;COUNT=7',
    );
    final id = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Daily review',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );
    series = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('row schedule button binds a recurring todo to its occurrence', (
    tester,
  ) async {
    expect(series.rrule, isNotNull);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.tap(find.byTooltip('Schedule'));
    await _settle(tester);
    expect(find.text('Schedule'), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await _settle(tester);

    final allocations = await db.select(db.taskAllocations).get();
    expect(
      allocations,
      hasLength(1),
      reason: 'the row writes its block instead of throwing',
    );
    expect(allocations.single.occurrenceId, isNotNull);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsNothing,
    );
    await _unmount(tester);
  });
}
