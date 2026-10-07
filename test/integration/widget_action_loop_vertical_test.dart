import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/services/action_projection_query.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';
import 'package:dayspark/infrastructure/platform/widget_command.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

import '../helpers/test_database.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int calId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    await db.close();
  });

  test('Widget Action Loop complete vertical slice', () async {
    final now = DateTime(2026, 10, 7, 10, 0);

    // 1. Seed domain data
    // Non-recurring todo due today
    final todo1Id = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'File Expense Report',
            syncId: const Value('todo_sync_expense'),
            dueDate: Value(DateTime(2026, 10, 7)),
          ),
        );
    final todo1 = await (db.select(db.todos)..where((t) => t.id.equals(todo1Id))).getSingle();

    // Recurring habit
    final habitSpec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 10, 7),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final habitId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Morning Meditation',
          rrule: Value(habitSpec.rule.canonical),
        ),
        recurrenceSpec: habitSpec,
      ),
    );
    final habit = await (db.select(db.todos)..where((t) => t.id.equals(habitId))).getSingle();

    // Event today
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calId,
            summary: 'Team Sync',
            startDt: DateTime(2026, 10, 7, 11, 0),
            endDt: DateTime(2026, 10, 7, 12, 0),
          ),
        );

    // 2. Initial snapshot generation
    final initialProjection = await ActionProjectionQuery.fetch(db, date: now);
    final initialTimeline = HomeWidgetService.todayTimeline(initialProjection);
    final initialActions = HomeWidgetService.todayActions(initialProjection);
    final initialStatus = HomeWidgetService.todayStatus(initialProjection);
    final initialUpcoming = await HomeWidgetService.upcomingItems(db, now: now);
    final initialMonthDots = await HomeWidgetService.monthDots(db, now: now);
    final initialUi = await HomeWidgetService.loadWidgetUiStrings(
      locale: const Locale('en'),
      todoCount: initialActions.length + initialStatus['unplannedCount']!,
    );
    final initialTheme = HomeWidgetService.buildThemeBlock(dark: true);

    final snapshot1 = HomeWidgetService.buildSnapshot(
      todayTimeline: initialTimeline,
      todayActions: initialActions,
      todayStatus: initialStatus,
      upcomingItems: initialUpcoming,
      monthDots: initialMonthDots,
      ui: initialUi,
      theme: initialTheme,
      generatedAt: now,
    );

    // Verify initial snapshot contents
    final snap1Actions = (snapshot1['today'] as Map<String, dynamic>)['actions'] as List;
    expect(snap1Actions.any((a) => a['summary'] == 'File Expense Report'), isTrue);
    expect(snap1Actions.any((a) => a['summary'] == 'Morning Meditation'), isTrue);

    // Extract occurrenceId of the habit from actions
    final habitAction = snap1Actions.firstWhere((a) => a['summary'] == 'Morning Meditation') as Map<String, dynamic>;
    final occurrenceId = habitAction['occurrenceId'] as String;
    expect(occurrenceId, isNotEmpty);

    // 3. Simulate Native widget checkbox taps -> writing typed commands to transport
    final transport = InMemoryWidgetCommandTransport();

    final cmdExpense = WidgetCommand(
      commandId: 'cmd_uuid_1',
      action: 'complete',
      target: 'todo',
      todoId: todo1.id,
      todoSyncId: todo1.syncId,
      at: DateTime.utc(2026, 10, 7, 10, 15),
    );

    final cmdMeditation = WidgetCommand(
      commandId: 'cmd_uuid_2',
      action: 'complete',
      target: 'taskInstance',
      todoId: habit.id,
      todoSyncId: habit.syncId,
      occurrenceId: occurrenceId,
      at: DateTime.utc(2026, 10, 7, 10, 16),
    );

    transport.pushCommand(cmdExpense);
    transport.pushCommand(cmdMeditation);

    expect((await transport.fetchPendingCommands()).length, 2);

    // 4. App refresh / drain: consume commands through canonical domain toggle path
    Future<void> toggleTodo({
      required int id,
      required bool isCompleted,
      String? occurrenceId,
    }) async {
      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(
          db,
          tx,
          id,
          isCompleted: isCompleted,
          occurrenceId: occurrenceId,
        ),
      );
    }

    await consumeWidgetCommands(
      db: db,
      transport: transport,
      toggleTodo: toggleTodo,
    );

    // 5. Verify database domain states updated
    // Expense todo is now COMPLETED
    final updatedTodo1 = await (db.select(db.todos)..where((t) => t.id.equals(todo1.id))).getSingle();
    expect(updatedTodo1.status, 'COMPLETED');

    // Habit has a task_instance_state COMPLETED for this occurrence
    final instanceState = await (db.select(db.taskInstanceStates)
          ..where((s) => s.todoSyncId.equals(habit.syncId!) & s.occurrenceId.equals(occurrenceId)))
        .getSingleOrNull();
    expect(instanceState, isNotNull);
    expect(instanceState!.status.toLowerCase(), 'completed');

    // Transport is fully drained and acknowledged
    expect((await transport.fetchPendingCommands()), isEmpty);

    // 6. Verify recomputed snapshot reflects completed items
    final refreshedProjection = await ActionProjectionQuery.fetch(db, date: now);
    final refreshedActions = HomeWidgetService.todayActions(refreshedProjection);

    // Completed items are removed from actionable today actions
    expect(refreshedActions.any((a) => a['summary'] == 'File Expense Report'), isFalse);
    expect(refreshedActions.any((a) => a['summary'] == 'Morning Meditation'), isFalse);

    // 7. Test semantic idempotency replay: re-delivering already completed commands is safe no-op
    transport.pushCommand(cmdExpense);
    transport.pushCommand(cmdMeditation);

    var replayToggleCalls = 0;
    await consumeWidgetCommands(
      db: db,
      transport: transport,
      toggleTodo: ({required id, required isCompleted, occurrenceId}) async {
        replayToggleCalls++;
      },
    );

    // Neither command called toggleTodo because both were detected as already applied!
    expect(replayToggleCalls, 0);
    expect((await transport.fetchPendingCommands()), isEmpty);
  });

  test('ordinary Allocation vertical slice: completion invalidates future allocation', () async {
    // 1. Ordinary Todo
    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Write Architectural Review',
            syncId: const Value('todo_sync_arch_review'),
            dueDate: Value(DateTime(2026, 10, 7)),
          ),
        );
    final todo = await (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle();

    // 2. Future active Allocation today (relative to now so startAt >= completedAt holds)
    final realNow = DateTime.now();
    final futureStart = realNow.add(const Duration(hours: 2));
    final futureEnd = futureStart.add(const Duration(hours: 1));

    final allocId = await db.into(db.taskAllocations).insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(todo.id),
            startAt: futureStart,
            endAt: futureEnd,
            state: const Value('active'),
          ),
        );

    // 3. Verify snapshot timeline contains taskAllocation row
    final queryDate = DateTime(futureStart.year, futureStart.month, futureStart.day);
    final initialProjection = await ActionProjectionQuery.fetch(db, date: queryDate);
    final initialTimeline = HomeWidgetService.todayTimeline(initialProjection);
    final allocRow = initialTimeline.firstWhere(
      (item) => item['kind'] == 'taskAllocation' && item['summary'] == 'Write Architectural Review',
    );
    expect(allocRow, isNotNull);
    expect(allocRow['allocationId'], '$allocId');
    expect(allocRow['todoId'], todo.id);
    expect(allocRow['todoSyncId'], todo.syncId);
    expect(allocRow['occurrenceId'], isNull);

    // 4. Native complete tap on TaskAllocation timeline row -> derives target=todo command with sourceAllocationId
    final transport = InMemoryWidgetCommandTransport();
    final cmd = WidgetCommand(
      commandId: 'cmd_alloc_ord_1',
      action: 'complete',
      target: 'todo',
      todoId: todo.id,
      todoSyncId: todo.syncId,
      sourceAllocationId: '$allocId',
      at: DateTime.utc(2026, 10, 7, 10, 15),
    );
    transport.pushCommand(cmd);

    // 5. Consume command through domain toggleTodo
    Future<void> toggleTodo({
      required int id,
      required bool isCompleted,
      String? occurrenceId,
    }) async {
      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(
          db,
          tx,
          id,
          isCompleted: isCompleted,
          occurrenceId: occurrenceId,
        ),
      );
    }

    await consumeWidgetCommands(
      db: db,
      transport: transport,
      toggleTodo: toggleTodo,
    );

    // 6. Verification: Todo is COMPLETED
    final updatedTodo = await (db.select(db.todos)..where((t) => t.id.equals(todo.id))).getSingle();
    expect(updatedTodo.status, 'COMPLETED');

    // 7. Future active allocation was invalidatedByCompletion in domain
    final updatedAlloc = await (db.select(db.taskAllocations)..where((a) => a.id.equals(allocId))).getSingle();
    expect(updatedAlloc.state, 'invalidatedByCompletion');

    // 8. Transport is fully acknowledged
    expect(await transport.fetchPendingCommands(), isEmpty);

    // 9. Refreshed snapshot timeline no longer has active allocation
    final refreshedProjection = await ActionProjectionQuery.fetch(db, date: queryDate);
    final refreshedTimeline = HomeWidgetService.todayTimeline(refreshedProjection);
    expect(refreshedTimeline.any((item) => item['allocationId'] == '$allocId'), isFalse);
  });

  test('recurring Allocation vertical slice: completion invalidates occurrence allocation while siblings remain untouched', () async {
    final realNow = DateTime.now();
    final todayLocal = LocalDate(realNow.year, realNow.month, realNow.day);

    // 1. Recurring Todo
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: todayLocal,
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final todoId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Daily German Practice',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );
    final todo = await (db.select(db.todos)..where((t) => t.id.equals(todoId))).getSingle();

    // 2. Derive occurrenceId for today
    final projection = await ActionProjectionQuery.fetch(db, date: realNow);
    final inst = projection.todayTaskInstances.firstWhere((i) => i.todo.id == todo.id);
    final targetOccurrenceId = inst.occurrence.occurrenceId;
    expect(targetOccurrenceId, isNotEmpty);

    // 3. Create occurrence-bound future active Allocation (start in future relative to realNow)
    final futureStart = realNow.add(const Duration(hours: 3));
    final futureEnd = futureStart.add(const Duration(hours: 1));
    final queryDate = DateTime(futureStart.year, futureStart.month, futureStart.day);

    final allocId = await db.into(db.taskAllocations).insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(todo.id),
            occurrenceId: Value(targetOccurrenceId),
            startAt: futureStart,
            endAt: futureEnd,
            state: const Value('active'),
          ),
        );

    // 4. Initial timeline verifies occurrenceId and allocationId are retained
    final initialProjection = await ActionProjectionQuery.fetch(db, date: queryDate);
    final initialTimeline = HomeWidgetService.todayTimeline(initialProjection);
    final allocRow = initialTimeline.firstWhere((item) => item['allocationId'] == '$allocId');
    expect(allocRow['kind'], 'taskAllocation');
    expect(allocRow['occurrenceId'], targetOccurrenceId);
    expect(allocRow['todoSyncId'], todo.syncId);

    // 5. Native complete tap sends target=taskInstance with exact occurrenceId and sourceAllocationId
    final transport = InMemoryWidgetCommandTransport();
    final cmd = WidgetCommand(
      commandId: 'cmd_alloc_rec_1',
      action: 'complete',
      target: 'taskInstance',
      todoId: todo.id,
      todoSyncId: todo.syncId,
      occurrenceId: targetOccurrenceId,
      sourceAllocationId: '$allocId',
      at: DateTime.utc(2026, 10, 7, 10, 20),
    );
    transport.pushCommand(cmd);

    // 6. Consume command
    Future<void> toggleTodo({
      required int id,
      required bool isCompleted,
      String? occurrenceId,
    }) async {
      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(
          db,
          tx,
          id,
          isCompleted: isCompleted,
          occurrenceId: occurrenceId,
        ),
      );
    }

    await consumeWidgetCommands(
      db: db,
      transport: transport,
      toggleTodo: toggleTodo,
    );

    // 7. Verification:
    // - TaskInstanceState for target occurrence is completed
    final instanceState = await (db.select(db.taskInstanceStates)
          ..where((s) => s.todoSyncId.equals(todo.syncId!) & s.occurrenceId.equals(targetOccurrenceId)))
        .getSingleOrNull();
    expect(instanceState, isNotNull);
    expect(instanceState!.status.toLowerCase(), 'completed');

    // - Parent Todo remains active (status != COMPLETED)
    final refreshedTodo = await (db.select(db.todos)..where((t) => t.id.equals(todo.id))).getSingle();
    expect(refreshedTodo.status, 'NEEDS-ACTION');

    // - Allocation is invalidatedByCompletion
    final updatedAlloc = await (db.select(db.taskAllocations)..where((a) => a.id.equals(allocId))).getSingle();
    expect(updatedAlloc.state, 'invalidatedByCompletion');

    // - Transport acknowledged
    expect(await transport.fetchPendingCommands(), isEmpty);

    // - Refreshed timeline no longer has the completed allocation
    final refreshedProjection = await ActionProjectionQuery.fetch(db, date: queryDate);
    final refreshedTimeline = HomeWidgetService.todayTimeline(refreshedProjection);
    expect(refreshedTimeline.any((item) => item['allocationId'] == '$allocId'), isFalse);
  });
}
