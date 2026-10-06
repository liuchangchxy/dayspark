import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/action_section.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_slot_sheet.dart';

Widget _wrapWithScope({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late int calendarId;
  final today = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default',
            color: const Value('#2196F3'),
          ),
        );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        actionDateProvider.overrideWith((ref) => today),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
    'Phase 1 vertical acceptance: Todo intent -> Calendar empty slot -> Schedule Todo -> TaskAllocation -> visible in Calendar and Action -> complete via existing writer with strict dueDate invariant and no Event creation',
    (tester) async {
      // -------------------------------------------------------------
      // 1. Todo Intent: Create ordinary Todo with specific future dueDate
      // -------------------------------------------------------------
      final initialDueDate = DateTime(2026, 10, 9, 17, 0); // 3 days later
      final todoId = await db.into(db.todos).insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Ship Action Loop Foundation',
              dueDate: Value(initialDueDate),
            ),
          );

      // Verify initial state
      final initialTodo = await (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle();
      expect(initialTodo.dueDate, initialDueDate, reason: 'Todo dueDate is explicitly preserved');
      expect(initialTodo.status, 'NEEDS-ACTION');

      // Verify no events or allocations initially exist
      expect(await db.select(db.events).get(), isEmpty);
      expect(await db.select(db.taskAllocations).get(), isEmpty);

      // -------------------------------------------------------------
      // 2. Calendar empty slot: User taps empty time slot for today 14:00 - 15:00
      // -------------------------------------------------------------
      final slotRange = DateTimeRange(
        start: DateTime(2026, 10, 6, 14, 0),
        end: DateTime(2026, 10, 6, 15, 0),
      );

      // Mount host page that opens CalendarSlotSheet exactly as HomePage does
      await tester.pumpWidget(
        _wrapWithScope(
          container: container,
          child: Builder(
            builder: (ctx) {
              return ElevatedButton(
                onPressed: () {
                  CalendarSlotSheet.show(
                    context: ctx,
                    range: slotRange,
                    onCreateEvent: () {
                      // Schedule Todo flow must NOT take this branch
                      fail('Should not trigger onCreateEvent during Schedule Todo flow');
                    },
                    loadSchedulableTodos: () =>
                        container.read(databaseProvider).todosDao.getSchedulableOrdinaryTodos(),
                    onScheduleTodo: (todo) async {
                      await container.read(createTaskAllocationProvider)(
                        todoId: todo.id,
                        startAt: slotRange.start,
                        endAt: slotRange.end,
                      );
                    },
                  );
                },
                child: const Text('Open Slot Sheet'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to open slot sheet
      await tester.tap(find.text('Open Slot Sheet'));
      await tester.pumpAndSettle();

      // Verify sheet shows Create Event and Schedule Todo
      expect(find.text('Create Event'), findsOneWidget);
      expect(find.text('Schedule Todo'), findsOneWidget);

      // -------------------------------------------------------------
      // 3. Choose existing ordinary Todo
      // -------------------------------------------------------------
      await tester.tap(find.text('Schedule Todo'));
      await tester.pumpAndSettle();

      // The sheet should now display candidate picker with our Todo
      expect(find.text('Ship Action Loop Foundation'), findsOneWidget);

      // Tap the candidate Todo to schedule it
      await tester.tap(find.text('Ship Action Loop Foundation'));
      await tester.pumpAndSettle();

      // -------------------------------------------------------------
      // 4. Assert throughout right after scheduling:
      //    - TaskAllocation created with exact slot interval
      //    - No Event is created
      //    - Todo.dueDate is strictly unchanged
      //    - Visible in Calendar and Action projection
      // -------------------------------------------------------------
      final allocations = await db.select(db.taskAllocations).get();
      expect(allocations, hasLength(1), reason: 'Exactly one TaskAllocation created');
      final allocation = allocations.first;
      expect(allocation.todoId, todoId);
      expect(allocation.startAt, slotRange.start.toUtc());
      expect(allocation.endAt, slotRange.end.toUtc());
      expect(allocation.state, 'active');
      expect(allocation.occurrenceId, isNull, reason: 'Ordinary Todo allocation has null occurrenceId');

      // Assert no Event created
      final events = await db.select(db.events).get();
      expect(events, isEmpty, reason: 'Scheduling a Todo must NOT create an Event');

      // Assert Todo.dueDate is strictly unchanged
      final todoAfterSchedule = await (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle();
      expect(todoAfterSchedule.dueDate, initialDueDate, reason: 'Todo.dueDate must remain strictly unchanged');

      // Assert visible in Calendar query (taskAllocationsInDateRangeProvider)
      final calendarRangeKey =
          '${today.millisecondsSinceEpoch}-${today.add(const Duration(days: 1)).millisecondsSinceEpoch}';
      final calSub = container.listen(
        taskAllocationsInDateRangeProvider(calendarRangeKey),
        (_, __) {},
      );
      final actSub = container.listen(actionProjectionProvider, (_, __) {});

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final calendarItems =
          container.read(taskAllocationsInDateRangeProvider(calendarRangeKey)).valueOrNull ?? [];
      expect(calendarItems, hasLength(1), reason: 'Visible in Calendar allocation query');
      expect(calendarItems.first.todo.id, todoId);
      expect(calendarItems.first.allocation.id, allocation.id);

      // Assert visible in Action projection
      final actionData = container.read(actionProjectionProvider).valueOrNull;
      expect(actionData, isNotNull);
      expect(actionData!.allocations, hasLength(1), reason: 'Allocation visible in Action timeline');
      expect(actionData.allocations.first.todo.id, todoId);
      expect(actionData.allocations.first.allocation.startAt, slotRange.start.toUtc());

      calSub.close();
      actSub.close();

      // -------------------------------------------------------------
      // 5. Action projection UI execution: complete through existing Todo writer
      // -------------------------------------------------------------
      await tester.pumpWidget(
        _wrapWithScope(
          container: container,
          child: const ActionSection(),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // ActionSection should show the item in todayTimeline
      expect(find.text('Ship Action Loop Foundation'), findsOneWidget);
      expect(find.text("Today's Schedule"), findsOneWidget);

      // Complete the Todo from Action surface checkbox
      final checkboxFinder = find.byType(Checkbox);
      expect(checkboxFinder, findsWidgets);
      await tester.tap(checkboxFinder.first);
      await tester.pumpAndSettle();

      // -------------------------------------------------------------
      // 6. Invariant check after completion:
      //    - Todo status is COMPLETED
      //    - Todo.dueDate is STILL strictly unchanged
      //    - Allocation lifecycle semantics followed:
      //      future allocation (startAt >= completedAt) becomes invalidatedByCompletion
      //    - No Event created
      // -------------------------------------------------------------
      final completedTodo = await (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle();
      expect(completedTodo.status, 'COMPLETED');
      expect(completedTodo.dueDate, initialDueDate, reason: 'Todo.dueDate must STILL be unchanged after completion');

      final finalAllocations = await db.select(db.taskAllocations).get();
      expect(finalAllocations, hasLength(1));
      // Since slot was today 14:00-15:00 and now is earlier, startAt >= completedAt
      // means it transitions to invalidatedByCompletion according to existing invariant
      expect(
        finalAllocations.first.state,
        'invalidatedByCompletion',
        reason: 'Existing TaskAllocation lifecycle invalidation respected',
      );

      final finalEvents = await db.select(db.events).get();
      expect(finalEvents, isEmpty, reason: 'No Event was ever created');
    },
  );
}
