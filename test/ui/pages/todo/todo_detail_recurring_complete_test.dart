import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Completing a recurring todo is a question — which occurrence? — not a row
/// write. Detail used to call the writer with no occurrence and throw
/// `StateError('Recurring Todo completion requires occurrenceId.')`; it now
/// goes through the same entry point as the list.
Widget _app(AppDatabase db, Todo todo) {
  final router = GoRouter(
    initialLocation: '/todo/detail',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/todo/detail',
        builder: (_, __) => TodoDetailPage(todo: todo),
      ),
    ],
  );
  return ProviderScope(
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
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
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
          summary: 'Daily standup',
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

  testWidgets('completing a recurring Todo from Detail asks which occurrence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, series));
    await _settle(tester);

    await tester.tap(find.text('Mark Complete'));
    await _settle(tester);

    expect(
      find.text('Select occurrence'),
      findsOneWidget,
      reason: 'a recurring series has no single row-level completion',
    );

    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await _settle(tester);

    final states = await db.select(db.taskInstanceStates).get();
    expect(states, hasLength(1), reason: 'the chosen occurrence is recorded');
    expect(states.single.status, 'completed');
    expect(states.single.todoSyncId, series.syncId);

    expect(find.text('Something went wrong. Please try again.'), findsNothing);
    await _unmount(tester);
  });
}
