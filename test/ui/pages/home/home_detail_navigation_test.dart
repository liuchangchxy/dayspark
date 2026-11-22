import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

GoRouter _router(int initialTab, {String? initialTodoView}) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => HomePage(
        initialTab: initialTab,
        initialTodoView: initialTodoView,
      ),
    ),
    GoRoute(
      path: '/todo/detail',
      builder: (_, __) => const Scaffold(
        body: Text('stub-todo-detail', key: ValueKey('stub-todo-detail')),
      ),
    ),
    GoRoute(
      path: '/event/detail',
      builder: (_, __) => const Scaffold(
        body: Text('stub-event-detail', key: ValueKey('stub-event-detail')),
      ),
    ),
  ],
);

Widget _app(AppDatabase db, GoRouter router) => ProviderScope(
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Finder _content(int tab) => find.byKey(ValueKey('workspace-content-$tab'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late int calId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Task 0',
            dueDate: Value(today),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('on narrow desktop (1000-1179) a todo tap opens 360 overlay drawer, below 1000 it navigates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, _router(2)));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );

    await tester.tap(find.text('Task 0'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('todo-detail-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('stub-todo-detail')), findsNothing);
    expect(container.read(workspaceSelectionProvider), isA<TodoSelection>());
    expect(tester.getSize(find.byKey(const ValueKey('spec-drawer-overlay'))).width, equals(360.0));

    // Below 1000, it navigates
    container.read(workspaceSelectionProvider.notifier).state = null;
    tester.view.physicalSize = const Size(880, 900);
    await tester.pump();
    await _settle(tester);

    await tester.tap(find.text('Task 0'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('stub-todo-detail')), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('on Today a todo tap opens overlay drawer on desktop and navigates on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, _router(0)));
    await _settle(tester);
    expect(_content(0), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );

    // Initial content width before drawer opens
    final initialContentWidth = tester.getSize(_content(0)).width;
    expect(initialContentWidth, equals(1440.0));

    await tester.tap(find.text('Task 0'));
    await _settle(tester);

    // Desktop Today: opens 380 overlay drawer without squeezing content
    expect(find.byKey(const ValueKey('todo-detail-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('stub-todo-detail')), findsNothing);
    expect(container.read(workspaceSelectionProvider), isA<TodoSelection>());
    final drawerRect = tester.getRect(find.byKey(const ValueKey('spec-drawer-overlay')));
    expect(drawerRect.width, equals(380.0));
    expect(drawerRect.right, equals(1440.0));
    expect(tester.getSize(_content(0)).width, equals(1440.0)); // List width unchanged!

    // Tap blank space closes drawer
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await _settle(tester);
    expect(find.byKey(const ValueKey('todo-detail-title')), findsNothing);
    expect(container.read(workspaceSelectionProvider), isNull);

    // Mobile: navigates
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await _settle(tester);

    await tester.tap(find.text('Task 0'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('stub-todo-detail')), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('an event tap on the Todo destination fills the detail pane', (
    tester,
  ) async {
    final now = DateTime.now();
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calId,
            summary: 'Standup',
            startDt: DateTime(now.year, now.month, now.day, 10),
            endDt: DateTime(now.year, now.month, now.day, 11),
          ),
        );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(db, _router(2, initialTodoView: 'date')),
    );
    await _settle(tester);

    await tester.tap(find.text('Standup'));
    await _settle(tester);

    expect(find.byType(EventDetailPane), findsOneWidget);
    expect(find.byKey(const ValueKey('stub-event-detail')), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(workspaceSelectionProvider), isA<EventSelection>());

    await _unmount(tester);
  });

  testWidgets('on Calendar an event tap opens 380 overlay drawer without squeezing', (
    tester,
  ) async {
    final now = DateTime.now();
    await db.into(db.events).insert(
      EventsCompanion.insert(
        calendarId: calId,
        summary: 'Team Sync',
        startDt: DateTime(now.year, now.month, now.day, 14),
        endDt: DateTime(now.year, now.month, now.day, 15),
      ),
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, _router(1)));
    await _settle(tester);
    expect(_content(1), findsOneWidget);

    final initialCalendarWidth = tester.getSize(_content(1)).width;
    expect(initialCalendarWidth, equals(1440.0));

    await tester.tap(find.text('Team Sync'));
    await _settle(tester);

    expect(find.byType(EventDetailPane), findsOneWidget);
    expect(find.byKey(const ValueKey('stub-event-detail')), findsNothing);
    final drawerRect = tester.getRect(find.byKey(const ValueKey('spec-drawer-overlay')));
    expect(drawerRect.width, equals(380.0));
    expect(tester.getSize(_content(1)).width, equals(1440.0));

    // Close button X closes drawer
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await _settle(tester);

    expect(find.byType(EventDetailPane), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(workspaceSelectionProvider), isNull);

    await _unmount(tester);
  });

  testWidgets('Escape closes the desktop detail pane', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, _router(2)));
    await _settle(tester);
    await tester.tap(find.text('Task 0'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('todo-detail-title')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const ValueKey('todo-detail-title')), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(workspaceSelectionProvider), isNull);

    await _unmount(tester);
  });

  testWidgets('system back on a non-Today destination returns to Today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, _router(0)));
    await _settle(tester);

    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    expect(_content(2), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_content(0), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Today has a read-only date; the month view pages by month', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'calendar_view_mode': 'month'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = _router(0);
    await tester.pumpWidget(_app(db, router));
    await _settle(tester);

    expect(find.byTooltip('Previous day'), findsNothing);
    expect(find.byTooltip('Next day'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    await container
        .read(calendarViewModeProvider.notifier)
        .setViewMode(CalendarViewMode.month);
    container.read(viewedDateProvider.notifier).state = DateTime(2026, 1, 31);
    await tester.tap(find.text('Calendar').first);
    await _settle(tester);
    expect(_content(1), findsOneWidget);

    await tester.tap(find.byTooltip('Next').first);
    await tester.pump();

    final viewed = container.read(viewedDateProvider);
    expect(viewed.year, 2026);
    expect(viewed.month, 2);
    expect(viewed.day, 28);

    await _unmount(tester);
  });

  testWidgets('Undo reopens the occurrence that was completed', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(now.year, now.month, now.day),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=40',
    );
    await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Daily standup',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    await tester.pumpWidget(_app(db, _router(0)));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    container.read(todosViewProvider.notifier).state = const TodosInboxView();
    await _settle(tester);
    expect(find.text('Daily standup'), findsOneWidget);

    final row = find.ancestor(
      of: find.text('Daily standup'),
      matching: find.byWidgetPredicate(
        (w) => w is A2Row || w.runtimeType.toString() == 'SpecTaskRow',
      ),
    );
    await tester.tap(find.descendant(of: row, matching: find.byType(DsCheck)));
    await _settle(tester);
    expect(find.text('Select occurrence'), findsOneWidget);

    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await _settle(tester);

    final completed = (await db.select(db.taskInstanceStates).get())
        .where((state) => state.status == 'completed')
        .map((state) => state.occurrenceId)
        .toSet();
    expect(completed, isNotEmpty);

    // Undo must not ask which occurrence again: it reopens the one the
    // completion actually wrote. The row now offers that undo in place, next
    // to the SnackBar's, so the row's own key is the one to press.
    await tester.tap(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is A2Row || w.runtimeType.toString() == 'SpecTaskRow',
            ),
            matching: find.text('Undo'),
          )
          .first,
    );
    await _settle(tester);

    expect(find.text('Select occurrence'), findsNothing);
    final reopened = await db.select(db.taskInstanceStates).get();
    for (final occurrenceId in completed) {
      expect(
        reopened
            .singleWhere((state) => state.occurrenceId == occurrenceId)
            .status,
        isNot('completed'),
      );
    }

    await _unmount(tester);
  });

  testWidgets('a calendar slot opens the composer with that slot prefilled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, _router(0)));
    await _settle(tester);
    await tester.tap(find.text('Calendar').last);
    await _settle(tester);

    // Every day column is one tap target that resolves to the half-hour slot
    // under the pointer.
    final grid = find.byType(A2TimeGridView);
    expect(grid, findsOneWidget);
    final rect = tester.getRect(grid);
    await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.6));
    await _settle(tester);

    expect(find.text('New & schedule'), findsOneWidget);
    final rangeLabel = tester
        .widgetList<Text>(find.textContaining('–'))
        .map((text) => text.data ?? '')
        .firstWhere((data) => data.contains('·'));
    // The sheet head is now two lines: the date is the fact, the range sits on
    // the subline ahead of its "default length" tag. The span is the first
    // segment of the subline, not the last.
    final span = rangeLabel.split('·').first.trim();

    await tester.tap(find.text('New & schedule'));
    await _settle(tester);

    expect(find.byType(A2ComposerSheet), findsOneWidget);
    expect(find.textContaining(span), findsOneWidget);

    await _unmount(tester);
  });
}
