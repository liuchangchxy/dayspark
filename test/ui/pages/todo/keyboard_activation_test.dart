import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_todo_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void _focus(WidgetTester tester, Finder control) {
  final gesture = find
      .descendant(of: control, matching: find.byType(GestureDetector))
      .first;
  Focus.of(tester.element(gesture)).requestFocus();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  final now = DateTime(2026, 11, 15, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
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

  testWidgets('Tab reaches the mode switch and Enter opens the All list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2TodoPage(
      now: now,
      dayAgenda: DayAgenda(
        day: DateTime(now.year, now.month, now.day),
        events: const [],
        allocations: const [],
        dueTodos: const [],
        overdueTodos: const [],
        instances: const [],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: page),
        ),
      ),
    );
    await _settle(tester);

    final allMode = find.byKey(const ValueKey('todo-mode-all'));
    _focus(tester, allMode);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodoPage)),
      listen: false,
    );
    expect(container.read(todosViewProvider), isA<TodosAllView>());

    await _unmount(tester);
  });

  testWidgets('the date strip month button answers Enter', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 10)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: A2TodoPage(
              now: now,
              dayAgenda: DayAgenda(
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
      ),
    );
    await _settle(tester);

    final strip = find.byKey(const ValueKey('todos-date-strip'));
    _focus(tester, strip);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('month-day-2026-11-10')),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);
    await _unmount(tester);
  });

  testWidgets('Escape closes the filter popover and restores focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: A2TodoPage(
              now: now,
              dayAgenda: DayAgenda(
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
      ),
    );
    await _settle(tester);

    final tool = find.byKey(const ValueKey('todos-filter-tool'));
    expect(tool, findsOneWidget);
    await tester.tap(tool);
    await _settle(tester);
    expect(find.text('Apply'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Apply'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'todos-filter-tool');

    await _unmount(tester);
  });
}
