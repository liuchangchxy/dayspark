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
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';

/// "Look at this" and "change this" are the same gesture: the detail surface
/// is editable in place, and no second page is needed to save a change.
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

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    final due = DateTime(2026, 10, 24, 18);
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Write the report',
            dueDate: Value(due),
          ),
        );
    todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('reminders can be added, edited and removed in detail', (
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
    var reminders = await db.select(db.reminders).get();
    expect(reminders.single.triggerTime, DateTime(2026, 10, 24, 17, 45));

    await tester.tap(find.text('15 min before'));
    await _settle(tester);
    await tester.tap(find.text('1 h before'));
    await _settle(tester);
    reminders = await db.select(db.reminders).get();
    expect(reminders.single.triggerTime, DateTime(2026, 10, 24, 17));
    expect(find.text('1 h before'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove reminder'));
    await _settle(tester);
    expect(await db.select(db.reminders).get(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('detail follows time → reminder → organize → content order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    double y(String label) => tester.getTopLeft(find.text(label).first).dy;
    expect(y('Time'), lessThan(y('Reminders')));
    expect(y('Reminders'), lessThan(y('Organize')));
    expect(y('Organize'), lessThan(y('Content')));

    await tester.ensureVisible(find.text('Add subtask'));
    await tester.tap(find.text('Add subtask'));
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(DsDialog),
        matching: find.byType(TextField),
      ),
      'First step',
    );
    await tester.tap(find.widgetWithText(DsButton, 'Add'));
    await _settle(tester);

    expect(find.text('First step'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('todo-detail-save')));
    await tester.tap(find.byKey(const ValueKey('todo-detail-save')));
    await _settle(tester);
    final subtasks = await (db.select(
      db.todos,
    )..where((row) => row.parentId.equals(todo.id))).get();
    expect(subtasks.single.summary, 'First step');
    await _unmount(tester);
  });

  testWidgets('detail is editable where it is read', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    expect(find.text('Write the report'), findsWidgets);
    expect(
      find.byKey(const ValueKey('todo-detail-title')),
      findsOneWidget,
      reason: 'the title is a field, not a label',
    );
    expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('editing the title writes through without a second page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);
    expect(find.byType(TodoFormPage), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('todo-detail-title')),
      'Write the final report',
    );
    await _settle(tester);

    expect(
      (await db.select(db.todos).get()).single.summary,
      'Write the report',
      reason: 'typing alone does not write',
    );

    await tester.tap(find.byKey(const ValueKey('todo-detail-save')));
    await _settle(tester);

    final rows = await db.select(db.todos).get();
    expect(rows.single.summary, 'Write the final report');
    expect(find.byType(TodoFormPage), findsNothing);
    await _unmount(tester);
  });

  testWidgets('priority chips and primary action expose 48dp hit targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(db, todo));
    await _settle(tester);

    final tops = <double>[];
    for (final value in const [0, 9, 5, 1]) {
      final key = 'todo-priority-$value';
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.width, greaterThanOrEqualTo(48), reason: key);
      expect(rect.height, greaterThanOrEqualTo(48), reason: key);
      tops.add(rect.top);
      final visual = tester.getSize(
        find.byKey(ValueKey('todo-priority-visual-$value')),
      );
      expect(visual.height, 28, reason: key);
    }
    expect(tops.toSet(), hasLength(1), reason: 'chips must share one row');
    expect(tops.length, 4);
    for (final key in const [
      'todo-priority-0',
      'todo-priority-9',
      'todo-priority-5',
      'todo-priority-1',
    ]) {
      expect(
        tester.getRect(find.byKey(ValueKey(key))).height,
        lessThanOrEqualTo(56),
        reason: key,
      );
    }

    final primary = tester.getSize(
      find.byKey(const ValueKey('todo-detail-save')),
    );
    expect(primary.width, greaterThanOrEqualTo(48));
    expect(primary.height, greaterThanOrEqualTo(48));
    final primaryVisual = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('todo-detail-save')),
        matching: find.byType(Ink),
      ),
    );
    expect(primaryVisual.height, 36);

    await _unmount(tester);
  });

  testWidgets('priority chips wrap at 1.4x text without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final legacyId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: todo.calendarId,
            summary: 'Legacy recurring task',
            dueDate: Value(DateTime(2026, 10, 24, 18)),
            rrule: const Value('FREQ=DAILY'),
            recurrenceLegacyState: const Value('unknownLegacy'),
          ),
        );
    final legacy = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(legacyId))).getSingle();

    await tester.pumpWidget(_app(db, legacy));
    await _settle(tester);

    final rects = [
      for (final value in const [0, 9, 5, 1])
        tester.getRect(find.byKey(ValueKey('todo-priority-$value'))),
    ];
    expect(
      rects.map((rect) => rect.top).toSet().length,
      greaterThan(1),
    );
    final maxBottom = rects
        .map((rect) => rect.bottom)
        .reduce((a, b) => a > b ? a : b);
    final rowHeight = tester
        .getSize(find.byKey(const ValueKey('todo-priority-row')))
        .height;
    expect(rowHeight, greaterThan(56));

    final contentTop = tester.getTopLeft(find.text('Content').first).dy;
    expect(maxBottom, lessThan(contentTop));

    await _unmount(tester);
  });
}
