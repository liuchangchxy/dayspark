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
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

(GoRouter, Widget) _app(
  AppDatabase db,
  Widget Function() form, {
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('list')),
      ),
      GoRoute(path: '/todo/edit', builder: (_, __) => form()),
    ],
  );
  return (
    router,
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), ...overrides],
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
}

Future<void> _open(WidgetTester tester, GoRouter router, Widget app) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await _settle(tester);
  router.push('/todo/edit');
  await _settle(tester);
}

Future<Todo> _row(AppDatabase db, int id) =>
    (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late Todo todo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Original title',
            dueDate: Value(DateTime(2026, 10, 30, 18)),
          ),
        );
    todo = await _row(db, id);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('a failed association read blocks Save until retried', (
    tester,
  ) async {
    var fail = true;
    final (router, app) = _app(
      db,
      () => TodoFormPage(todo: todo),
      overrides: [
        todoTagsProvider(todo.id).overrideWith(
          (ref) => fail
              ? Stream<List<Tag>>.error(StateError('tags failed'))
              : Stream<List<Tag>>.value(const []),
        ),
      ],
    );
    await _open(tester, router, app);

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.byType(TodoFormPage), findsOneWidget);
    expect((await _row(db, todo.id)).summary, 'Original title');

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(
      find.text('Discard changes?'),
      findsOneWidget,
      reason: 'an unloaded form has no honest baseline to discard',
    );
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);

    fail = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Recovered title');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect((await _row(db, todo.id)).summary, 'Recovered title');
    await _unmount(tester);
  });

  testWidgets('the completion checkbox is a draft until Save', (tester) async {
    final (router, app) = _app(db, () => TodoFormPage(todo: todo));
    await _open(tester, router, app);

    await tester.tap(find.byType(DsCheck).first);
    await tester.pump();
    expect(
      (await _row(db, todo.id)).status,
      'NEEDS-ACTION',
      reason: 'ticking the box must not write before Save',
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);
    expect((await _row(db, todo.id)).status, 'NEEDS-ACTION');

    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect((await _row(db, todo.id)).status, 'COMPLETED');
    await _unmount(tester);
  });

  testWidgets('saving a recurring completion reuses the occurrence picker', (
    tester,
  ) async {
    final calendarId = (await db.select(db.calendars).get()).first.id;
    final now = DateTime.now();
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(now.year, now.month, now.day),
      ),
      timeZone: 'UTC',
      rrule: 'FREQ=DAILY;COUNT=5',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Daily standup',
          startDate: Value(DateTime(now.year, now.month, now.day)),
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );
    final series = await _row(db, seriesId);

    final (router, app) = _app(db, () => TodoFormPage(todo: series));
    await _open(tester, router, app);

    await tester.tap(find.byType(DsCheck).first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final states = await db.select(db.taskInstanceStates).get();
    expect(states, hasLength(1));
    expect(states.single.status, 'completed');
    await _unmount(tester);
  });

  testWidgets('a new series refuses a draft block and keeps it removable', (
    tester,
  ) async {
    final (router, app) = _app(
      db,
      () => TodoFormPage(
        initialSummary: 'Water plants',
        initialDueDate: DateTime(2026, 10, 17, 9),
        initialExecutionStart: DateTime(2026, 10, 17, 14),
        initialExecutionEnd: DateTime(2026, 10, 17, 15),
      ),
    );
    await _open(tester, router, app);

    expect(find.text('Add execution time'), findsOneWidget);

    await tester.tap(find.text('Does not repeat'));
    await _settle(tester);
    await tester.tap(find.text('Every day'));
    await _settle(tester);
    await tester.tap(find.text('Done'));
    await _settle(tester);

    expect(
      find.text('Add execution time'),
      findsNothing,
      reason: 'a new series has no occurrence to bind a block to yet',
    );
    expect(
      find.text('Save · Give an existing task a time here'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(
      (await db.select(db.todos).get()).where(
        (row) => row.summary == 'Water plants',
      ),
      isEmpty,
      reason: 'the block must be resolved, not silently dropped',
    );

    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    await tester.tap(find.byTooltip('Cancel scheduled time'));
    await _settle(tester);
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final saved = (await db.select(db.todos).get())
        .where((row) => row.summary == 'Water plants')
        .toList();
    expect(saved, hasLength(1));
    expect(saved.single.summary, 'Water plants');
    expect(saved.single.rrule, contains('FREQ=DAILY'));
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    await _unmount(tester);
  });
}
