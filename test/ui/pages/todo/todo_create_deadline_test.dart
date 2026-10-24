import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';

import 'package:go_router/go_router.dart';

Widget _wrap(AppDatabase db) {
  final router = GoRouter(
    initialLocation: '/todo/new',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(path: '/todo/new', builder: (_, __) => const TodoFormPage()),
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
  // Drift broadcast streams never complete, so pump a fixed number of frames
  // instead of pumpAndSettle (which would wait on an endless spinner).
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Default Calendar',
            color: const Value('#2196F3'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'new ordinary Todo defaults to null dueDate when no deadline is picked',
    (tester) async {
      await tester.pumpWidget(_wrap(db));
      await _settle(tester);

      final textField = find.byType(TextField).first;
      await tester.enterText(textField, 'Inbox item without deadline');
      await tester.pump();

      // The deadline row states the absence of a deadline; nothing is
      // preselected, so "no deadline" is the honest default.
      expect(find.text('No deadline'), findsWidgets);

      final saveButton = find.text('Save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await _settle(tester);

      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(1));
      expect(todos.first.summary, 'Inbox item without deadline');
      expect(
        todos.first.dueDate,
        isNull,
        reason: 'Creating without picking deadline must leave dueDate null',
      );

      await _unmount(tester);
    },
  );

  testWidgets(
    'new ordinary Todo saves dueDate when user explicitly picks a date',
    (tester) async {
      await tester.pumpWidget(_wrap(db));
      await _settle(tester);

      final textField = find.byType(TextField).first;
      await tester.enterText(textField, 'Item due tomorrow');
      await tester.pump();

      await tester.tap(find.text('No deadline').last);
      await _settle(tester);

      final dialog = find.byType(DatePickerDialog);
      expect(dialog, findsOneWidget);
      final now = DateTime.now();
      final tomorrow = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1));
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('${tomorrow.day}')),
      );
      await tester.pump();
      await tester.tap(find.descendant(of: dialog, matching: find.text('OK')));
      await _settle(tester);

      final saveButton = find.text('Save');
      await tester.tap(saveButton);
      await _settle(tester);

      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(1));
      expect(todos.first.summary, 'Item due tomorrow');
      expect(todos.first.dueDate, isNotNull);
      expect(todos.first.dueDate!.year, tomorrow.year);
      expect(todos.first.dueDate!.month, tomorrow.month);
      expect(todos.first.dueDate!.day, tomorrow.day);

      await _unmount(tester);
    },
  );

  testWidgets('a new Todo can carry an execution block without saving first', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(db));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Item I will do now');
    await tester.pump();

    // Scheduling is offered while the todo is still a draft; the old flow
    // forced a save, a reopen, and a second trip to this same sheet.
    await tester.tap(find.text('Add execution time'));
    await _settle(tester);

    final sheetSave = find.widgetWithText(FilledButton, 'Save');
    expect(sheetSave, findsOneWidget);
    await tester.tap(sheetSave);
    await _settle(tester);

    await tester.tap(find.text('Save'));
    await _settle(tester);

    final todos = await db.select(db.todos).get();
    expect(todos, hasLength(1));
    final allocations = await db.select(db.taskAllocations).get();
    expect(
      allocations,
      hasLength(1),
      reason: 'the draft block must be written together with the todo',
    );
    expect(allocations.single.todoId, todos.single.id);
    expect(
      allocations.single.endAt.isAfter(allocations.single.startAt),
      isTrue,
    );

    await _unmount(tester);
  });

  testWidgets('changing the deadline date keeps the time it already had', (
    tester,
  ) async {
    final calendarId = (await db.select(db.calendars).get()).first.id;
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Call the bank',
            dueDate: Value(DateTime(2026, 10, 30, 18)),
          ),
        );
    final todo = (await db.select(db.todos).get()).single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: TodoFormPage(todo: todo),
        ),
      ),
    );
    await _settle(tester);

    // A deadline that has a time keeps asking for one: the date is what the
    // user is changing, and the hour they already chose must survive it.
    await tester.tap(find.textContaining('Oct 30').last);
    await _settle(tester);

    final dialog = find.byType(DatePickerDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('31')));
    await tester.pump();
    await tester.tap(find.descendant(of: dialog, matching: find.text('OK')));
    await _settle(tester);

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget, reason: 'the time step still asks');
    await tester.tap(find.descendant(of: sheet, matching: find.text('OK')));
    await _settle(tester);

    await tester.tap(find.text('Save'));
    await _settle(tester);

    final after = (await db.select(db.todos).get()).single;
    expect(after.dueDate, DateTime(2026, 10, 31, 18));
    await _unmount(tester);
  });
}
