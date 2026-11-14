import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/todo_quick_add.dart';

Future<T> _resolve<T>(
  ProviderContainer container,
  ProviderListenable<AsyncValue<T>> provider,
) async {
  final sub = container.listen(provider, (_, __) {});
  try {
    for (var i = 0; i < 60; i++) {
      await pumpEventQueue();
      final value = container.read(provider);
      if (value.hasError) throw value.error!;
      if (value.hasValue && !value.isLoading) return value.requireValue;
    }
    throw StateError('provider did not resolve to data');
  } finally {
    sub.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixed = DateTime(2026, 11, 14, 9, 30);

  group('date states', () {
    test('today and browseDate both start at the clock day', () {
      final container = ProviderContainer(
        overrides: [clockNowProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      expect(container.read(clockDayProvider), DateTime(2026, 11, 14));
      expect(container.read(browseDateProvider), DateTime(2026, 11, 14));
    });

    test('a midnight refresh moves today but not the browsed date', () {
      var now = fixed;
      final container = ProviderContainer(
        overrides: [clockNowProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      container.read(browseDateProvider.notifier).state = DateTime(2026, 11, 20);
      now = DateTime(2026, 11, 15, 0, 1);
      container.read(clockDayProvider.notifier).refresh();

      expect(container.read(clockDayProvider), DateTime(2026, 11, 15));
      expect(container.read(browseDateProvider), DateTime(2026, 11, 20));
    });

    test('browsing does not move today', () {
      final container = ProviderContainer(
        overrides: [clockNowProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      container.read(browseDateProvider.notifier).state = DateTime(2026, 12, 1);

      expect(container.read(clockDayProvider), DateTime(2026, 11, 14));
      expect(container.read(browseDateProvider), DateTime(2026, 12, 1));
    });
  });

  group('day projection', () {
    late AppDatabase db;
    late ProviderContainer container;
    late int calendarId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      calendarId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Default'));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockNowProvider.overrideWithValue(() => fixed),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    test('a todo due and planned the same day is one projected task',
        () async {
      final todoId = await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Write review',
              dueDate: Value(DateTime(2026, 11, 14)),
            ),
          );
      await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: DateTime(2026, 11, 14, 10),
        endAt: DateTime(2026, 11, 14, 10, 30),
      );

      final projected = await _resolve(
        container,
        projectedDayTodosProvider(DateTime(2026, 11, 14)),
      );
      expect(projected.where((t) => t.id == todoId), hasLength(1));
      expect(projected.single.summary, 'Write review');

      final today = await _resolve(container, actionProjectionProvider);
      expect(today.allocations.single.todo.id, todoId);
    });

    test('a planned task appears on its day only', () async {
      final todoId = await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Plan the week',
            ),
          );
      await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: DateTime(2026, 11, 20, 9),
        endAt: DateTime(2026, 11, 20, 9, 30),
      );

      final onDay = await _resolve(
        container,
        projectedDayTodosProvider(DateTime(2026, 11, 20)),
      );
      final offDay = await _resolve(
        container,
        projectedDayTodosProvider(DateTime(2026, 11, 21)),
      );
      expect(onDay.map((t) => t.id), contains(todoId));
      expect(offDay.map((t) => t.id), isNot(contains(todoId)));
    });

    test('overdue belongs to today and never to another browsed day',
        () async {
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Old invoice',
              dueDate: Value(DateTime(2026, 11, 10)),
            ),
          );

      final today = await _resolve(container, actionProjectionProvider);
      expect(today.overdueTodos.map((t) => t.summary), contains('Old invoice'));

      final other = await _resolve(
        container,
        dayProjectionProvider(DateTime(2026, 11, 20)),
      );
      expect(other.overdueTodos, isEmpty);
    });
  });

  group('capture contract', () {
    testWidgets('an inline capture writes no deadline and no allocation', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Default'));

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
            home: const Scaffold(body: Column(children: [TodoQuickAdd()])),
          ),
        ),
      );
      await tester.pump();

      final field = find.byKey(const ValueKey('todo-quick-add'));
      await tester.enterText(field, 'Milk');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final rows = await db.select(db.todos).get();
      expect(rows, hasLength(1));
      expect(rows.single.dueDate, isNull);
      expect(await db.select(db.taskAllocations).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
    });
  });
}
