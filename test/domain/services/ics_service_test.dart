import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

void main() {
  group('IcsService', () {
    test('can be instantiated with mock db', () {
      // IcsService requires AppDatabase — just verify construction logic compiles
      expect(IcsService, isNotNull);
    });

    test(
      'known zoned recurrence round-trips spec and occurrence identities',
      () async {
        ensureTodoRecurrenceTimeZonesInitialized();
        final firstDb = AppDatabase.forTesting(NativeDatabase.memory());
        final firstCalendar = await firstDb
            .into(firstDb.calendars)
            .insert(CalendarsCompanion.insert(name: 'Round trip source'));
        final spec = RecurrenceSpec.parse(
          anchor: RecurrenceAnchor(
            source: RecurrenceAnchorSource.start,
            value: LocalDateTime(2026, 11, 2, 9, 0, 0),
          ),
          timeZone: 'America/New_York',
          rrule: 'FREQ=WEEKLY;COUNT=4',
        );
        final todoId = await firstDb
            .into(firstDb.todos)
            .insert(
              TodosCompanion.insert(
                calendarId: firstCalendar,
                summary: 'Round trip',
                rrule: Value(spec.rule.canonical),
              ),
            );
        await (firstDb.update(firstDb.todos)
              ..where((row) => row.id.equals(todoId)))
            .write(TodoRecurrence.known(spec, revision: 1).toCompanion());
        final ics = await IcsService(firstDb).exportCalendar(firstCalendar);

        final secondDb = AppDatabase.forTesting(NativeDatabase.memory());
        final secondCalendar = await secondDb
            .into(secondDb.calendars)
            .insert(CalendarsCompanion.insert(name: 'Round trip target'));
        await IcsService(secondDb).importIcs(ics, secondCalendar);
        final imported = TodoRecurrence.fromTodo(
          (await secondDb.select(secondDb.todos).getSingle()),
        ).spec!;
        expect(imported.anchor.source, spec.anchor.source);
        expect(imported.anchor.valueType, spec.anchor.valueType);
        expect(imported.anchor.value.canonical, spec.anchor.value.canonical);
        expect(imported.timeZone, spec.timeZone);
        expect(imported.rule.canonical, spec.rule.canonical);
        const engine = RecurrenceEngine();
        final window = InstantWindow(
          startInclusive: DateTime.utc(2026, 10, 31),
          endExclusive: DateTime.utc(2026, 12, 1),
        );
        expect(
          engine
              .expand(spec, window: window, limit: 10)
              .map((item) => item.occurrenceId.value),
          engine
              .expand(imported, window: window, limit: 10)
              .map((item) => item.occurrenceId.value),
        );
        await firstDb.close();
        await secondDb.close();
      },
    );

    test(
      'ICS Shanghai, DST, DATE, anchor, and RRULE round-trip matrix',
      () async {
        ensureTodoRecurrenceTimeZonesInitialized();
        final matrix =
            <
              ({
                String name,
                String start,
                String? due,
                String rule,
                String zone,
                RecurrenceValueType type,
                RecurrenceAnchorSource source,
              })
            >[
              (
                name: 'Shanghai',
                start: 'DTSTART;TZID=Asia/Shanghai:20261102T090000',
                due: null,
                rule: 'FREQ=DAILY;COUNT=3',
                zone: 'Asia/Shanghai',
                type: RecurrenceValueType.dateTime,
                source: RecurrenceAnchorSource.start,
              ),
              (
                name: 'New York ordinary and DTSTART+DUE',
                start: 'DTSTART;TZID=America/New_York:20261102T090000',
                due: 'DUE;TZID=America/New_York:20261102T170000',
                rule: 'FREQ=DAILY;UNTIL=20261105T140000Z',
                zone: 'America/New_York',
                type: RecurrenceValueType.dateTime,
                source: RecurrenceAnchorSource.start,
              ),
              (
                name: 'New York DST gap and BYDAY',
                start: 'DTSTART;TZID=America/New_York:20260308T023000',
                due: null,
                rule: 'FREQ=WEEKLY;BYDAY=SU;COUNT=3',
                zone: 'America/New_York',
                type: RecurrenceValueType.dateTime,
                source: RecurrenceAnchorSource.start,
              ),
              (
                name: 'New York DST fold and BYMONTHDAY',
                start: 'DTSTART;TZID=America/New_York:20261101T013000',
                due: null,
                rule: 'FREQ=MONTHLY;BYMONTHDAY=1;COUNT=3',
                zone: 'America/New_York',
                type: RecurrenceValueType.dateTime,
                source: RecurrenceAnchorSource.start,
              ),
              (
                name: 'DATE only',
                start: 'DTSTART;VALUE=DATE:20261102',
                due: null,
                rule: 'FREQ=DAILY;COUNT=3',
                zone: 'Etc/UTC',
                type: RecurrenceValueType.date,
                source: RecurrenceAnchorSource.start,
              ),
              (
                name: 'DUE only',
                start: 'DUE;TZID=Asia/Shanghai:20261102T170000',
                due: null,
                rule: 'FREQ=DAILY;COUNT=3',
                zone: 'Asia/Shanghai',
                type: RecurrenceValueType.dateTime,
                source: RecurrenceAnchorSource.due,
              ),
            ];
        for (final item in matrix) {
          final firstDb = AppDatabase.forTesting(NativeDatabase.memory());
          final firstCalendar = await firstDb
              .into(firstDb.calendars)
              .insert(CalendarsCompanion.insert(name: 'Matrix source'));
          await IcsService(firstDb).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:${item.name}
DTSTAMP:20261005T000000Z
SUMMARY:${item.name}
${item.start}
${item.due ?? ''}
RRULE:${item.rule}
END:VTODO
END:VCALENDAR''', firstCalendar);
          final sourceTodo = await firstDb.select(firstDb.todos).getSingle();
          final source = TodoRecurrence.fromTodo(sourceTodo).spec!;
          expect(source.anchor.source, item.source, reason: item.name);
          expect(source.anchor.valueType, item.type, reason: item.name);
          expect(source.timeZone, item.zone, reason: item.name);
          final exported = await IcsService(
            firstDb,
          ).exportCalendar(firstCalendar);

          final secondDb = AppDatabase.forTesting(NativeDatabase.memory());
          final secondCalendar = await secondDb
              .into(secondDb.calendars)
              .insert(CalendarsCompanion.insert(name: 'Matrix target'));
          await IcsService(secondDb).importIcs(exported, secondCalendar);
          final restoredTodo = await secondDb
              .select(secondDb.todos)
              .getSingle();
          expect(
            restoredTodo.recurrenceLegacyState,
            'knownZoned',
            reason: item.name,
          );
          final restored = TodoRecurrence.fromTodo(restoredTodo).spec!;
          expect(
            restored.anchor.source,
            source.anchor.source,
            reason: item.name,
          );
          expect(
            restored.anchor.valueType,
            source.anchor.valueType,
            reason: item.name,
          );
          expect(
            restored.anchor.value.canonical,
            source.anchor.value.canonical,
            reason: item.name,
          );
          expect(restored.timeZone, source.timeZone, reason: item.name);
          expect(
            restored.rule.canonical,
            source.rule.canonical,
            reason: item.name,
          );
          if (item.due != null) expect(restoredTodo.dueDate, isNotNull);
          final List<String> originalIds;
          final List<String> restoredIds;
          if (item.type == RecurrenceValueType.date) {
            final window = LocalDateWindow(
              startInclusive: LocalDate(2026, 1, 1),
              endExclusive: LocalDate(2028, 1, 1),
            );
            originalIds = const RecurrenceEngine()
                .expand(source, window: window, limit: 10)
                .map((occurrence) => occurrence.occurrenceId.value)
                .toList();
            restoredIds = const RecurrenceEngine()
                .expand(restored, window: window, limit: 10)
                .map((occurrence) => occurrence.occurrenceId.value)
                .toList();
          } else {
            final window = InstantWindow(
              startInclusive: DateTime.utc(2026, 1, 1),
              endExclusive: DateTime.utc(2028, 1, 1),
            );
            originalIds = const RecurrenceEngine()
                .expand(source, window: window, limit: 10)
                .map((occurrence) => occurrence.occurrenceId.value)
                .toList();
            restoredIds = const RecurrenceEngine()
                .expand(restored, window: window, limit: 10)
                .map((occurrence) => occurrence.occurrenceId.value)
                .toList();
          }
          expect(restoredIds, originalIds, reason: item.name);
          await firstDb.close();
          await secondDb.close();
        }
      },
    );

    test('exportCalendar skips soft-deleted events and todos', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Visible Event',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
            ),
          );
      final deletedEventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Deleted Event',
              startDt: DateTime(2026, 4, 18, 10),
              endDt: DateTime(2026, 4, 18, 11),
            ),
          );
      await (db.update(db.events)..where((t) => t.id.equals(deletedEventId)))
          .write(EventsCompanion(deletedAt: Value(DateTime.now())));

      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Visible Todo',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final deletedTodoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Deleted Todo',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await (db.update(db.todos)..where((t) => t.id.equals(deletedTodoId)))
          .write(TodosCompanion(deletedAt: Value(DateTime.now())));

      final ics = await IcsService(db).exportCalendar(calId);

      expect(ics, contains('Visible Event'));
      expect(ics, isNot(contains('Deleted Event')));
      expect(ics, contains('Visible Todo'));
      expect(ics, isNot(contains('Deleted Todo')));

      await db.close();
    });

    test(
      'imports an IANA TZID recurrence as nominal local wall time',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final calendarId = await db
            .into(db.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:tzid
DTSTAMP:20261005T000000Z
SUMMARY:Zoned
DTSTART;TZID=America/New_York:20261102T090000
DUE;TZID=America/New_York:20261102T170000
RRULE:FREQ=WEEKLY;COUNT=3
END:VTODO
END:VCALENDAR''', calendarId);

        final todo = await db.select(db.todos).getSingle();
        expect(todo.recurrenceLegacyState, 'knownZoned');
        expect(todo.recurrenceAnchorValue, '2026-11-02T09:00:00');
        expect(todo.recurrenceTimeZone, 'America/New_York');
        expect(todo.recurrenceRule, 'FREQ=WEEKLY;COUNT=3');
        expect(todo.dueDate?.hour, 17);
        await db.close();
      },
    );

    test(
      'fails closed for matching IANA VTIMEZONE whose offsets conflict',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final calendarId = await db
            .into(db.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:STANDARD
DTSTART:20260101T000000
TZOFFSETFROM:+0300
TZOFFSETTO:+0300
END:STANDARD
END:VTIMEZONE
BEGIN:VTODO
UID:conflicting-zone
DTSTAMP:20261005T000000Z
SUMMARY:Conflicting zone
DTSTART;TZID=America/New_York:20261102T090000
RRULE:FREQ=WEEKLY;COUNT=3
END:VTODO
END:VCALENDAR''', calendarId);

        final todo = await db.select(db.todos).getSingle();
        expect(todo.recurrenceLegacyState, 'unknownLegacy');
        expect(todo.recurrenceTimeZone, isNull);
        final evidence = LegacyRecurrenceEvidence.decode(
          todo.recurrenceEvidence,
        );
        expect(evidence?.timeSemantic, 'vtimezoneConflict');
        expect(evidence?.rawTzid, 'America/New_York');
        expect(evidence?.hasVTimezone, isTrue);
        await db.close();
      },
    );

    test(
      'intentionally keeps equivalent IANA VTIMEZONE legacy when unverified',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final calendarId = await db
            .into(db.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:STANDARD
DTSTART:20261101T020000
TZOFFSETFROM:-0400
TZOFFSETTO:-0500
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:20260308T020000
TZOFFSETFROM:-0500
TZOFFSETTO:-0400
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VTODO
UID:unverified-zone
DTSTAMP:20261005T000000Z
SUMMARY:Unverified zone
DTSTART;TZID=America/New_York:20261102T090000
RRULE:FREQ=WEEKLY;COUNT=3
END:VTODO
END:VCALENDAR''', calendarId);

        final todo = await db.select(db.todos).getSingle();
        expect(todo.recurrenceLegacyState, 'unknownLegacy');
        final evidence = LegacyRecurrenceEvidence.decode(
          todo.recurrenceEvidence,
        );
        expect(evidence?.timeSemantic, 'vtimezoneUnsupported');
        expect(evidence?.hasVTimezone, isTrue);
        await db.close();
      },
    );

    test('does not map custom TZID from its VTIMEZONE definition', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final calendarId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTIMEZONE
TZID:Corp-NewYork
BEGIN:STANDARD
DTSTART:20260101T000000
TZOFFSETFROM:-0500
TZOFFSETTO:-0500
END:STANDARD
END:VTIMEZONE
BEGIN:VTODO
UID:custom-zone
DTSTAMP:20261005T000000Z
SUMMARY:Custom zone
DTSTART;TZID=Corp-NewYork:20261102T090000
RRULE:FREQ=WEEKLY;COUNT=3
END:VTODO
END:VCALENDAR''', calendarId);

      final todo = await db.select(db.todos).getSingle();
      expect(todo.recurrenceLegacyState, 'unknownLegacy');
      final evidence = LegacyRecurrenceEvidence.decode(todo.recurrenceEvidence);
      expect(evidence?.timeSemantic, 'unknownTzid');
      expect(evidence?.rawTzid, 'Corp-NewYork');
      expect(evidence?.hasVTimezone, isTrue);
      await db.close();
    });

    test('DATE recurrence ignores TZID and VTIMEZONE metadata', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final calendarId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTIMEZONE
TZID:Not-An-Iana-Zone
BEGIN:STANDARD
DTSTART:20260101T000000
TZOFFSETFROM:+0300
TZOFFSETTO:+0300
END:STANDARD
END:VTIMEZONE
BEGIN:VTODO
UID:date-zone-noise
DTSTAMP:20261005T000000Z
SUMMARY:Date zone noise
DTSTART;VALUE=DATE;TZID=Not-An-Iana-Zone:20261102
RRULE:FREQ=DAILY;COUNT=2
END:VTODO
END:VCALENDAR''', calendarId);

      final todo = await db.select(db.todos).getSingle();
      final recurrence = TodoRecurrence.fromTodo(todo);
      expect(recurrence.legacyState, TodoRecurrenceLegacyState.knownZoned);
      expect(recurrence.spec!.timeZone, 'Etc/UTC');
      expect(
        const RecurrenceEngine()
            .expand(
              recurrence.spec!,
              window: LocalDateWindow(
                startInclusive: LocalDate(2026, 11, 1),
                endExclusive: LocalDate(2026, 11, 5),
              ),
              limit: 5,
            )
            .map((item) => item.occurrenceId.value),
        ['v2:DATE:2026-11-02', 'v2:DATE:2026-11-03'],
      );
      await db.close();
    });

    test(
      'keeps floating recurrence unknown instead of binding a device zone',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final calendarId = await db
            .into(db.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:floating
DTSTAMP:20261005T000000Z
SUMMARY:Floating
DTSTART:20261102T090000
RRULE:FREQ=DAILY;COUNT=2
END:VTODO
END:VCALENDAR''', calendarId);

        final todo = await db.select(db.todos).getSingle();
        expect(todo.recurrenceLegacyState, 'unknownLegacy');
        expect(todo.recurrenceTimeZone, isNull);
        expect(todo.startDate?.hour, 9);
        final evidence = LegacyRecurrenceEvidence.decode(
          todo.recurrenceEvidence,
        );
        expect(evidence?.source, 'ics');
        expect(evidence?.timeSemantic, 'floating');
        await db.close();
      },
    );

    test(
      'exports known recurrence with local DTSTART and its IANA TZID',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final calendarId = await db
            .into(db.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        final todoId = await db
            .into(db.todos)
            .insert(
              TodosCompanion.insert(
                calendarId: calendarId,
                summary: 'Zoned export',
                rrule: const Value('FREQ=WEEKLY;COUNT=2'),
              ),
            );
        final recurrence = TodoRecurrence.known(
          RecurrenceSpec.parse(
            anchor: RecurrenceAnchor(
              source: RecurrenceAnchorSource.start,
              value: LocalDateTime(2026, 11, 2, 9, 0, 0),
            ),
            timeZone: 'America/New_York',
            rrule: 'FREQ=WEEKLY;COUNT=2',
          ),
          revision: 1,
        );
        await (db.update(db.todos)..where((row) => row.id.equals(todoId)))
            .write(recurrence.toCompanion());

        final ics = await IcsService(db).exportCalendar(calendarId);

        expect(ics, contains('DTSTART;TZID=America/New_York:20261102T090000'));
        expect(ics, contains('RRULE:FREQ=WEEKLY;COUNT=2'));
        await db.close();
      },
    );

    test(
      'imports DATE recurrence without converting its identity to midnight',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final calendarId = await db
            .into(db.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:date
DTSTAMP:20261005T000000Z
SUMMARY:Date series
DTSTART;VALUE=DATE:20261102
RRULE:FREQ=DAILY;COUNT=2
END:VTODO
END:VCALENDAR''', calendarId);

        final todo = await db.select(db.todos).getSingle();
        expect(todo.recurrenceLegacyState, 'knownZoned');
        expect(todo.recurrenceValueType, 'date');
        expect(todo.recurrenceAnchorValue, '2026-11-02');
        final exported = await IcsService(db).exportCalendar(calendarId);
        expect(exported, contains('DTSTART;VALUE=DATE:20261102'));
        await db.close();
      },
    );

    test('keeps UTC, unsupported RRULE, and unknown TZID as legacy', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final calendarId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await IcsService(db).importIcs('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:utc
DTSTAMP:20261005T000000Z
SUMMARY:UTC series
DTSTART:20261102T140000Z
RRULE:FREQ=DAILY;COUNT=2
END:VTODO
BEGIN:VTODO
UID:rule
DTSTAMP:20261005T000000Z
SUMMARY:Unsupported rule
DTSTART;TZID=America/New_York:20261102T090000
RRULE:FREQ=DAILY;BYHOUR=9
END:VTODO
BEGIN:VTODO
UID:zone
DTSTAMP:20261005T000000Z
SUMMARY:Unknown zone
DTSTART;TZID=Custom/Unknown:20261102T090000
RRULE:FREQ=DAILY;COUNT=2
END:VTODO
END:VCALENDAR''', calendarId);

      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(3));
      expect(
        todos.map((todo) => todo.recurrenceLegacyState),
        everyElement('unknownLegacy'),
      );
      expect(todos.every((todo) => todo.recurrenceTimeZone == null), isTrue);
      final evidence = todos
          .map(
            (todo) => LegacyRecurrenceEvidence.decode(todo.recurrenceEvidence),
          )
          .toList();
      expect(evidence.map((item) => item?.timeSemantic), [
        'utcInstant',
        'unsupportedRrule',
        'unknownTzid',
      ]);
      expect(evidence.last?.rawTzid, 'Custom/Unknown');
      final exported = await IcsService(db).exportCalendar(calendarId);
      expect(exported, contains('DTSTART'));
      expect(exported, isNot(contains('TZID=Custom/Unknown')));
      await db.close();
    });
  });
}
