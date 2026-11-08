import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage(initialTab: 2)),
    GoRoute(
      path: '/todo/detail',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
    GoRoute(
      path: '/tags',
      builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
    ),
    GoRoute(
      path: '/trash',
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
  // Drift broadcast streams never complete; pump a fixed number of frames.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Unmount the tree and flush drift's zero-duration stream-close timers so
// the test binding's pending-timer invariant holds at teardown.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Future<AppDatabase> _seedTodayTodos(
  AppDatabase db, {
  int pendingCount = 8,
  bool withCompleted = false,
}) async {
  final calId = await db
      .into(db.calendars)
      .insert(CalendarsCompanion.insert(name: 'Test'));
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (var i = 0; i < pendingCount; i++) {
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Task $i',
            dueDate: Value(today),
            sortOrder: Value(i),
          ),
        );
  }
  if (withCompleted) {
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Done task',
            dueDate: Value(today),
            status: const Value('COMPLETED'),
            completedAt: Value(today),
            percentComplete: const Value(100),
            sortOrder: Value(99),
          ),
        );
  }
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('shows the full day list and ignores the retired fold pref', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'default_tab': 'calendar',
      'six_things_mode': true,
    });
    await _seedTodayTodos(db, pendingCount: 8);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    for (var i = 0; i < 8; i++) {
      expect(find.text('Task $i'), findsOneWidget);
    }
    expect(find.textContaining('More ('), findsNothing);
    expect(find.text('Six Things'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('drag reorder moves a row and keeps every row visible', (
    tester,
  ) async {
    await _seedTodayTodos(db, pendingCount: 8);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);
    expect(find.text('Task 0'), findsOneWidget);

    // Long-press drag (ReorderableDelayedDragStartListener on touch
    // platforms) moves Task 0 one slot down.
    final dragDistance =
        (tester.getCenter(find.text('Task 1')).dy -
            tester.getCenter(find.text('Task 0')).dy) *
        1.5;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Task 0')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, dragDistance / 10));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await _settle(tester);

    final rows =
        await (db.select(db.todos)..orderBy([
              (t) => OrderingTerm.asc(t.sortOrder),
            ]))
            .get();
    expect(rows.first.summary, 'Task 1');
    expect(rows[1].summary, 'Task 0');
    expect(rows[2].summary, 'Task 2');
    expect(rows.last.summary, 'Task 7');
    expect(find.text('Task 7'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('display menu hides completed rows and persists the choice', (
    tester,
  ) async {
    await _seedTodayTodos(db, pendingCount: 2, withCompleted: true);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);
    expect(find.text('Done task'), findsOneWidget);

    await tester.tap(find.byTooltip('Display'));
    await _settle(tester);
    await tester.tap(find.text('Hide completed'));
    await _settle(tester);

    expect(find.text('Done task'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('hide_completed'), isTrue);
    await _unmount(tester);
  });

  testWidgets('persisted hide-completed state applies on launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'default_tab': 'calendar',
      'hide_completed': true,
    });
    await _seedTodayTodos(db, pendingCount: 2, withCompleted: true);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(find.text('Task 0'), findsOneWidget);
    expect(find.text('Done task'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    await _unmount(tester);
  });
}
