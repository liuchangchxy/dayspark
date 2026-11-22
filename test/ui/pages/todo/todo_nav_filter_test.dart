import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Widget _todoApp({
  required List<Override> overrides,
  required DateTime now,
  DayAgenda? dayAgenda,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: A2TodoPage(
          now: now,
          dayAgenda:
              dayAgenda ??
              DayAgenda(
                day: DateTime(now.year, now.month, now.day),
                events: const [],
                allocations: const [],
                dueTodos: const [],
                overdueTodos: const [],
                instances: const [],
              ),
        ),
      ),
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
  await tester.pump(Duration.zero);
}

ProviderContainer _containerOf(WidgetTester tester, Finder finder) =>
    ProviderScope.containerOf(tester.element(finder));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late int calendarId;
  final now = DateTime(2026, 11, 15, 10);
  final today = DateTime(2026, 11, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test('Todo opens on Inbox the first time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(todosViewProvider), isA<TodosInboxView>());
    expect(container.read(todosInboxNoDateOnlyProvider), isFalse);
  });

  testWidgets('zero filter matches show the applied banner and filter empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Buy milk'),
        );

    await tester.pumpWidget(
      _todoApp(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
          todoCalendarFilterProvider.overrideWith((ref) => 999999),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('todos-filter-banner')), findsOneWidget);
    expect(find.text('Filtered · 0 items'), findsOneWidget);
    expect(find.text('No matching tasks'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('todos-filter-clear')));
    await _settle(tester);

    final container = _containerOf(tester, find.byType(A2TodoPage));
    expect(container.read(todoCalendarFilterProvider), isNull);
    expect(find.byKey(const ValueKey('todos-filter-banner')), findsNothing);
    expect(find.text('Buy milk'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('filter choices stay drafts until Apply', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _todoApp(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosInboxView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('todos-filter-tool')));
    await _settle(tester);

    await tester.tap(find.text('Work'));
    await _settle(tester);

    final container = _containerOf(tester, find.byType(A2TodoPage));
    expect(container.read(todoCalendarFilterProvider), isNull);

    await tester.tap(find.text('Apply'));
    await _settle(tester);

    expect(container.read(todoCalendarFilterProvider), calendarId);
    expect(find.byType(A2ComposerSheet), findsNothing);

    await _unmount(tester);
  });

  testWidgets('All names the completed group Completed and the empty box honestly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _todoApp(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    expect(
      tester.widget<A2Empty>(find.byType(A2Empty)).title,
      'No tasks here',
    );
    await _unmount(tester);

    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Finished',
            status: const Value('COMPLETED'),
          ),
        );
    await tester.pumpWidget(
      _todoApp(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Completed Today'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('View unplanned opens Inbox narrowed to undated tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (var i = 0; i < 6; i++) {
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Undated $i',
            ),
          );
    }
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'With deadline',
            dueDate: Value(today),
          ),
        );

    await tester.pumpWidget(
      _todoApp(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => today),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('View 6 unplanned'));
    await _settle(tester);

    final container = _containerOf(tester, find.byType(A2TodoPage));
    expect(container.read(todosViewProvider), isA<TodosInboxView>());
    expect(container.read(todosInboxNoDateOnlyProvider), isTrue);
    expect(
      find.byKey(const ValueKey('todos-inbox-nodate-banner')),
      findsOneWidget,
    );
    expect(find.text('From today · undated only'), findsOneWidget);
    expect(find.text('With deadline'), findsNothing);
    expect(find.text('With a deadline · unplanned'), findsNothing);
    expect(find.text('Undated 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todos-inbox-view-all')));
    await _settle(tester);
    expect(container.read(todosInboxNoDateOnlyProvider), isFalse);
    expect(find.text('With deadline'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('scheduling from All defaults to today, not the last browsed day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Schedule me'),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 10, 1)),
        ],
        child: _homeBody(now),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(ValueKey('todo-schedule-$id-series')));
    await _settle(tester);

    final composer = tester.widget<A2ComposerSheet>(
      find.byType(A2ComposerSheet),
    );
    expect(
      DateTime(
        composer.contextDate.year,
        composer.contextDate.month,
        composer.contextDate.day,
      ),
      today,
    );

    await _unmount(tester);
  });

  testWidgets('scheduling from a browsed day keeps that day', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final browseDay = DateTime(2026, 11, 10);
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Schedule me'),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => browseDay),
        ],
        child: _homeBody(now),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(ValueKey('todo-schedule-$id-series')));
    await _settle(tester);

    final composer = tester.widget<A2ComposerSheet>(
      find.byType(A2ComposerSheet),
    );
    expect(
      DateTime(
        composer.contextDate.year,
        composer.contextDate.month,
        composer.contextDate.day,
      ),
      browseDay,
    );

    await _unmount(tester);
  });
}

Widget _homeBody(DateTime now) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => HomePage(
          initialTab: 2,
          clock: () => now,
        ),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
  );
}
