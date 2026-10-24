import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Save means "the bundle I was just looking at", not "as much of it as the
/// database would take". The form used to write the row, then each association
/// in turn, swallowing every failure and leaving anyway — so a title that
/// landed with an attachment that did not looked like a successful save.
(GoRouter, Widget) _app(AppDatabase db, {Todo? todo, CalendaEventAdapter? event, List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('list'))),
      GoRoute(
        path: '/todo/edit',
        builder: (_, __) => TodoFormPage(todo: todo),
      ),
      GoRoute(
        path: '/event/new',
        builder: (_, __) => EventFormPage(
          event: event,
          initialStart: DateTime(2026, 11, 1, 9),
          initialEnd: DateTime(2026, 11, 1, 10),
        ),
      ),
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// A reminder write that always fails — standing in for anything that can go
/// wrong late in a draft, which is exactly where the old code gave up.
Override _failingReminderWrites() => createReminderProvider.overrideWith(
  (ref) =>
      ({
        required parentType,
        required parentId,
        required triggerTime,
      }) async => throw StateError('reminder write refused'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  setUp(() async {
    // forTesting seeds one calendar already; a second would make the
    // "which calendar?" step appear in tests that are not about it.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('a failing late write takes the whole edit down with it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calendarId = (await db.select(db.calendars).get()).single.id;
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Original title',
            dueDate: Value(DateTime(2026, 10, 30, 18)),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    final (router, app) = _app(
      db,
      todo: todo,
      overrides: [_failingReminderWrites()],
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/todo/edit');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Renamed by the user');
    await tester.pump();

    // Add a reminder so the commit has a failing write after the row itself.
    // Stage a reminder: the sheet is where the choice is made, and until it
    // is made the draft has nothing extra to write.
    await tester.tap(find.text('Add Reminder'));
    await _settle(tester);
    await tester.tap(find.text('On time'));
    await _settle(tester);
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'the reminder is staged and the sheet is gone',
    );

    await tester.tap(find.text('Save'));
    await _settle(tester);

    final after = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(
      after.summary,
      'Original title',
      reason: 'the title must not land if the rest of the draft did not',
    );
    expect(
      find.byType(TodoFormPage),
      findsOneWidget,
      reason: 'the form stays open so the user can retry or fix the draft',
    );
    expect(find.text('list'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a clean save still writes the whole edit', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calendarId = (await db.select(db.calendars).get()).single.id;
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Original title',
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    final (router, app) = _app(db, todo: todo);
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/todo/edit');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final after = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(after.summary, 'Renamed');
    expect(after.id, id, reason: 'an edit updates in place');
    expect((await db.select(db.todos).get()), hasLength(1));
    expect(find.byType(TodoFormPage), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failing late write does not create a partial event', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (router, app) = _app(
      db,
      overrides: [_failingReminderWrites()],
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/event/new');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Team offsite');
    await tester.pump();
    await tester.tap(find.text('Add Reminder'));
    await _settle(tester);
    await tester.tap(find.text('On time'));
    await _settle(tester);

    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(
      await db.select(db.events).get(),
      isEmpty,
      reason: 'a half-written event is worse than none',
    );
    expect(find.byType(EventFormPage), findsOneWidget);
    await _unmount(tester);
  });
}
