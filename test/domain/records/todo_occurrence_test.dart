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
        (tx) => TodoWriter.setCompletion(db, tx, todoId, isCompleted: true),
      );
      final rows = await db.select(db.taskAllocations).get();
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.occurrenceId), [occurrenceId, occurrenceId]);
      expect(rows.first.startAt, DateTime.utc(2026, 10, 11, 20));
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
}
