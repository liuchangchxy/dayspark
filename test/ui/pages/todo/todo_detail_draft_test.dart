import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';

/// Editing tags, reminders or planned time in the detail surface is a draft:
/// cancel leaves the stored rows untouched, save applies every one of them.
Widget _app(AppDatabase db, Todo todo) {
  final router = GoRouter(
    initialLocation: '/todo/detail',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold()),
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

  late AppDatabase db;
  late Todo todo;
  late int tagId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Plan the launch',
            dueDate: Value(DateTime(2026, 10, 24, 18)),
          ),
        );
    todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    tagId = await db
        .into(db.tags)
        .insert(TagsCompanion.insert(name: 'Work'));
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('tag changes roll back on cancel and persist on save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    await tester.ensureVisible(find.text('Work'));
    await tester.tap(find.text('Work'));
    await _settle(tester);
    expect(
      await db.select(db.todoTags).get(),
      isEmpty,
      reason: 'toggling a tag only edits the draft',
    );

    await tester.tap(find.byKey(const ValueKey('todo-detail-cancel')));
    await _settle(tester);
    expect(await db.select(db.todoTags).get(), isEmpty);
    await _unmount(tester);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);
    await tester.ensureVisible(find.text('Work'));
    await tester.tap(find.text('Work'));
    await _settle(tester);
    expect(await db.select(db.todoTags).get(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('todo-detail-save')));
    await _settle(tester);
    final links = await db.select(db.todoTags).get();
    expect(links, hasLength(1));
    expect(links.single.todoId, todo.id);
    expect(links.single.tagId, tagId);
    await _unmount(tester);
  });

  testWidgets('reminder changes roll back on cancel and persist on save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    await tester.ensureVisible(find.text('Add Reminder'));
    await tester.tap(find.text('Add Reminder'));
    await _settle(tester);
    await tester.tap(find.text('15 min before'));
    await _settle(tester);
    expect(
      await db.select(db.reminders).get(),
      isEmpty,
      reason: 'a reminder chosen in edit mode waits for save',
    );

    await tester.tap(find.byKey(const ValueKey('todo-detail-cancel')));
    await _settle(tester);
    expect(await db.select(db.reminders).get(), isEmpty);
    await _unmount(tester);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);
    await tester.ensureVisible(find.text('Add Reminder'));
    await tester.tap(find.text('Add Reminder'));
    await _settle(tester);
    await tester.tap(find.text('15 min before'));
    await _settle(tester);
    expect(await db.select(db.reminders).get(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('todo-detail-save')));
    await _settle(tester);
    final reminders = await db.select(db.reminders).get();
    expect(reminders, hasLength(1));
    expect(reminders.single.triggerTime, DateTime(2026, 10, 24, 17, 45));
    await _unmount(tester);
  });

  testWidgets('planned time rolls back on cancel and persists on save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    await tester.ensureVisible(find.text('Add execution time'));
    await tester.tap(find.text('Add execution time'));
    await _settle(tester);
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    expect(
      await db.select(db.taskAllocations).get(),
      isEmpty,
      reason: 'a planned block added in edit mode waits for save',
    );

    await tester.tap(find.byKey(const ValueKey('todo-detail-cancel')));
    await _settle(tester);
    expect(await db.select(db.taskAllocations).get(), isEmpty);
    await _unmount(tester);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);
    await tester.ensureVisible(find.text('Add execution time'));
    await tester.tap(find.text('Add execution time'));
    await _settle(tester);
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    expect(await db.select(db.taskAllocations).get(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('todo-detail-save')));
    await _settle(tester);
    final allocations = await db.select(db.taskAllocations).get();
    expect(allocations, hasLength(1));
    expect(allocations.single.todoId, todo.id);
    expect(allocations.single.state, 'active');
    await _unmount(tester);
  });
}
