import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/writers/task_allocation_writer.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';

Widget _app(
  AppDatabase db,
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db), ...overrides],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
}

Widget _routerApp(AppDatabase db, GoRouter router) {
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
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  var calendarId = 0;
  final day = DateTime(2026, 10, 17);

  setUp(() async {
    // The recurrence resolver reads the device zone from preferences.
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Personal',
            color: const Value('#2563EB'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('opens on pure capture and promises what save will do', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(db, A2ComposerSheet(contextDate: _DayContext.value)),
    );
    await _settle(tester);

    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('No slot chosen'), findsOneWidget);
    expect(
      find.text('Saving without a slot files this under Unplanned.'),
      findsOneWidget,
    );
    // Nothing typed yet: the disabled button asks for the missing input
    // instead of promising a save it cannot perform.
    expect(find.text('Save to Unplanned'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'What needs doing?'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Write the retro',
    );
    await tester.pump();
    expect(find.text('Save to Unplanned'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('choosing a slot changes the promise and writes an allocation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Write the retro',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();

    expect(find.text('09:00–10:00'), findsOneWidget);
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    expect(find.text('Plan for 10/17 14:00–15:00'), findsOneWidget);
    expect(
      find.text(
        'This is a planned execution, not a deadline. '
        'Set the deadline separately.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Plan for 10/17 14:00–15:00'));
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Write the retro');
    // A slot is not a deadline: dueDate stays null.
    expect(todos.single.dueDate, isNull);
    final allocations = await db.select(db.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.todoId, todos.single.id);
    expect(allocations.single.startAt.toLocal(), DateTime(2026, 10, 17, 14));
    expect(allocations.single.endAt.toLocal(), DateTime(2026, 10, 17, 15));
    expect(calendarId, greaterThan(0));

    await _unmount(tester);
  });

  testWidgets(
    'failed allocation rolls back capture and retry creates one todo',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var fail = true;
      final override = createTaskAllocationProvider.overrideWith(
        (ref) =>
            ({
              required todoId,
              required startAt,
              required endAt,
              occurrenceId,
            }) async {
              if (fail) throw StateError('allocation failed');
              return RecordScope.run(
                db,
                (tx) => TaskAllocationWriter.create(
                  db,
                  tx,
                  todoId: todoId,
                  startAt: startAt,
                  endAt: endAt,
                  occurrenceId: occurrenceId,
                ),
              );
            },
      );
      await tester.pumpWidget(
        _app(db, A2ComposerSheet(contextDate: day), overrides: [override]),
      );
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('a2-composer-title')),
        'Retry me',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
      await tester.pump();
      await tester.tap(find.text('14:00–15:00'));
      await tester.pump();
      await tester.tap(find.text('Plan for 10/17 14:00–15:00'));
      await _settle(tester);
      expect(await db.select(db.todos).get(), isEmpty);
      expect(await db.select(db.taskAllocations).get(), isEmpty);
      expect(find.text('Retry me'), findsOneWidget);
      expect(find.text('Plan for 10/17 14:00–15:00'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Plan for 10/17 14:00–15:00'));
      await _settle(tester);
      expect(await db.select(db.todos).get(), hasLength(1));
      expect(await db.select(db.taskAllocations).get(), hasLength(1));
      await _unmount(tester);
    },
  );
  testWidgets('a recurring todo asks which occurrence the slot is for', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final todo = await _recurringTodo(db, calendarId);

    await tester.pumpWidget(
      _app(db, A2ComposerSheet(contextDate: day, todo: todo)),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();
    await tester.tap(find.text('Plan to 10/17 14:00–15:00'));
    await _settle(tester);

    // The writer refuses an allocation without an occurrence, so the sheet
    // asks for one and nothing is written until it is chosen.
    expect(find.text('Could not complete. Please try again.'), findsNothing);
    // The sheet is a dialog either way: a legacy rule is confirmed first,
    // a zoned series goes straight to the occurrence list.
    expect(find.byType(Dialog), findsOneWidget);
    expect(await db.select(db.taskAllocations).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets(
    'scheduling an existing todo needs a slot and writes no deadline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
          );
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();

      await tester.pumpWidget(
        _app(db, A2ComposerSheet(contextDate: day, todo: todo)),
      );
      await _settle(tester);

      expect(find.text('Call mum'), findsOneWidget);
      // Nothing to save until a slot is chosen.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
      await tester.pump();
      await tester.tap(find.text('16:00–17:00'));
      await tester.pump();
      await tester.tap(find.text('Plan to 10/17 16:00–17:00'));
      await _settle(tester);

      final refreshed = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      expect(refreshed.dueDate, isNull);
      final allocations = await db.select(db.taskAllocations).get();
      expect(allocations, hasLength(1));
      expect(allocations.single.startAt.toLocal(), DateTime(2026, 10, 17, 16));

      await _unmount(tester);
    },
  );

  testWidgets(
    'scheduling mode disables the full-form exit instead of dropping the slot',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todo = await _recurringTodo(db, calendarId);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, __) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showA2Composer(
                    context,
                    contextDate: _DayContext.value,
                    todo: todo,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(_routerApp(db, router));
      await _settle(tester);

      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.byType(A2ComposerSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
      await tester.pump();
      await tester.tap(find.text('14:00–15:00'));
      await tester.pump();

      // The full form cannot carry the chosen slot for an existing todo, so the
      // exit is disabled rather than silently discarding it.
      final ellipsis = tester.widget<TextButton>(
        find.descendant(
          of: find.byType(A2ComposerSheet),
          matching: find.byType(TextButton),
        ),
      );
      expect(ellipsis.onPressed, isNull);
      expect(
        find.byTooltip('Give an existing task a time here'),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(A2ComposerSheet),
          matching: find.byType(TextButton),
        ),
      );
      await _settle(tester);
      expect(router.state.uri.path, '/');
      expect(find.byType(A2ComposerSheet), findsOneWidget);
      expect(find.text('Plan to 10/17 14:00–15:00'), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('create mode "…" still carries the chosen slot to the form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showA2Composer(context, contextDate: _DayContext.value),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/todo/new',
          builder: (_, __) => const Scaffold(body: Text('full form')),
        ),
      ],
    );
    await tester.pumpWidget(_routerApp(db, router));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Weekly review',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(A2ComposerSheet),
        matching: find.byIcon(CupertinoIcons.ellipsis),
      ),
    );
    await _settle(tester);

    expect(router.state.uri.path, '/todo/new');
    expect(
      router.state.uri.queryParameters['start'],
      '${DateTime(2026, 10, 17, 14).millisecondsSinceEpoch}',
    );
    expect(
      router.state.uri.queryParameters['end'],
      '${DateTime(2026, 10, 17, 15).millisecondsSinceEpoch}',
    );
    expect(router.state.uri.queryParameters['summary'], 'Weekly review');

    await _unmount(tester);
  });

  testWidgets('a chosen slot shows its date and tapping it again clears it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Write the retro',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    // A bare clock time on another day is the classic way to misread a slot.
    expect(find.text('10/17 14:00–15:00'), findsOneWidget);
    expect(find.text('Plan for 10/17 14:00–15:00'), findsOneWidget);

    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    expect(find.text('No slot chosen'), findsOneWidget);
    expect(find.text('Save to Unplanned'), findsOneWidget);

    await tester.tap(find.text('Save to Unplanned'));
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(await db.select(db.taskAllocations).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets('the custom slot chip is reversible too', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        db,
        A2ComposerSheet(
          contextDate: day,
          initialStart: DateTime(2026, 10, 17, 11),
          initialEnd: DateTime(2026, 10, 17, 12),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('10/17 11:00–12:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();

    await tester.tap(find.text('Custom…'));
    await tester.pump();

    expect(find.text('No slot chosen'), findsOneWidget);
    expect(find.text('10/17 11:00–12:00'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('a deadline and a slot are both named by the primary button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Send the report',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);

    await tester.tap(find.byKey(const ValueKey('a2-composer-due')));
    await _settle(tester);
    await tester.tap(find.text('17'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await tester.tap(find.text('Date only'));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    // Both writes happen, so the button must name both.
    expect(find.text('Save (Plan 14:00–15:00 · Due 10/17)'), findsOneWidget);

    await tester.tap(find.text('Save (Plan 14:00–15:00 · Due 10/17)'));
    await _settle(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.dueDate, DateTime(2026, 10, 17));
    final allocations = await db.select(db.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.startAt.toLocal(), DateTime(2026, 10, 17, 14));

    await _unmount(tester);
  });

  testWidgets('scheduling mode cannot edit reminder, calendar or priority', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();

    await tester.pumpWidget(
      _app(db, A2ComposerSheet(contextDate: day, todo: todo)),
    );
    await _settle(tester);

    // These rows look editable but a scheduling save only writes the
    // allocation, so they must not be shown at all.
    expect(find.byKey(const ValueKey('a2-composer-reminder')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-calendar')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-priority')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-notes')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-plan')), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets(
    '"No reminder" clears a choice while dismissing the picker keeps it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('a2-composer-title')),
        'Water the plants',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
      await tester.pump();
      await tester.tap(find.text('14:00–15:00'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('a2-composer-reminder')));
      await _settle(tester);
      await tester.tap(find.text('On time'));
      await _settle(tester);
      expect(find.text('On time'), findsOneWidget);

      // Dismissing the picker is not a choice: the reminder stays.
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
      expect(find.text('On time'), findsOneWidget);

      // Choosing "No reminder" is a choice, and it must survive the pop.
      await tester.tap(find.byKey(const ValueKey('a2-composer-reminder')));
      await _settle(tester);
      await tester.tap(find.text('No reminder'));
      await _settle(tester);
      expect(find.text('No reminder'), findsOneWidget);

      await tester.tap(find.text('Plan for 10/17 14:00–15:00'));
      await _settle(tester);

      expect(await db.select(db.reminders).get(), isEmpty);

      await _unmount(tester);
    },
  );

  testWidgets('the calendar row is the shared picker and can create one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-calendar')));
    await _settle(tester);

    // One calendar is not a reason to hide the picker; the create entry is how
    // a second one becomes possible.
    expect(find.text('Personal'), findsWidgets);
    expect(find.text('+ New calendar'), findsOneWidget);

    await tester.tap(find.text('+ New calendar'));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(DsDialog),
        matching: find.byType(TextField),
      ),
      'Work',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.byType(DsDialog), findsNothing);

    expect(find.text('Work'), findsWidgets);
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Write the retro',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Save to Unplanned'));
    await _settle(tester);
    expect(find.text("That didn't work. Please try again."), findsNothing);

    final work = await (db.select(
      db.calendars,
    )..where((row) => row.name.equals('Work'))).getSingle();
    final todo = (await db.select(db.todos).get()).single;
    expect(todo.calendarId, work.id);

    await _unmount(tester);
  });

  testWidgets('escape closes the sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showA2Composer(context, contextDate: _DayContext.value),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(_routerApp(db, router));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.byType(A2ComposerSheet), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    expect(find.byType(A2ComposerSheet), findsNothing);

    await _unmount(tester);
  });

  testWidgets('escape closes the scheduling sheet too', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showA2Composer(
                  context,
                  contextDate: _DayContext.value,
                  todo: todo,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(_routerApp(db, router));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.byType(A2ComposerSheet), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    expect(find.byType(A2ComposerSheet), findsNothing);

    await _unmount(tester);
  });

  testWidgets('rows and slot chips are keyboard-activatable ink targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('a2-composer-plan')),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('a2-composer-reminder')),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('09:00–10:00'),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets('the overflow button opens the full page with the typed title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        _openComposerRoute(),
        GoRoute(
          path: '/todo/new',
          builder: (_, __) => const Scaffold(body: Text('full form')),
        ),
      ],
    );
    await tester.pumpWidget(_routerApp(db, router));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Weekly review',
    );
    await tester.pump();

    // Notes are no longer a capture field: the overflow button is the one
    // path from the sheet to the full page, and it carries the typed title.
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await _settle(tester);

    expect(router.state.uri.path, '/todo/new');
    expect(router.state.uri.queryParameters['summary'], 'Weekly review');

    await _unmount(tester);
  });

  testWidgets(
    'desktop presents a centred dialog with a keyboard path to save',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/',
        routes: [_openComposerRoute()],
      );
      await tester.pumpWidget(_routerApp(db, router));
      await _settle(tester);
      await tester.tap(find.text('open'));
      await _settle(tester);

      // Desktop gets a dialog, not a phone sheet stretched across the window.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'What needs doing?'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('a2-composer-title')),
        'Desktop task',
      );
      await tester.pump();

      // Title -> deadline -> plan -> reminder -> calendar -> priority -> more
      // -> primary. Each stop has to exist, or Enter lands elsewhere.
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(find.byType(A2ComposerSheet), findsNothing);
      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(1));
      expect(todos.single.summary, 'Desktop task');

      await _unmount(tester);
    },
  );

  testWidgets('desktop dialog keeps Tab inside and closes on Escape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [_openComposerRoute()],
    );
    await tester.pumpWidget(_routerApp(db, router));
    await _settle(tester);
    await tester.tap(find.text('open'));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-title')));
    await tester.pump();
    // The stop before the title is the dialog's close button. If Tab had
    // escaped to the page behind the dialog, Enter would re-open the composer
    // instead of closing it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.byType(A2ComposerSheet), findsNothing);

    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.byType(A2ComposerSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(A2ComposerSheet), findsNothing);

    await _unmount(tester);
  });

  test('the full form is handed everything the sheet already took', () {
    final route = composerCreateRoute(
      due: DateTime(2026, 10, 17, 18),
      start: DateTime(2026, 10, 17, 16),
      end: DateTime(2026, 10, 17, 17),
      summary: 'Weekly review',
    );
    final uri = Uri.parse(route);
    expect(uri.path, '/todo/new');
    expect(
      uri.queryParameters['due'],
      '${DateTime(2026, 10, 17, 18).millisecondsSinceEpoch}',
    );
    expect(
      uri.queryParameters['start'],
      '${DateTime(2026, 10, 17, 16).millisecondsSinceEpoch}',
    );
    expect(
      uri.queryParameters['end'],
      '${DateTime(2026, 10, 17, 17).millisecondsSinceEpoch}',
    );
    expect(uri.queryParameters['summary'], 'Weekly review');

    // A sheet with nothing but a title still opens the bare form.
    expect(composerCreateRoute(), '/todo/new');
    expect(composerCreateRoute(summary: '  '), '/todo/new');
  });

  testWidgets('the six promise states each say exactly what is written', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Six states',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // nothing
    expect(find.text('Save to Unplanned'), findsOneWidget);

    // slot only
    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();
    expect(find.text('Plan for 10/17 14:00–15:00'), findsOneWidget);

    // both: plan first, then the deadline, and no repeated date.
    await tester.tap(find.byKey(const ValueKey('a2-composer-due')));
    await _settle(tester);
    await tester.tap(find.text('17'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await tester.tap(find.text('Date only'));
    await _settle(tester);
    expect(find.text('Save (Plan 14:00–15:00 · Due 10/17)'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('due only keeps the deadline-only promise', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Due only',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);

    await tester.tap(find.byKey(const ValueKey('a2-composer-due')));
    await _settle(tester);
    await tester.tap(find.text('17'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await tester.tap(find.text('Date only'));
    await _settle(tester);

    expect(find.text('Save (due 10/17)'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets(
    'switching to scheduling keeps the typed fields and drops the bind',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
          );
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();

      await tester.pumpWidget(
        _app(db, A2ComposerSheet(contextDate: day, todo: todo)),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
      await tester.pump();
      await tester.tap(find.text('14:00–15:00'));
      await tester.pump();
      expect(find.text('Plan to 10/17 14:00–15:00'), findsOneWidget);

      // Back to create: the title unlocks, the verb becomes "save", and the slot
      // the user already picked survives the switch.
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(find.byKey(const ValueKey('a2-composer-title')), findsOneWidget);
      expect(find.text('Call mum'), findsOneWidget);
      expect(find.text('Plan for 10/17 14:00–15:00'), findsOneWidget);

      // And forward again: the todo comes back bound, the slot is still there.
      await tester.tap(find.text('Schedule Task'));
      await tester.pump();
      expect(find.text('Plan to 10/17 14:00–15:00'), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('a failed write keeps the draft, marks it, and retries once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var fail = true;
    final override = createTaskAllocationProvider.overrideWith(
      (ref) =>
          ({
            required todoId,
            required startAt,
            required endAt,
            occurrenceId,
          }) async {
            if (fail) throw StateError('allocation failed');
            return RecordScope.run(
              db,
              (tx) => TaskAllocationWriter.create(
                db,
                tx,
                todoId: todoId,
                startAt: startAt,
                endAt: endAt,
                occurrenceId: occurrenceId,
              ),
            );
          },
    );
    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();

    await tester.pumpWidget(
      _app(
        db,
        A2ComposerSheet(contextDate: day, todo: todo),
        overrides: [override],
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();
    await tester.tap(find.text('Plan to 10/17 14:00–15:00'));
    await _settle(tester);

    // Nothing written, nothing closed, nothing lost.
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    expect(find.byType(A2ComposerSheet), findsOneWidget);
    expect(find.text('Call mum'), findsOneWidget);
    expect(find.text('Plan to 10/17 14:00–15:00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('a2-composer-write-failed')),
      findsOneWidget,
    );

    fail = false;
    await tester.tap(find.text('Plan to 10/17 14:00–15:00'));
    await _settle(tester);

    expect(await db.select(db.taskAllocations).get(), hasLength(1));
    expect(
      find.byKey(const ValueKey('a2-composer-write-failed')),
      findsNothing,
    );

    await _unmount(tester);
  });

  testWidgets('scheduling names a moved deadline and writes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();

    await tester.pumpWidget(
      _app(db, A2ComposerSheet(contextDate: day, todo: todo)),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-due')));
    await _settle(tester);
    await tester.tap(find.text('17'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await tester.tap(find.text('Date only'));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('14:00–15:00'));
    await tester.pump();

    expect(
      find.text('Schedule (Plan 14:00–15:00 · Due 10/17)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Schedule (Plan 14:00–15:00 · Due 10/17)'));
    await _settle(tester);

    final refreshed = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();
    expect(refreshed.dueDate, DateTime(2026, 10, 17));
    expect(await db.select(db.taskAllocations).get(), hasLength(1));

    await _unmount(tester);
  });

  testWidgets('a scheduled write moves the browsed day to the slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.read(viewedDateProvider.notifier).state = DateTime(2026, 10, 1);

    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(calendarId: calendarId, summary: 'Call mum'),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showA2Composer(context, contextDate: day, todo: todo),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    await _settle(tester);
    await tester.tap(find.text('open'));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();
    await tester.tap(find.text('16:00–17:00'));
    await tester.pump();
    await tester.tap(find.text('Plan to 10/17 16:00–17:00'));
    await _settle(tester);

    // The sheet closes, the browsed day follows the block, and the toast says
    // where it went — otherwise the user stays on 10/1 and has to hunt.
    expect(find.byType(A2ComposerSheet), findsNothing);
    expect(container.read(viewedDateProvider), DateTime(2026, 10, 17));
    expect(find.text('Plan to 10/17'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('custom slot opens SpecPlanPicker and backfills slot on submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Deep work',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();

    await tester.tap(find.text('Custom…'));
    await tester.pumpAndSettle();

    expect(find.byType(SpecPlanPicker), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();

    expect(find.byType(SpecPlanPicker), findsNothing);
    expect(find.text('Plan for 10/17 09:00–10:00'), findsOneWidget);

    await tester.tap(find.text('Plan for 10/17 09:00–10:00'));
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    expect(todos.single.summary, 'Deep work');
    expect(todos.single.dueDate, isNull);

    final allocations = await db.select(db.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.todoId, todos.single.id);
    expect(allocations.single.startAt.toLocal(), DateTime(2026, 10, 17, 9));
    expect(allocations.single.endAt.toLocal(), DateTime(2026, 10, 17, 10));

    await _unmount(tester);
  });

  testWidgets('a time phrase is a visible suggestion, never a silent type change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      '明天下午三点交报告',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('a2-composer-suggestion')),
      findsOneWidget,
    );
    expect(find.text('Type remains Task'), findsOneWidget);
    expect(find.textContaining('Suggested Plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('a2-composer-suggestion-type')),
      findsOneWidget,
    );
    // The fact sheet is still a Todo: due and priority remain reachable.
    expect(find.byKey(const ValueKey('a2-composer-due')), findsOneWidget);
    expect(find.byKey(const ValueKey('a2-composer-priority')), findsOneWidget);

    // "Done" on the title does not write the raw sentence on the spot.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(await db.select(db.todos).get(), isEmpty);

    await tester.tap(find.byType(FilledButton));
    await _settle(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.summary, '交报告');
    expect(todo.dueDate, isNull);
    final allocation = (await db.select(db.taskAllocations).get()).single;
    expect(allocation.startAt.toLocal().hour, 15);
    expect(allocation.endAt.toLocal().hour, 16);

    await _unmount(tester);
  });

  testWidgets('removing the suggestion writes only a clean title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      '明天下午三点交报告',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('a2-composer-suggestion-toggle')),
    );
    await tester.pump();
    expect(find.text('Time suggestion removed'), findsOneWidget);
    expect(find.text('No slot chosen'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await _settle(tester);

    final todo = (await db.select(db.todos).get()).single;
    expect(todo.summary, '交报告');
    expect(todo.dueDate, isNull);
    expect(await db.select(db.taskAllocations).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets('changing to an event writes event fields, not a todo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      '明天下午三点交报告',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('a2-composer-suggestion-type')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('a2-composer-event-time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('a2-composer-change-to-todo')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('a2-composer-due')), findsNothing);
    expect(find.byKey(const ValueKey('a2-composer-priority')), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await _settle(tester);

    final event = (await db.select(db.events).get()).single;
    expect(event.summary, '交报告');
    expect(event.startDt.toLocal().hour, 15);
    expect(event.endDt.toLocal().hour, 16);
    expect(event.isAllDay, isFalse);
    expect(await db.select(db.todos).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets('closing a dirty capture asks before throwing the draft away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Half-written thought',
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Discard this input?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await _settle(tester);
    expect(find.byType(A2ComposerSheet), findsOneWidget);
    expect(find.text('Half-written thought'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
    await _settle(tester);
    expect(find.text('Discard this input?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(A2ComposerSheet), findsNothing);

    await _unmount(tester);
  });

  testWidgets('a custom slot reports the blocks it overlaps', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Deep work block',
            startDt: DateTime(2026, 10, 17, 9, 30),
            endDt: DateTime(2026, 10, 17, 10, 30),
          ),
        );

    await tester.pumpWidget(_app(db, A2ComposerSheet(contextDate: day)));
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Deep work',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await tester.pump();

    await tester.tap(find.text('Custom…'));
    await tester.pumpAndSettle();

    // The picker reads the chosen day's real blocks: the default 09:00–10:00
    // span overlaps the 09:30 block and must say so instead of "No conflict".
    expect(find.byType(SpecPlanPicker), findsOneWidget);
    expect(find.textContaining('1 item overlaps'), findsOneWidget);
    expect(find.textContaining('Deep work block'), findsOneWidget);
    expect(find.textContaining('No time conflict'), findsNothing);

    await _unmount(tester);
  });
}

GoRoute _openComposerRoute() => GoRoute(
  path: '/',
  builder: (context, __) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () =>
            showA2Composer(context, contextDate: _DayContext.value),
        child: const Text('open'),
      ),
    ),
  ),
);

/// Seeds a real recurring series (the writer fills every recurrence column;
/// a bare rrule insert is "partial persistence" and cannot be projected).
Future<Todo> _recurringTodo(AppDatabase db, int calendarId) async {
  final spec = RecurrenceSpec.parse(
    anchor: RecurrenceAnchor(
      source: RecurrenceAnchorSource.start,
      value: LocalDate(2026, 10, 1),
    ),
    timeZone: 'Asia/Shanghai',
    rrule: 'FREQ=DAILY;COUNT=40',
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
  return (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();
}

/// Const stand-in so the first case can be `const`.
abstract final class _DayContext {
  static final DateTime value = DateTime(2026, 10, 17);
}
