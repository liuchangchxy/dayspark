import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/search_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';

void main() {
  testWidgets('inbox suggestions are read-only and open the todo', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'GUI验收-普通Todo-Edit',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      serverRev: 0,
    );
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/todo/detail',
          builder: (_, __) => const Scaffold(body: Text('Todo detail route')),
        ),
      ],
    );
    var completionCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith((ref) => Stream.value([todo])),
          recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          toggleTodoProvider.overrideWith(
            (ref) =>
                ({
                  required int id,
                  required bool isCompleted,
                  String? occurrenceId,
                }) async {
                  expect(id, todo.id);
                  expect(isCompleted, isTrue);
                  completionCalls++;
                },
          ),
        ],
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
      ),
    );
    await tester.pumpAndSettle();

    // A lookup is not an edit surface: there is nothing to tick here.
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text(todo.summary));
    await tester.pumpAndSettle();

    expect(find.text('Todo detail route'), findsOneWidget);
    expect(completionCalls, 0);
    debugDefaultTargetPlatformOverride = null;
    router.dispose();
  });

  testWidgets('a search result opens its detail and offers no checkbox', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'GUI验收-普通Todo-Edit',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      serverRev: 0,
    );
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/todo/detail',
          builder: (_, __) => const Scaffold(body: Text('Todo detail route')),
        ),
      ],
    );
    var completionCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          toggleTodoProvider.overrideWith(
            (ref) =>
                ({
                  required int id,
                  required bool isCompleted,
                  String? occurrenceId,
                }) async {
                  expect(id, todo.id);
                  expect(isCompleted, isTrue);
                  completionCalls++;
                },
          ),
          searchResultsProvider(
            'GUI验收-普通Todo-Edit',
          ).overrideWith((ref) async => SearchResults([], [todo])),
        ],
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
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'GUI验收-普通Todo-Edit');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(Checkbox), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/search');

    await tester.tap(find.text('GUI验收-普通Todo-Edit').last);
    await tester.pumpAndSettle();

    expect(find.text('Todo detail route'), findsOneWidget);
    expect(completionCalls, 0);
    debugDefaultTargetPlatformOverride = null;
    router.dispose();
  });

  testWidgets('a new query keeps the previous results until new ones arrive, '
      'and clear returns to the empty state', (tester) async {
    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'Quarterly plan',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      serverRev: 0,
    );
    final pending = Completer<void>();
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
          recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
          searchResultsProvider(
            'plan',
          ).overrideWith((ref) async => SearchResults([], [todo])),
          // The second query never answers: the screen must not go blank
          // while the user is still reading the first answer.
          searchResultsProvider('slow').overrideWith((ref) async {
            await pending.future;
            return SearchResults([], []);
          }),
        ],
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
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'plan');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final planRow = find.byWidgetPredicate(
      (w) => w is CmdRow && w.title == 'Quarterly plan',
    );
    expect(planRow, findsOneWidget);

    await tester.enterText(find.byType(TextField), 'slow');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      planRow,
      findsOneWidget,
      reason: 'the previous answer stays readable while the next one loads',
    );

    await tester.tap(find.byKey(const ValueKey('command-clear-button')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(planRow, findsNothing);
    // Spec line 2030: clearing to empty query displays the actions group, not the old non-spec 'Search your calendar'.
    expect(find.text('New Task'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);

    pending.complete();
    router.dispose();
  });

  testWidgets('a failed new query shows an error and retry, not stale hits', (
    tester,
  ) async {
    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'Quarterly plan',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: 0,
      serverRev: 0,
    );
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
          recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
          recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
          searchResultsProvider(
            'plan',
          ).overrideWith((ref) async => SearchResults([], [todo])),
          searchResultsProvider('broken').overrideWith(
            (ref) async => throw Exception('search backend down'),
          ),
        ],
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
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'plan');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final planRow = find.byWidgetPredicate(
      (w) => w is CmdRow && w.title == 'Quarterly plan',
    );
    expect(planRow, findsOneWidget);

    await tester.enterText(find.byType(TextField), 'broken');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      planRow,
      findsNothing,
      reason: 'a failed query must not keep presenting the previous answer',
    );
    expect(find.text('Search failed. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    router.dispose();
  });

  testWidgets('desktop cmd palette geometry matches frozen spec', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
          recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
        ],
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
      ),
    );
    await tester.pumpAndSettle();

    // 1. Scrim top padding is 94
    final paddingFinder = find.byWidgetPredicate(
      (w) => w is Padding && w.padding == const EdgeInsets.only(top: 94),
    );
    expect(paddingFinder, findsOneWidget);

    // 2. Command palette card width is 620
    final boxFinder = find.byWidgetPredicate(
      (w) =>
          w is ConstrainedBox &&
          w.constraints.maxWidth == 620 &&
          w.constraints.minWidth == 0,
    );
    expect(boxFinder, findsOneWidget);

    // 3. Input bar height is 52 (CSS .cmd-input: height: 52px; padding: 0 16px)
    final inputBar = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints?.minHeight == 52 &&
          w.constraints?.maxHeight == 52,
    );
    expect(inputBar, findsOneWidget);

    // 4. Footer height is 32 (CSS .cmd-foot: height: 32px; padding: 0 16px)
    final footBar = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints?.minHeight == 32 &&
          w.constraints?.maxHeight == 32,
    );
    expect(footBar, findsOneWidget);

    // 5. CmdRow min height is 43 (CSS .cmd-row: min-height: 43px; padding: 0 16px)
    final firstRow = tester.firstWidget<Container>(
      find.descendant(
        of: find.byType(CmdRow),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.minHeight == 43,
        ),
      ),
    );
    expect(firstRow.constraints?.minHeight, 43);

    router.dispose();
  });

  testWidgets(
    'results grouping: tasks first, events second, actions third with title query and Action side',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final todo = Todo(
        id: 1,
        calendarId: 1,
        summary: 'Submit weekly report',
        priority: 5,
        status: 'NEEDS-ACTION',
        recurrenceRevision: 0,
        percentComplete: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sortOrder: 0,
        serverRev: 0,
      );

      final event = Event(
        id: 2,
        calendarId: 1,
        summary: 'Weekly team meeting',
        startDt: DateTime(2026, 11, 21, 16, 0),
        endDt: DateTime(2026, 11, 21, 17, 0),
        isAllDay: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        serverRev: 0,
      );

      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);

      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
            taskAllocationsForTodoProvider(
              todo.id,
            ).overrideWith((ref) => Stream.value([])),
            recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
            recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
            searchResultsProvider(
              'Weekly',
            ).overrideWith((ref) async => SearchResults([event], [todo])),
          ],
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
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Weekly');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Spec: Content first, actions follow
      // 1. Tasks group header
      expect(find.text('Tasks'), findsOneWidget);
      // 2. Events group header
      expect(find.text('Events'), findsOneWidget);
      // 3. Actions group header
      expect(find.text('Actions'), findsOneWidget);

      final yTasks = tester.getTopLeft(find.text('Tasks')).dy;
      final yEvents = tester.getTopLeft(find.text('Events')).dy;
      final yActions = tester.getTopLeft(find.text('Actions')).dy;

      expect(yTasks, lessThan(yEvents), reason: 'Tasks precede Events');
      expect(yEvents, lessThan(yActions), reason: 'Events precede Actions');

      // Actions group has New Task and New Event with Title "Weekly"
      expect(find.text('New Task'), findsOneWidget);
      expect(find.text('New Event'), findsOneWidget);
      expect(find.text('Title "Weekly"'), findsNWidgets(2));
      expect(find.text('Action'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      debugDefaultTargetPlatformOverride = null;
      router.dispose();
    },
  );

  testWidgets(
    'selection state and keyboard navigation update selection and footer status',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
            recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
          ],
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
        ),
      );
      await tester.pumpAndSettle();

      // Initial state has 3 action items (New Task, New Event, Configure)
      expect(find.byType(CmdRow), findsNWidgets(3));

      // No row is selected until the keyboard asks for one.
      expect(find.text('Content first, actions after'), findsOneWidget);
      expect(
        tester
            .widgetList<CmdRow>(find.byType(CmdRow))
            .where((row) => row.selected),
        isEmpty,
      );

      // Down arrow selects the first item
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Item 1 selected'), findsOneWidget);

      // Down arrow moves selection to item 2
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Item 2 selected'), findsOneWidget);

      // Down arrow moves selection to item 3
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Item 3 selected'), findsOneWidget);

      // Up arrow moves back to item 2
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.text('Item 2 selected'), findsOneWidget);

      router.dispose();
    },
  );

  testWidgets(
    'empty state shows CmdEmpty with 23px search icon and spec not-found text',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
            recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
            searchResultsProvider(
              'nonexistent',
            ).overrideWith((ref) async => SearchResults([], [])),
          ],
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
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CmdEmpty), findsOneWidget);
      expect(find.text('No results found for "nonexistent"'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.search), findsNWidgets(2)); // Input + Empty icon

      router.dispose();
    },
  );

  testWidgets(
    'mobile 390 width renders full screen command palette without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
            recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
          ],
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
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.byType(CmdRow), findsNWidgets(3));
      expect(tester.takeException(), isNull);

      router.dispose();
    },
  );

  testWidgets(
    'P1-1: todo and event result rows both render as homomorphic CmdRow with height in [43, 50), side type, and mark highlight',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final todo = Todo(
        id: 101,
        calendarId: 1,
        summary: 'Submit budget report',
        priority: 5,
        status: 'NEEDS-ACTION',
        recurrenceRevision: 0,
        percentComplete: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sortOrder: 0,
        serverRev: 0,
      );

      final event = Event(
        id: 202,
        calendarId: 1,
        summary: 'Annual budget review',
        startDt: DateTime(2026, 11, 22, 10, 0),
        endDt: DateTime(2026, 11, 22, 11, 0),
        isAllDay: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        serverRev: 0,
      );

      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
            recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
            searchResultsProvider(
              'budget',
            ).overrideWith((ref) async => SearchResults([event], [todo])),
          ],
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
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'budget');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 1. Assert both todo and event are rendered as CmdRow
      final todoRowFinder = find.byWidgetPredicate(
        (w) => w is CmdRow && w.title == 'Submit budget report',
      );
      final eventRowFinder = find.byWidgetPredicate(
        (w) => w is CmdRow && w.title == 'Annual budget review',
      );
      expect(todoRowFinder, findsOneWidget);
      expect(eventRowFinder, findsOneWidget);

      // 2. Assert heights are >= 43 and < 50
      final todoHeight = tester.getSize(todoRowFinder).height;
      final eventHeight = tester.getSize(eventRowFinder).height;
      expect(todoHeight, greaterThanOrEqualTo(43.0));
      expect(todoHeight, lessThan(50.0));
      expect(eventHeight, greaterThanOrEqualTo(43.0));
      expect(eventHeight, lessThan(50.0));

      // 3. Assert right column side is 'Task' and 'Event'
      expect(
        find.descendant(of: todoRowFinder, matching: find.text('Task')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: eventRowFinder, matching: find.text('Event')),
        findsOneWidget,
      );

      // 4. Assert both rows each have a <mark> highlight with color 0xFFF3E7C9
      final markFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            (w.decoration as BoxDecoration?)?.color == const Color(0xFFF3E7C9),
      );
      expect(
        find.descendant(of: todoRowFinder, matching: markFinder),
        findsOneWidget,
      );
      expect(
        find.descendant(of: eventRowFinder, matching: markFinder),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = null;
      router.dispose();
    },
  );

  testWidgets(
    'P1-2: desktop cmd palette body has maxHeight constraint of 390px (scrolls when rows exceed 390)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Preset 14 todos which exceed 390px
      final todos = List.generate(
        14,
        (i) => Todo(
          id: i + 1,
          calendarId: 1,
          summary: 'Bulk item number $i for search',
          priority: 5,
          status: 'NEEDS-ACTION',
          recurrenceRevision: 0,
          percentComplete: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          sortOrder: i,
          serverRev: 0,
        ),
      );

      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentCommandTodosProvider.overrideWith((ref) => Stream.value([])),
            recentCommandEventsProvider.overrideWith((ref) => Stream.value([])),
            searchResultsProvider(
              'Bulk',
            ).overrideWith((ref) async => SearchResults([], todos)),
          ],
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
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Bulk');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Find the body container with key 'cmd-body'
      final bodyFinder = find.byKey(const ValueKey('cmd-body'));
      expect(bodyFinder, findsOneWidget);

      final bodyHeight = tester.getSize(bodyFinder).height;
      // Assert body height <= 390 per spec .cmd-body{max-height:390}
      expect(bodyHeight, lessThanOrEqualTo(390.0));
      expect(bodyHeight, equals(390.0));

      debugDefaultTargetPlatformOverride = null;
      router.dispose();
    },
  );

  testWidgets('empty state merges recent todos and events by recency', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final olderTodo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'Older task',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 1, 1),
      sortOrder: 0,
      serverRev: 0,
    );
    final newerEvent = Event(
      id: 2,
      calendarId: 1,
      summary: 'Newer event',
      startDt: DateTime(2026, 11, 22, 10),
      endDt: DateTime(2026, 11, 22, 11),
      isAllDay: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 11, 22),
      serverRev: 0,
    );

    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith(
            (ref) => Stream.value([olderTodo]),
          ),
          recentCommandEventsProvider.overrideWith(
            (ref) => Stream.value([newerEvent]),
          ),
        ],
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text(olderTodo.summary), findsOneWidget);
    expect(find.text(newerEvent.summary), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(newerEvent.summary)).dy,
      lessThan(tester.getTopLeft(find.text(olderTodo.summary)).dy),
      reason: 'the most recently updated item comes first',
    );
    expect(find.text('New Task'), findsOneWidget);

    router.dispose();
  });

  testWidgets('desktop command palette paints a scrim instead of paper', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          recentCommandEventsProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
        ],
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
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == SpecTokens.paper,
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color == const Color(0x3D191918),
      ),
      findsOneWidget,
    );

    router.dispose();
  });

  testWidgets('opening a result closes the palette before pushing the detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'Recent task to open',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 11, 22),
      sortOrder: 0,
      serverRev: 0,
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home route')),
        ),
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/todo/detail',
          builder: (_, __) =>
              const Scaffold(body: Text('Todo detail route')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith(
            (ref) => Stream.value([todo]),
          ),
          recentCommandEventsProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
        ],
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
      ),
    );
    await tester.pumpAndSettle();

    router.push('/search');
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);

    await tester.tap(find.text(todo.summary));
    await tester.pumpAndSettle();

    expect(find.text('Todo detail route'), findsOneWidget);
    expect(
      find.byType(SearchPage),
      findsNothing,
      reason: 'the command palette must not stay underneath the detail',
    );

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home route'), findsOneWidget);

    router.dispose();
  });

  testWidgets('opening a result from a shell page keeps one shell navigator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todo = Todo(
      id: 1,
      calendarId: 1,
      summary: 'Task from a shell page',
      priority: 5,
      status: 'NEEDS-ACTION',
      recurrenceRevision: 0,
      percentComplete: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 11, 22),
      sortOrder: 0,
      serverRev: 0,
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home route')),
        ),
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        ShellRoute(
          builder: (context, state, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, __) =>
                  const Scaffold(body: Text('Settings page')),
            ),
            GoRoute(
              path: '/todo/detail',
              builder: (_, __) =>
                  const Scaffold(body: Text('Todo detail route')),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith(
            (ref) => Stream.value([todo]),
          ),
          recentCommandEventsProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          todoTagsProvider(todo.id).overrideWith((ref) => Stream.value([])),
        ],
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
      ),
    );
    await tester.pumpAndSettle();

    router.push('/settings');
    await tester.pumpAndSettle();
    router.push('/search');
    await tester.pumpAndSettle();

    await tester.tap(find.text(todo.summary));
    await tester.pumpAndSettle();

    expect(find.text('Todo detail route'), findsOneWidget);
    expect(find.byType(SearchPage), findsNothing);
    expect(tester.takeException(), isNull);

    router.dispose();
  });

  testWidgets('a Chinese action prefix exposes actions with the remainder', (    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/event/new',
          builder: (_, state) => Scaffold(
            body: Text('event ${state.uri.queryParameters['summary']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentCommandTodosProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          recentCommandEventsProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          searchResultsProvider(
            '新建 周报',
          ).overrideWith((ref) async => SearchResults([], [])),
        ],
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
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '新建 周报');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('New Task'), findsOneWidget);
    expect(find.text('New Event'), findsOneWidget);
    expect(find.text('Title "周报"'), findsNWidgets(2));

    await tester.tap(find.text('New Event'));
    await tester.pumpAndSettle();
    expect(find.text('event 周报'), findsOneWidget);

    router.dispose();
  });

  testWidgets('eventCreate form seeds its title from initialSummary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, __) => EventFormPage(
                initialStart: DateTime(2026, 11, 22, 10),
                initialEnd: DateTime(2026, 11, 22, 11),
                initialSummary: '周报整理',
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == '周报整理',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    router.dispose();
  });
}
