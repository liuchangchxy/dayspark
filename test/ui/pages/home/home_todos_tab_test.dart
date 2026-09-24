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
import 'package:dayspark/ui/pages/settings/settings_sections/todos_section.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage(initialTab: 1)),
    GoRoute(
      path: '/todo/edit',
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

  testWidgets('collapses today list to six slots with a More fold row', (
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

    expect(find.text('Task 0'), findsOneWidget);
    expect(find.text('Task 5'), findsOneWidget);
    expect(find.text('Task 6'), findsNothing);
    expect(find.text('Task 7'), findsNothing);
    expect(find.text('More (2)'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('More fold row expands to the full list and collapses back', (
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
    expect(find.text('Task 7'), findsNothing);

    await tester.tap(find.text('More (2)'));
    await _settle(tester);
    expect(find.text('Task 6'), findsOneWidget);
    expect(find.text('Task 7'), findsOneWidget);
    expect(find.text('Collapse'), findsOneWidget);

    await tester.tap(find.text('Collapse'));
    await _settle(tester);
    expect(find.text('Task 7'), findsNothing);
    expect(find.text('More (2)'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('six-things toggle defaults off and persists when switched on', (
    tester,
  ) async {
    await _seedTodayTodos(db, pendingCount: 8);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    // Default OFF: full list, no fold row.
    expect(find.text('Task 7'), findsOneWidget);
    expect(find.text('More (2)'), findsNothing);

    await tester.tap(find.text('Six Things'));
    await _settle(tester);
    expect(find.text('Task 6'), findsNothing);
    expect(find.text('More (2)'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('six_things_mode'), isTrue);

    // A fresh tree (fresh providers) restores the persisted value.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_app(db));
    await _settle(tester);
    expect(find.text('Task 6'), findsNothing);
    expect(find.text('More (2)'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('drag reorder inside six slots preserves the full list order', (
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
    expect(find.text('Task 0'), findsOneWidget);

    // Long-press drag (ReorderableDelayedDragStartListener on touch
    // platforms) moves Task 0 one slot down within the visible six.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Task 0')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 110));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await _settle(tester);

    final rows =
        await (db.select(db.todos)..orderBy([
              (t) => OrderingTerm.asc(t.sortOrder),
            ]))
            .get();
    expect(rows.first.summary, 'Task 1');
    expect(rows[1].summary, 'Task 0');
    // Hidden tail keeps its relative order after the in-prefix move.
    expect(rows[2].summary, 'Task 2');
    expect(rows.last.summary, 'Task 7');
    // Collapsed view still shows exactly six slots.
    expect(find.text('More (2)'), findsOneWidget);
    expect(find.text('Task 7'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('hide-completed setting hides the completed section', (
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

  testWidgets('completed section shows when hide-completed is off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'default_tab': 'calendar',
      'hide_completed': false,
    });
    await _seedTodayTodos(db, pendingCount: 2, withCompleted: true);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Done task'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('todos settings switch persists hide_completed', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: TodosSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isFalse,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('hide_completed'), isTrue);
  });

  testWidgets('todos settings switch restores persisted state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'hide_completed': true});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: TodosSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
}
