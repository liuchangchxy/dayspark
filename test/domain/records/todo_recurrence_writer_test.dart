import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

RecurrenceSpec _spec({
  String timezone = 'Asia/Shanghai',
  String rule = 'FREQ=WEEKLY;COUNT=4',
}) => RecurrenceSpec.parse(
  anchor: RecurrenceAnchor(
    source: RecurrenceAnchorSource.start,
    value: LocalDateTime(2026, 10, 5, 9, 30, 0),
  ),
  timeZone: timezone,
  rrule: rule,
);

void main() {
  late AppDatabase db;
  late int calendarId;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calendarId = (await db.select(db.calendars).getSingle()).id;
  });

  tearDown(() => db.close());

  test(
    'knownZoned DATE-TIME spec round trips through structured columns',
    () async {
      final spec = _spec();
      late int id;
      await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'series',
            startDate: Value(DateTime(2026, 10, 5, 9, 30)),
            rrule: Value(spec.rule.canonical),
          ),
          recurrenceSpec: spec,
        ).then((value) => id = value),
      );

      final row = await (db.select(
        db.todos,
      )..where((todo) => todo.id.equals(id))).getSingle();
      final recurrence = TodoRecurrence.fromTodo(row);
      expect(recurrence.legacyState, TodoRecurrenceLegacyState.knownZoned);
      expect(recurrence.revision, 1);
      expect(
        recurrence.spec!.anchor.value.valueType,
        RecurrenceValueType.dateTime,
      );
      expect(recurrence.spec!.anchor.value.canonical, '2026-10-05T09:30:00');
      expect(recurrence.spec!.timeZone, 'Asia/Shanghai');
      expect(recurrence.spec!.rule.canonical, 'FREQ=WEEKLY;COUNT=4');
    },
  );

  test(
    'DATE persistence stays a date and retains independent timezone',
    () async {
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: RecurrenceAnchorSource.due,
          value: LocalDate(2026, 10, 5),
        ),
        timeZone: 'Pacific/Auckland',
        rrule: 'FREQ=DAILY;COUNT=3',
      );
      final id = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(calendarId: calendarId, summary: 'date series'),
          recurrenceSpec: spec,
        ),
      );
      final row = await (db.select(
        db.todos,
      )..where((todo) => todo.id.equals(id))).getSingle();
      expect(row.recurrenceValueType, 'date');
      expect(row.recurrenceAnchorValue, '2026-10-05');
      expect(row.recurrenceTimeZone, 'Pacific/Auckland');
      expect(
        TodoRecurrence.fromTodo(row).spec!.anchor.value,
        LocalDate(2026, 10, 5),
      );
    },
  );

  test(
    'update replaces the whole tuple and removal clears every active field',
    () async {
      final id = await RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(calendarId: calendarId, summary: 'series'),
          recurrenceSpec: _spec(),
        ),
      );
      final replacement = _spec(
        timezone: 'Asia/Tokyo',
        rule: 'FREQ=DAILY;COUNT=2',
      );
      await RecordScope.run(
        db,
        (tx) => TodoWriter.updateTodo(
          db,
          tx,
          id,
          const TodosCompanion(),
          recurrenceSpec: replacement,
          replaceRecurrence: true,
        ),
      );
      var row = await (db.select(
        db.todos,
      )..where((todo) => todo.id.equals(id))).getSingle();
      expect(TodoRecurrence.fromTodo(row).revision, 2);
      expect(row.recurrenceTimeZone, 'Asia/Tokyo');
      expect(row.recurrenceRule, 'FREQ=DAILY;COUNT=2');

      await RecordScope.run(
        db,
        (tx) => TodoWriter.updateTodo(
          db,
          tx,
          id,
          const TodosCompanion(),
          replaceRecurrence: true,
        ),
      );
      row = await (db.select(
        db.todos,
      )..where((todo) => todo.id.equals(id))).getSingle();
      expect(row.rrule, isNull);
      expect(row.recurrenceAnchorSource, isNull);
      expect(row.recurrenceValueType, isNull);
      expect(row.recurrenceAnchorValue, isNull);
      expect(row.recurrenceTimeZone, isNull);
      expect(row.recurrenceRule, isNull);
      expect(row.recurrenceLegacyState, isNull);
      expect(row.recurrenceRevision, 3);
    },
  );

  test('rrule-only creation and partial update are rejected', () async {
    await expectLater(
      RecordScope.run(
        db,
        (tx) => TodoWriter.create(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'partial',
            rrule: const Value('FREQ=DAILY'),
          ),
        ),
      ),
      throwsStateError,
    );
    expect(await db.select(db.todos).get(), isEmpty);
  });

  test(
    'legacy confirmation writes one known spec and sync outbox item',
    () async {
      final id = await RecordScope.run(
        db,
        (tx) => TodoWriter.importRow(
          db,
          tx,
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'legacy',
            dueDate: Value(DateTime.utc(2026, 10, 5, 1)),
            rrule: const Value('FREQ=DAILY;COUNT=2'),
          ),
        ),
      );
      final before = await (db.select(
        db.todos,
      )..where((todo) => todo.id.equals(id))).getSingle();
      expect(TodoRecurrence.fromTodo(before).isUnknownLegacy, isTrue);
      expect(before.recurrenceTimeZone, isNull);

      await RecordScope.run(
        db,
        (tx) => TodoWriter.confirmLegacyRecurrence(
          db,
          tx,
          todoId: id,
          chosenTimeZone: 'America/New_York',
          interpretation: RecurrenceAnchor(
            source: RecurrenceAnchorSource.due,
            value: LocalDateTime(2026, 10, 5, 1, 0, 0),
          ),
          validatedRRule: 'FREQ=DAILY;COUNT=2',
        ),
      );
      final after = await (db.select(
        db.todos,
      )..where((todo) => todo.id.equals(id))).getSingle();
      expect(
        TodoRecurrence.fromTodo(after).legacyState,
        TodoRecurrenceLegacyState.knownZoned,
      );
      expect(after.recurrenceRevision, 1);
      expect(after.recurrenceTimeZone, 'America/New_York');
      expect(after.recurrenceAnchorSource, 'due');
      expect(await db.select(db.syncOutbox).get(), hasLength(1));
    },
  );
}
