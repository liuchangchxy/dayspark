import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

Widget _app({
  required List<Override> overrides,
  required DateTime now,
  Widget? detail,
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
          dayAgenda: DayAgenda(
            day: DateTime(now.year, now.month, now.day),
            events: const [],
            allocations: const [],
            dueTodos: const [],
            overdueTodos: const [],
            instances: const [],
          ),
          detail: detail,
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
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
  final now = DateTime(2026, 11, 15, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('desktop By date reaches a distant day through the strip', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 15)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    // The desktop bar outside this page prints a date but cannot open a
    // picker; without the strip a distant day was arrow taps only.
    expect(find.byKey(const ValueKey('todos-date-strip')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todos-date-strip')));
    await _settle(tester);

    // A window gets the same grid in a centred card, not a sheet from an edge.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('month-day-2026-11-20')));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodoPage)),
      listen: false,
    );
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 20));
    expect(find.byType(Dialog), findsNothing);

    await _unmount(tester);
  });

  testWidgets('the strip jumps back to today without opening the picker', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosDayView()),
          viewedDateProvider.overrideWith((ref) => DateTime(2026, 11, 10)),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    final today = find.byKey(const ValueKey('todos-date-strip-today'));
    expect(today, findsOneWidget);

    await tester.tap(today);
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodoPage)),
      listen: false,
    );
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 15));
    // The shortcut is the point: no picker on the way back.
    expect(find.text('Month'), findsNothing);

    // Browsing today, the strip is the only entry, and it opens the picker.
    expect(find.byKey(const ValueKey('todos-date-strip-today')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('todos-date-strip')));
    await _settle(tester);
    expect(find.text('Month'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('desktop switches views through mode switch control', (
    tester,
  ) async {
    desktop(tester);
    await tester.pumpWidget(
      _app(
        overrides: [
          databaseProvider.overrideWithValue(db),
          todosViewProvider.overrideWith((ref) => const TodosAllView()),
        ],
        now: now,
      ),
    );
    await _settle(tester);

    // Header has mode switch with 3 modes.
    expect(find.byKey(const ValueKey('todos-mode-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-mode-date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-mode-date')));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2TodoPage)),
      listen: false,
    );
    expect(container.read(todosViewProvider), isA<TodosDayView>());

    await _unmount(tester);
  });
}
