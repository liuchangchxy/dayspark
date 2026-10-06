import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/writers/task_allocation_writer.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  late AppDatabase db;
  late int calendarId;

  setUpAll(tzdata.initializeTimeZones);
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = (await db.select(db.calendars).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<int> createSeries(RecurrenceSpec spec) => RecordScope.run(
    db,
    (tx) => TodoWriter.create(
      db,
      tx,
      TodosCompanion.insert(
        calendarId: calendarId,
        summary: 'series',
        rrule: Value(spec.rule.canonical),
      ),
      recurrenceSpec: spec,
    ),
  );

  test('known DATE-TIME expansion preserves nominal key and instant', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(2026, 10, 5, 9, 0, 0),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=3',
    );
    final id = await createSeries(spec);
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    final result = expandTodoOccurrences(
      todo,
      startInclusive: DateTime.utc(2026, 10, 5),
      endExclusive: DateTime.utc(2026, 10, 8),
    );
    expect(result.status, TodoOccurrenceExpansionStatus.expanded);
    expect(result.occurrences, hasLength(3));
    expect(
      result.occurrences.first.nominalAnchor.canonical,
      '2026-10-05T09:00:00',
    );
    expect(result.occurrences.first.occurrenceId, contains('@Asia/Shanghai'));
    expect(result.occurrences.first.resolvedStartInstant, isNotNull);
    expect(result.occurrences.first.todoSyncId, todo.syncId);
  });

  test('DATE expansion has no execution instant', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 10, 5),
      ),
      timeZone: 'Pacific/Auckland',
      rrule: 'FREQ=DAILY;COUNT=2',
    );
    final id = await createSeries(spec);
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    final result = expandTodoOccurrences(
      todo,
      startInclusive: DateTime(2026, 10, 5),
      endExclusive: DateTime(2026, 10, 7),
    );
    expect(result.occurrences, hasLength(2));
    expect(result.occurrences.first.nominalAnchor, LocalDate(2026, 10, 5));
    expect(result.occurrences.first.resolvedStartInstant, isNull);
  });

  test(
    'missed recurrence stays a lazy pending occurrence after midnight',
    () async {
      final today = DateTime.now();
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            9,
            0,
            0,
          ),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=3',
      );
      final id = await createSeries(spec);
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(id))).getSingle();
      final expansion = expandTodoOccurrences(
        todo,
        startInclusive: yesterday,
        endExclusive: DateTime(today.year, today.month, today.day + 1),
      );
      expect(expansion.status, TodoOccurrenceExpansionStatus.expanded);
      expect(
        expansion.occurrences.first.nominalAnchor.canonical,
        startsWith('${yesterday.year}-'),
      );
      expect(
        await db.select(db.taskInstanceStates).get(),
        isEmpty,
        reason:
            'crossing midnight must not synthesize completion or skip state',
      );
    },
  );

  test(
    'history page joins state by its occurrence ids beyond the latest 100',
    () async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2030, 1, 1, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=150',
      );
      final todoId = await createSeries(spec);
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final all = expandTodoOccurrences(
        todo,
        startInclusive: DateTime.utc(2030, 1, 1),
        endExclusive: DateTime.utc(2030, 6, 1),
        maxOccurrences: 200,
      ).occurrences;
      expect(all, hasLength(150));
      final fixedTime = DateTime.utc(2029);
      for (var index = 0; index < all.length; index++) {
        if (index == 10) continue; // Sparse absence is still pending.
        await db
            .into(db.taskInstanceStates)
            .insert(
              TaskInstanceStatesCompanion.insert(
                syncId: 'historical-state-$index',
                todoSyncId: todo.syncId!,
                occurrenceId: all[index].occurrenceId,
                status: Value(
                  index == 5 || index == 120 ? 'skipped' : 'completed',
                ),
                updatedAt: Value(fixedTime.add(Duration(days: index))),
              ),
            );
      }

      Future<TodoOccurrenceExpansion> page(int index) async =>
          TodoOccurrenceExpansion(TodoOccurrenceExpansionStatus.expanded, [
            all[index],
          ]);
      final oldCompleted = await projectTodoOccurrenceStates(db, await page(4));
      expect(oldCompleted, hasLength(1));
      expect(oldCompleted.single.status, 'completed');
      final oldSkipped = await projectTodoOccurrenceStates(db, await page(5));
      expect(oldSkipped.single.status, 'skipped');
      final stillPending = await projectTodoOccurrenceStates(
        db,
        await page(10),
      );
      expect(stillPending.single.status, 'pending');
      final anotherPage = await projectTodoOccurrenceStates(
        db,
        await page(120),
      );
      expect(anotherPage.single.status, 'skipped');
      final unpersisted = await projectTodoOccurrenceStates(
        db,
        await page(149),
      );
      expect(unpersisted.single.status, 'completed');
      expect(await db.select(db.taskInstanceStates).get(), hasLength(149));
      expect(
        oldCompleted.length,
        1,
        reason: 'projection result is bounded to the requested occurrence page',
      );

      final ordinaryId = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(calendarId: calendarId, summary: 'ordinary'),
        ),
      );
      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(db, tx, ordinaryId, isCompleted: true),
      );
      final ordinary = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(ordinaryId))).getSingle();
      expect(ordinary.status, 'COMPLETED');
    },
  );

  test(
    'one occurrence accepts multiple allocations and rescheduling keeps key',
    () async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2026, 10, 5, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=WEEKLY;COUNT=4',
      );
      final todoId = await createSeries(spec);
      final occurrenceId = OccurrenceId.forNominal(
        spec.anchor.value,
        spec.timeZone,
      ).value;
      final first = await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: occurrenceId,
          startAt: DateTime.utc(2026, 10, 4, 20),
          endAt: DateTime.utc(2026, 10, 4, 21),
        ),
      );
      final second = await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: occurrenceId,
          startAt: DateTime.utc(2026, 10, 4, 22),
          endAt: DateTime.utc(2026, 10, 4, 23),
        ),
      );
      await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.reschedule(
          db,
          tx,
          id: first,
          startAt: DateTime.utc(2026, 10, 11, 20),
          endAt: DateTime.utc(2026, 10, 11, 21),
        ),
      );
      await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.cancel(db, tx, second),
      );
      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(
          db,
          tx,
          todoId,
          isCompleted: true,
          occurrenceId: occurrenceId,
        ),
      );
      final rows = await db.select(db.taskAllocations).get();
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.occurrenceId), [occurrenceId, occurrenceId]);
      expect(rows.first.startAt, DateTime.utc(2026, 10, 11, 20));
      expect(rows.first.state, 'invalidatedByCompletion');
      expect(rows.last.id, second);
      expect(rows.last.state, 'cancelledByUser');
    },
  );

  test('fake occurrence identity is rejected', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(2026, 10, 5, 9, 0, 0),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=WEEKLY;COUNT=4',
    );
    final todoId = await createSeries(spec);
    await expectLater(
      RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: 'v1:DT:2026-10-06T09:00:00@Asia/Shanghai',
          startAt: DateTime.utc(2026, 10, 5, 20),
          endAt: DateTime.utc(2026, 10, 5, 21),
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.taskAllocations).get(), isEmpty);
  });

  test(
    'instance completion leaves the series and sibling allocation active',
    () async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2026, 10, 5, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=DAILY;COUNT=2',
      );
      final todoId = await createSeries(spec);
      final firstId = OccurrenceId.forNominal(
        spec.anchor.value,
        spec.timeZone,
      ).value;
      final secondId = OccurrenceId.forNominal(
        LocalDateTime(2026, 10, 6, 9, 0, 0),
        spec.timeZone,
      ).value;
      final firstAllocation = await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: firstId,
          startAt: DateTime.now().toUtc().add(const Duration(days: 1)),
          endAt: DateTime.now().toUtc().add(const Duration(days: 1, hours: 1)),
        ),
      );
      final secondAllocation = await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: secondId,
          startAt: DateTime.now().toUtc().add(const Duration(days: 2)),
          endAt: DateTime.now().toUtc().add(const Duration(days: 2, hours: 1)),
        ),
      );
      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(
          db,
          tx,
          todoId,
          isCompleted: true,
          occurrenceId: firstId,
        ),
      );

      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final first = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(firstAllocation))).getSingle();
      final second = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(secondAllocation))).getSingle();
      final state = await db.select(db.taskInstanceStates).getSingle();
      expect(todo.status, 'NEEDS-ACTION');
      expect(state.occurrenceId, firstId);
      expect(first.state, 'invalidatedByCompletion');
      expect(second.state, 'active');

      await RecordScope.run(
        db,
        (tx) => TodoWriter.setCompletion(
          db,
          tx,
          todoId,
          isCompleted: false,
          occurrenceId: firstId,
        ),
      );
      final reopened = await (db.select(
        db.taskInstanceStates,
      )..where((row) => row.occurrenceId.equals(firstId))).getSingle();
      final stillInvalidated = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(firstAllocation))).getSingle();
      expect(reopened.status, 'pending');
      expect(stillInvalidated.state, 'invalidatedByCompletion');
    },
  );

  test('unknown legacy is a distinct non-expanded result', () async {
    final id = await RecordScope.run(
      db,
      (tx) => TodoWriter.importRow(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'legacy',
          rrule: const Value('FREQ=DAILY;COUNT=2'),
        ),
      ),
    );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    final result = expandTodoOccurrences(
      todo,
      startInclusive: DateTime.utc(2026, 10, 5),
      endExclusive: DateTime.utc(2026, 10, 7),
    );
    expect(
      result.status,
      TodoOccurrenceExpansionStatus.requiresLegacyConfirmation,
    );
    expect(result.occurrences, isEmpty);
    await expectLater(
      RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: id,
          occurrenceId: 'forged',
          startAt: DateTime.utc(2026, 10, 5, 9),
          endAt: DateTime.utc(2026, 10, 5, 10),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('legacy recurrence must be confirmed'),
        ),
      ),
    );
  });

  test(
    'series edits orphan old keys without rewriting Allocation rows',
    () async {
      final original = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2026, 10, 5, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=4',
      );
      final todoId = await createSeries(original);
      final todo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final occurrenceId = OccurrenceId.forNominal(
        original.anchor.value,
        original.timeZone,
      ).value;
      final allocationId = await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: occurrenceId,
          startAt: DateTime.utc(2026, 10, 11, 20),
          endAt: DateTime.utc(2026, 10, 11, 21),
        ),
      );
      expect(isOccurrenceStillValidForSeries(todo, occurrenceId), isTrue);
      await RecordScope.run(
        db,
        (tx) => TodoWriter.updateTodo(
          db,
          tx,
          todoId,
          const TodosCompanion(),
          recurrenceSpec: RecurrenceSpec.parse(
            anchor: RecurrenceAnchor(
              source: RecurrenceAnchorSource.start,
              value: LocalDateTime(2026, 10, 5, 10, 0, 0),
            ),
            timeZone: 'Asia/Tokyo',
            rrule: 'FREQ=WEEKLY;BYDAY=TU;COUNT=4',
          ),
          replaceRecurrence: true,
        ),
      );
      final changedTodo = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final allocation = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(allocationId))).getSingle();
      expect(allocation.occurrenceId, occurrenceId);
      expect(allocation.startAt, DateTime.utc(2026, 10, 11, 20));
      expect(
        isOccurrenceStillValidForSeries(changedTodo, occurrenceId),
        isFalse,
      );
    },
  );
  test(
    'series timezone, anchor, RRULE edits and removal orphan old keys',
    () async {
      final original = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.start,
          value: LocalDateTime(2026, 10, 5, 9, 0, 0),
        ),
        timeZone: 'Asia/Shanghai',
        rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=4',
      );
      final todoId = await createSeries(original);
      final oldId = OccurrenceId.forNominal(
        original.anchor.value,
        original.timeZone,
      ).value;
      final retainedId = await RecordScope.run(
        db,
        (tx) => TaskAllocationWriter.create(
          db,
          tx,
          todoId: todoId,
          occurrenceId: oldId,
          startAt: DateTime.utc(2026, 10, 4, 20),
          endAt: DateTime.utc(2026, 10, 4, 21),
        ),
      );
      final edits = <RecurrenceSpec>[
        RecurrenceSpec.parse(
          anchor: original.anchor,
          timeZone: 'Asia/Tokyo',
          rrule: original.rule.canonical,
        ),
        RecurrenceSpec.parse(
          anchor: RecurrenceAnchor(
            source: RecurrenceAnchorSource.start,
            value: LocalDateTime(2026, 10, 5, 10, 0, 0),
          ),
          timeZone: original.timeZone,
          rrule: original.rule.canonical,
        ),
        RecurrenceSpec.parse(
          anchor: original.anchor,
          timeZone: original.timeZone,
          rrule: 'FREQ=WEEKLY;BYDAY=TU;COUNT=4',
        ),
      ];
      for (final edit in edits) {
        await RecordScope.run(
          db,
          (tx) => TodoWriter.updateTodo(
            db,
            tx,
            todoId,
            const TodosCompanion(),
            recurrenceSpec: edit,
            replaceRecurrence: true,
          ),
        );
        final changed = await (db.select(
          db.todos,
        )..where((row) => row.id.equals(todoId))).getSingle();
        expect(isOccurrenceStillValidForSeries(changed, oldId), isFalse);
        final retained = await (db.select(
          db.taskAllocations,
        )..where((row) => row.id.equals(retainedId))).getSingle();
        expect(retained.occurrenceId, oldId);
        await RecordScope.run(
          db,
          (tx) => TodoWriter.updateTodo(
            db,
            tx,
            todoId,
            const TodosCompanion(),
            recurrenceSpec: original,
            replaceRecurrence: true,
          ),
        );
      }
      await RecordScope.run(
        db,
        (tx) => TodoWriter.updateTodo(
          db,
          tx,
          todoId,
          const TodosCompanion(),
          replaceRecurrence: true,
        ),
      );
      final ordinary = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      expect(isOccurrenceStillValidForSeries(ordinary, oldId), isFalse);
      final retained = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(retainedId))).getSingle();
      expect(retained.occurrenceId, oldId);
    },
  );

  test('ProjectedTaskInstance DATE semantics (Ruling E)', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(2026, 10, 1),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final id = await createSeries(spec);
    final todo = await (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();

    final todayOccurrence = TodoOccurrence(
      todoSyncId: todo.syncId!,
      occurrenceId: 'v2:DATE:2026-10-06',
      nominalAnchor: LocalDate(2026, 10, 6),
      resolvedStartInstant: null,
      timeZone: 'Asia/Shanghai',
    );
    final missedOccurrence = TodoOccurrence(
      todoSyncId: todo.syncId!,
      occurrenceId: 'v2:DATE:2026-10-04',
      nominalAnchor: LocalDate(2026, 10, 4),
      resolvedStartInstant: null,
      timeZone: 'Asia/Shanghai',
    );
    final earlierOccurrence = TodoOccurrence(
      todoSyncId: todo.syncId!,
      occurrenceId: 'v2:DATE:2026-08-01',
      nominalAnchor: LocalDate(2026, 8, 1),
      resolvedStartInstant: null,
      timeZone: 'Asia/Shanghai',
    );

    final actionDate = DateTime(2026, 10, 6);

    final todayInstance = ProjectedTaskInstance(
      todo: todo,
      occurrence: todayOccurrence,
      status: 'pending',
    );
    expect(todayInstance.isToday(actionDate), isTrue);
    expect(todayInstance.isMissedWithin30Days(actionDate), isFalse);
    expect(todayInstance.isEarlierMissed(actionDate), isFalse);

    final missedInstance = ProjectedTaskInstance(
      todo: todo,
      occurrence: missedOccurrence,
      status: 'pending',
    );
    expect(missedInstance.isToday(actionDate), isFalse);
    expect(missedInstance.isMissedWithin30Days(actionDate), isTrue);
    expect(missedInstance.isEarlierMissed(actionDate), isFalse);

    final earlierInstance = ProjectedTaskInstance(
      todo: todo,
      occurrence: earlierOccurrence,
      status: 'pending',
    );
    expect(earlierInstance.isToday(actionDate), isFalse);
    expect(earlierInstance.isMissedWithin30Days(actionDate), isFalse);
    expect(earlierInstance.isEarlierMissed(actionDate), isTrue);
  });

  test('ProjectedTaskInstance DATE-TIME resolved instant Action-day semantics (Ruling E)', () async {
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDateTime(2026, 10, 5, 20, 0, 0),
      ),
      timeZone: 'America/New_York',
      rrule: 'FREQ=DAILY',
    );
    final id = await createSeries(spec);
    final todo = await (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();

    // 2026-10-05 20:00 EDT = 2026-10-06 00:00 UTC.
    // For a local execution day [2026-10-06 00:00 UTC, 2026-10-07 00:00 UTC),
    // this resolved instant falls on today!
    final instant = DateTime.utc(2026, 10, 6, 0, 0, 0);
    final occ = TodoOccurrence(
      todoSyncId: todo.syncId!,
      occurrenceId: 'v1:DT:2026-10-05T20:00:00@America/New_York',
      nominalAnchor: LocalDateTime(2026, 10, 5, 20, 0, 0),
      resolvedStartInstant: instant,
      timeZone: 'America/New_York',
    );

    final actionDate = DateTime.utc(2026, 10, 6);
    final instance = ProjectedTaskInstance(
      todo: todo,
      occurrence: occ,
      status: 'pending',
    );

    expect(instance.isToday(actionDate), isTrue);
    expect(instance.isMissedWithin30Days(actionDate), isFalse);
  });

  test('loadOccurrencePage pages bounded history and future with sparse state overlay', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchor = today.subtract(const Duration(days: 40));

    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: LocalDate(anchor.year, anchor.month, anchor.day),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    );
    final id = await createSeries(spec);
    final todo = await (db.select(db.todos)..where((row) => row.id.equals(id))).getSingle();

    // Page 1: [today - 30, today + 91)
    final page1 = await loadOccurrencePage(db, todo, historyPage: 1, anchorDate: today);
    expect(page1, isNotEmpty);
    expect(page1.any((i) => i.isToday(today)), isTrue);

    // Page 2: [today - 60, today - 30)
    final page2 = await loadOccurrencePage(db, todo, historyPage: 2, anchorDate: today);
    expect(page2, isNotEmpty);
    expect(page2.every((i) => i.isEarlierMissed(today) || i.isMissedWithin30Days(today)), isTrue);
  });
}
