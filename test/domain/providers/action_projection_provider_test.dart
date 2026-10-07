import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late ProviderContainer container;
  late int calendarId;
  final fixedToday = DateTime(2026, 10, 6);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            name: 'Default Calendar',
            color: const Value('#2196F3'),
          ),
        );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        actionDateProvider.overrideWith((ref) => fixedToday),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ActionProjectionData> getActionData() async {
    final sub = container.listen(actionProjectionProvider, (_, __) {});
    try {
      for (var i = 0; i < 30; i++) {
        await pumpEventQueue();
        final asyncVal = container.read(actionProjectionProvider);
        if (asyncVal.hasValue) {
          return asyncVal.value!;
        }
      }
      throw StateError('actionProjectionProvider did not resolve to data');
    } finally {
      sub.close();
    }
  }

  test('projects today events and excludes other days', () async {
    // Event today: 10:00 - 11:00
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Morning Standup',
            startDt: DateTime(2026, 10, 6, 10, 0),
            endDt: DateTime(2026, 10, 6, 11, 0),
            isAllDay: const Value(false),
          ),
        );
    // Event yesterday: 14:00 - 15:00
    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Yesterday Meeting',
            startDt: DateTime(2026, 10, 5, 14, 0),
            endDt: DateTime(2026, 10, 5, 15, 0),
            isAllDay: const Value(false),
          ),
        );

    final data = await getActionData();
    expect(data.events.length, 1);
    expect(data.events.first.title, 'Morning Standup');
  });

  test('projects ordinary task allocation and excludes recurring allocation', () async {
    // 1. Ordinary todo with today allocation
    final ordinaryTodoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Deep Work Session',
          ),
        );
    await container.read(createTaskAllocationProvider)(
      todoId: ordinaryTodoId,
      startAt: DateTime(2026, 10, 6, 14, 0),
      endAt: DateTime(2026, 10, 6, 16, 0),
    );

    // 2. Recurring todo with allocation (Phase 1 excludes recurring instances from Action)
    final recurringTodoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Daily Review',
            rrule: const Value('RRULE:FREQ=DAILY'),
          ),
        );
    await db.into(db.taskAllocations).insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(recurringTodoId),
            occurrenceId: const Value('2026-10-06T09:00:00Z'),
            startAt: DateTime(2026, 10, 6, 9, 0),
            endAt: DateTime(2026, 10, 6, 9, 30),
            state: const Value('active'),
          ),
        );

    final data = await getActionData();
    expect(data.allocations.length, 1);
    expect(data.allocations.first.todo.summary, 'Deep Work Session');
    expect(data.allocations.first.allocation.occurrenceId, isNull);
  });

  test('projects due today and overdue separately with original deadline preserved', () async {
    final originalOverdueDeadline = DateTime(2026, 10, 3, 18, 0);
    final todayDeadline = DateTime(2026, 10, 6, 17, 0);

    // Overdue todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Past Due Report',
            dueDate: Value(originalOverdueDeadline),
          ),
        );

    // Due today todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Deliver Slides',
            dueDate: Value(todayDeadline),
          ),
        );

    // Future todo (should NOT appear in due today or overdue)
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Next Week Planning',
            dueDate: Value(DateTime(2026, 10, 12)),
          ),
        );

    final data = await getActionData();

    expect(data.overdueTodos.length, 1);
    expect(data.overdueTodos.first.summary, 'Past Due Report');
    expect(data.overdueTodos.first.dueDate, originalOverdueDeadline);

    expect(data.dueTodayTodos.length, 1);
    expect(data.dueTodayTodos.first.summary, 'Deliver Slides');
    expect(data.dueTodayTodos.first.dueDate, todayDeadline);
  });

  test('preserves both facts when a Todo has both today allocation and today deadline', () async {
    final deadline = DateTime(2026, 10, 6, 20, 0);
    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Important Deliverable',
            dueDate: Value(deadline),
          ),
        );

    // Add allocation for today
    await container.read(createTaskAllocationProvider)(
      todoId: todoId,
      startAt: DateTime(2026, 10, 6, 10, 0),
      endAt: DateTime(2026, 10, 6, 12, 0),
    );

    final data = await getActionData();

    // Must appear in allocations
    expect(data.allocations.any((a) => a.todo.id == todoId), isTrue);
    // Must also appear in due today without losing either fact
    expect(data.dueTodayTodos.any((t) => t.id == todoId), isTrue);
    expect(data.dueTodayTodos.firstWhere((t) => t.id == todoId).dueDate, deadline);
  });

  test('unplannedCount counts only undated pending ordinary todos', () async {
    // 2 undated ordinary todos
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Idea 1',
          ),
        );
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Idea 2',
          ),
        );

    // 1 dated todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Dated',
            dueDate: Value(DateTime(2026, 10, 6)),
          ),
        );

    // 1 completed undated todo
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Completed idea',
            status: const Value('COMPLETED'),
          ),
        );

    final data = await getActionData();
    expect(data.unplannedCount, 2);
  });

  test('toggling todo completion moves it reactively to completedToday', () async {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    container.read(actionDateProvider.notifier).state = todayMidnight;

    final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Task To Complete',
            dueDate: Value(todayMidnight.add(const Duration(hours: 15))),
          ),
        );

    var data = await getActionData();
    expect(data.dueTodayTodos.length, 1);
    expect(data.completedTodayTodos.isEmpty, isTrue);

    // Complete the todo via existing toggle provider
    await container.read(toggleTodoProvider)(id: todoId, isCompleted: true);

    data = await getActionData();
    expect(data.dueTodayTodos.isEmpty, isTrue);
    expect(data.completedTodayTodos.length, 1);
    expect(data.completedTodayTodos.first.id, todoId);
    expect(data.completedTodayTodos.first.status, 'COMPLETED');
  });

  test('recurring series started >45 days before Action date produces occurrence today', () async {
    // Master event started 90 days ago (2026-07-08), repeating daily at 09:00 - 10:00
    final startDt = DateTime(2026, 7, 8, 9, 0);
    final endDt = DateTime(2026, 7, 8, 10, 0);
    expect(fixedToday.difference(startDt).inDays, greaterThan(45));

    await db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            summary: 'Long-standing Daily Standup',
            startDt: startDt,
            endDt: endDt,
            rrule: const Value('RRULE:FREQ=DAILY'),
            isAllDay: const Value(false),
          ),
        );

    final data = await getActionData();
    expect(data.events.length, 1);
    final occurrence = data.events.first;
    expect(occurrence.title, 'Long-standing Daily Standup');
    expect(occurrence.start, DateTime(2026, 10, 6, 9, 0));
    expect(occurrence.end, DateTime(2026, 10, 6, 10, 0));
  });

  test('Phase 2: projects today actionable recurring TaskInstance and separates from missed', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 10, 4),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Daily Habit',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    final data = await getActionData();

    // Oct 6 is today
    expect(data.todayTaskInstances, hasLength(1));
    expect(data.todayTaskInstances.first.todo.id, seriesId);
    expect(data.todayTaskInstances.first.occurrenceId, 'v2:DATE:2026-10-06');
    expect(data.todayTaskInstances.first.isPending, isTrue);

    // Oct 4 and Oct 5 are missed (within 30 days)
    expect(data.missedTaskInstances, hasLength(2));
    expect(data.missedTaskInstances.map((i) => i.occurrenceId), containsAll(['v2:DATE:2026-10-04', 'v2:DATE:2026-10-05']));
  });

  test('Phase 2: projects valid occurrence-bound TaskAllocation in today timeline', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 10, 6),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Exercise',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    // Create allocation bound to today's occurrence
    await container.read(createTaskAllocationProvider)(
      todoId: seriesId,
      startAt: DateTime(2026, 10, 6, 15, 0),
      endAt: DateTime(2026, 10, 6, 16, 0),
      occurrenceId: 'v2:DATE:2026-10-06',
    );

    final data = await getActionData();
    expect(data.allocations.any((a) => a.allocation.occurrenceId == 'v2:DATE:2026-10-06'), isTrue);
  });

  test('Phase 2: completed today TaskInstance appears in completedTodayTaskInstances and reopens cleanly', () async {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    container.read(actionDateProvider.notifier).state = todayMidnight;
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final occId = 'v2:DATE:$todayStr';

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(today.year, today.month, today.day),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Read Book',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    // Complete today's occurrence
    await container.read(toggleTodoProvider)(
      id: seriesId,
      isCompleted: true,
      occurrenceId: occId,
    );

    var data = await getActionData();
    expect(data.todayTaskInstances.isEmpty, isTrue);
    expect(data.completedTodayTaskInstances, hasLength(1));
    expect(data.completedTodayTaskInstances.first.occurrenceId, occId);

    // Reopen exact occurrence
    await container.read(toggleTodoProvider)(
      id: seriesId,
      isCompleted: false,
      occurrenceId: occId,
    );

    data = await getActionData();
    expect(data.completedTodayTaskInstances.isEmpty, isTrue);
    expect(data.todayTaskInstances, hasLength(1));
    expect(data.todayTaskInstances.first.occurrenceId, occId);
  });

  test('Phase 2: unknownLegacy recurrence counted in unconfirmed without synthesized instances (Ruling C)', () async {
    // Insert an unknown legacy recurring todo (no recurrenceSpec, recurrenceLegacyState != 'knownZoned')
    await db.into(db.todos).insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Legacy Task',
            rrule: const Value('RRULE:FREQ=DAILY'),
            recurrenceLegacyState: const Value('unknownLegacy'),
          ),
        );

    final data = await getActionData();
    expect(data.unconfirmedRecurringCount, 1);
    expect(data.unconfirmedRecurringTodos.first.summary, 'Legacy Task');
    expect(data.todayTaskInstances.any((i) => i.todo.summary == 'Legacy Task'), isFalse);
    expect(data.missedTaskInstances.any((i) => i.todo.summary == 'Legacy Task'), isFalse);
  });

  test('Phase 2 regression: earlierMissedSeries targets only series with real earlier pending obligations', () async {
    // Series A: started 40 days ago, Daily, none completed
    final specA = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 8, 27),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesAId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Series A (pending earlier)',
          rrule: Value(specA.rule.canonical),
        ),
        recurrenceSpec: specA,
      ),
    );

    // Series B: started 40 days ago, Daily, but occurrences before 30 days ago (2026-08-27 .. 2026-09-05) are ALL completed
    final specB = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 8, 27),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesBId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Series B (all earlier completed)',
          rrule: Value(specB.rule.canonical),
        ),
        recurrenceSpec: specB,
      ),
    );
    final todoB = await (db.select(db.todos)..where((t) => t.id.equals(seriesBId))).getSingle();
    var idx = 0;
    for (var d = DateTime(2026, 8, 27); d.isBefore(DateTime(2026, 9, 6)); d = d.add(const Duration(days: 1))) {
      final occId = 'v2:DATE:${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await db.into(db.taskInstanceStates).insert(
        TaskInstanceStatesCompanion.insert(
          syncId: 'sync-b-$idx',
          todoSyncId: todoB.syncId!,
          occurrenceId: occId,
          status: const Value('completed'),
          completedAt: Value(DateTime(2026, 9, 1)),
        ),
      );
      idx++;
    }

    final data = await getActionData();
    expect(data.earlierMissedSeries, hasLength(1));
    expect(data.earlierMissedSeries.first.id, seriesAId);
    expect(data.earlierMissedSeries.first.summary, 'Series A (pending earlier)');
  });

  test('Phase 2 regression: expansion failure on known recurrence does not masquerade as unconfirmed recurrence', () async {
    await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: 'Broken Recurring Task',
        rrule: const Value('INVALID_RRULE_FORMAT'),
        recurrenceLegacyState: const Value('knownZoned'),
        recurrenceRule: const Value('INVALID_RRULE_FORMAT'),
        recurrenceAnchorSource: const Value('due'),
        recurrenceValueType: const Value('date'),
        recurrenceAnchorValue: const Value('2026-10-06'),
        recurrenceTimeZone: const Value('UTC'),
      ),
    );

    final data = await getActionData();
    expect(data.unconfirmedRecurringTodos.isEmpty, isTrue);
    expect(data.unconfirmedRecurringCount, 0);

    expect(data.recurrenceExpansionErrors, hasLength(1));
    expect(data.recurrenceExpansionErrors.first.todo.summary, 'Broken Recurring Task');
  });

  test('Phase 2 regression: completed today DATE-TIME occurrence preserves nominal instant independently of completedAt', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(2026, 10, 6, 9, 0, 0),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Morning Standup Meeting',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    final todo = await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();
    final occurrenceId = OccurrenceId.forNominal(spec.anchor.value, spec.timeZone).value;
    final userCompletedAt = DateTime(2026, 10, 6, 17, 30);

    await db.into(db.taskInstanceStates).insert(
      TaskInstanceStatesCompanion.insert(
        syncId: 'sync-meeting-1',
        todoSyncId: todo.syncId!,
        occurrenceId: occurrenceId,
        status: const Value('completed'),
        completedAt: Value(userCompletedAt),
      ),
    );

    final data = await getActionData();
    expect(data.completedTodayTaskInstances, hasLength(1));
    final completedInstance = data.completedTodayTaskInstances.first;

    expect(completedInstance.completedAt, userCompletedAt);
    final expectedInstant = DateTime.utc(2026, 10, 6, 1, 0, 0);
    expect(completedInstance.occurrence.resolvedStartInstant, expectedInstant);
    expect(completedInstance.occurrence.occurrenceId, occurrenceId);
  });

  test('Phase 2 regression: Action-day window timezone ownership preserves Tokyo series in UTC user day (Ruling E)', () async {
    final utcContainer = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        actionDateProvider.overrideWith((ref) => DateTime.utc(2026, 10, 6)),
      ],
    );
    addTearDown(utcContainer.dispose);

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(2026, 10, 7, 0, 30, 0),
      ),
      timeZone: 'Asia/Tokyo',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Midnight Tokyo Standup',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    final sub = utcContainer.listen(actionProjectionProvider, (_, __) {});
    ActionProjectionData? data;
    try {
      for (var i = 0; i < 30; i++) {
        await pumpEventQueue();
        final asyncVal = utcContainer.read(actionProjectionProvider);
        if (asyncVal.hasValue) {
          data = asyncVal.value!;
          break;
        }
      }
    } finally {
      sub.close();
    }

    expect(data, isNotNull);
    expect(data!.todayTaskInstances, hasLength(1));
    final instance = data.todayTaskInstances.first;
    expect(instance.todo.id, seriesId);
    expect(instance.occurrence.occurrenceId, 'v1:DT:2026-10-07T00:30:00@Asia/Tokyo');
    expect(instance.occurrence.resolvedStartInstant, DateTime.utc(2026, 10, 6, 15, 30));
    expect(data.missedTaskInstances, isEmpty);
  });

  test('Phase 2 regression: civil next-midnight boundary captures late-evening events and tasks up to civil midnight', () async {
    final lateEventStart = DateTime(2026, 10, 6, 23, 30);
    final lateEventEnd = DateTime(2026, 10, 6, 23, 59);

    await db.into(db.events).insert(
      EventsCompanion.insert(
        calendarId: calendarId,
        summary: 'Late Evening Wrap-up',
        startDt: lateEventStart,
        endDt: lateEventEnd,
        isAllDay: const Value(false),
      ),
    );

    final ordinaryLateId = await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: 'Late Night Ordinary Task',
        dueDate: Value(lateEventStart),
      ),
    );

    final data = await getActionData();
    expect(data.events.any((e) => e.title == 'Late Evening Wrap-up'), isTrue);
    expect(data.dueTodayTodos.any((t) => t.id == ordinaryLateId), isTrue);
  });

  test('Phase 2 regression: earlier-missed DAILY series >= 300 days old retains affordance without exceeding expansion limit', () async {
    final anchorDate = LocalDate(2025, 12, 10);
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: anchorDate,
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'Long Running 300-day Habit',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    final data = await getActionData();

    expect(data.recurrenceExpansionErrors, isEmpty);
    expect(data.hasEarlierMissed, isTrue);
    expect(data.earlierMissedSeries.any((s) => s.id == seriesId), isTrue);
  });

  test('Phase 2 regression: DAILY series > 720 days old with terminal recent 720 days preserves earlier history entryway', () async {
    // 800 days ago from 2026-10-06
    final anchorDt = fixedToday.subtract(const Duration(days: 800));
    final anchorDate = LocalDate(anchorDt.year, anchorDt.month, anchorDt.day);
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: anchorDate,
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: '800-day Habit Series',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );
    final todo = await (db.select(db.todos)..where((t) => t.id.equals(seriesId))).getSingle();

    // Mark all occurrences from day -750 to today as completed.
    // This completes all occurrences in the 30-day recent window and all 24 probe pages (24 * 30 = 720 days).
    final statesToInsert = <TaskInstanceStatesCompanion>[];
    var currentDay = fixedToday.subtract(const Duration(days: 750));
    while (!currentDay.isAfter(fixedToday)) {
      final nextChunk = currentDay.add(const Duration(days: 50));
      final chunkExpansion = expandTodoOccurrences(
        todo,
        startInclusive: currentDay,
        endExclusive: nextChunk,
        maxOccurrences: 100,
      );
      for (final occ in chunkExpansion.occurrences) {
        statesToInsert.add(
          TaskInstanceStatesCompanion.insert(
            syncId: 'sync-${occ.occurrenceId}',
            todoSyncId: todo.syncId!,
            occurrenceId: occ.occurrenceId,
            status: const Value('completed'),
          ),
        );
      }
      currentDay = nextChunk;
    }
    await db.batch((b) {
      b.insertAll(db.taskInstanceStates, statesToInsert);
    });

    final data = await getActionData();

    // The probe horizon (24 pages = 720 days) was exhausted without reaching anchorDate (800 days ago).
    // Because all probed occurrences were terminal (completed), no pending item was found within horizon.
    // Instead of falsely dropping the series or asserting false certainty, tri-state earlierHistory is preserved.
    expect(data.hasEarlierMissed, isFalse);
    expect(data.earlierMissedSeries.any((s) => s.id == seriesId), isFalse);
    expect(data.hasEarlierHistory, isTrue);
    expect(data.earlierHistorySeries.any((s) => s.id == seriesId), isTrue);
  });
}
