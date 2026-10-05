import 'package:dayspark_recurrence/dayspark_recurrence.dart';

final class RecurrenceParityVector {
  const RecurrenceParityVector({
    required this.name,
    required this.spec,
    required this.window,
    required this.expected,
  });

  final String name;
  final RecurrenceSpec spec;
  final RecurrenceWindow window;
  final List<String> expected;
}

List<RecurrenceParityVector> recurrenceParityVectors() => [
  RecurrenceParityVector(
    name: 'Shanghai weekly 09:00 with BYDAY',
    spec: _dateTimeSpec(
      LocalDateTime(2026, 10, 5, 9, 0, 0),
      'Asia/Shanghai',
      'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4',
    ),
    window: _instantWindow('2026-10-04T00:00:00Z', '2026-10-16T00:00:00Z'),
    expected: [
      'v1:DT:2026-10-05T09:00:00@Asia/Shanghai|2026-10-05T01:00:00.000Z',
      'v1:DT:2026-10-07T09:00:00@Asia/Shanghai|2026-10-07T01:00:00.000Z',
      'v1:DT:2026-10-12T09:00:00@Asia/Shanghai|2026-10-12T01:00:00.000Z',
      'v1:DT:2026-10-14T09:00:00@Asia/Shanghai|2026-10-14T01:00:00.000Z',
    ],
  ),
  RecurrenceParityVector(
    name: 'New York spring-forward gap',
    spec: _dateTimeSpec(
      LocalDateTime(2026, 3, 7, 2, 30, 0),
      'America/New_York',
      'FREQ=DAILY;COUNT=3',
    ),
    window: _instantWindow('2026-03-07T00:00:00Z', '2026-03-10T00:00:00Z'),
    expected: [
      'v1:DT:2026-03-07T02:30:00@America/New_York|2026-03-07T07:30:00.000Z',
      'v1:DT:2026-03-08T02:30:00@America/New_York|2026-03-08T07:30:00.000Z',
      'v1:DT:2026-03-09T02:30:00@America/New_York|2026-03-09T06:30:00.000Z',
    ],
  ),
  RecurrenceParityVector(
    name: 'New York fall-back fold first instant',
    spec: _dateTimeSpec(
      LocalDateTime(2026, 11, 1, 1, 30, 0),
      'America/New_York',
      'FREQ=DAILY;COUNT=1',
    ),
    window: _instantWindow('2026-11-01T05:00:00Z', '2026-11-01T06:00:00Z'),
    expected: [
      'v1:DT:2026-11-01T01:30:00@America/New_York|2026-11-01T05:30:00.000Z',
    ],
  ),
  RecurrenceParityVector(
    name: 'DATE monthly on day five',
    spec: _dateSpec(
      LocalDate(2026, 10, 5),
      'Asia/Shanghai',
      'FREQ=MONTHLY;BYMONTHDAY=5;COUNT=3',
    ),
    window: LocalDateWindow(
      startInclusive: LocalDate(2026, 10, 1),
      endExclusive: LocalDate(2027, 1, 1),
    ),
    expected: [
      'v2:DATE:2026-10-05|DATE',
      'v2:DATE:2026-11-05|DATE',
      'v2:DATE:2026-12-05|DATE',
    ],
  ),
  RecurrenceParityVector(
    name: 'monthly BYMONTHDAY skips absent month days',
    spec: _dateSpec(
      LocalDate(2026, 1, 31),
      'Etc/UTC',
      'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4',
    ),
    window: LocalDateWindow(
      startInclusive: LocalDate(2026, 1, 1),
      endExclusive: LocalDate(2026, 8, 1),
    ),
    expected: [
      'v2:DATE:2026-01-31|DATE',
      'v2:DATE:2026-03-31|DATE',
      'v2:DATE:2026-05-31|DATE',
      'v2:DATE:2026-07-31|DATE',
    ],
  ),
  RecurrenceParityVector(
    name: 'DATE UNTIL is inclusive',
    spec: _dateSpec(
      LocalDate(2026, 10, 1),
      'America/New_York',
      'FREQ=DAILY;UNTIL=20261003',
    ),
    window: LocalDateWindow(
      startInclusive: LocalDate(2026, 10, 1),
      endExclusive: LocalDate(2026, 10, 5),
    ),
    expected: [
      'v2:DATE:2026-10-01|DATE',
      'v2:DATE:2026-10-02|DATE',
      'v2:DATE:2026-10-03|DATE',
    ],
  ),
  RecurrenceParityVector(
    name: 'DAILY INTERVAL cadence',
    spec: _dateTimeSpec(
      LocalDateTime(2026, 10, 1, 9, 0, 0),
      'Etc/UTC',
      'FREQ=DAILY;INTERVAL=2;COUNT=3',
    ),
    window: _instantWindow('2026-10-01T00:00:00Z', '2026-10-07T00:00:00Z'),
    expected: [
      'v1:DT:2026-10-01T09:00:00@Etc/UTC|2026-10-01T09:00:00.000Z',
      'v1:DT:2026-10-03T09:00:00@Etc/UTC|2026-10-03T09:00:00.000Z',
      'v1:DT:2026-10-05T09:00:00@Etc/UTC|2026-10-05T09:00:00.000Z',
    ],
  ),
  RecurrenceParityVector(
    name: 'inclusive UTC UNTIL',
    spec: _dateTimeSpec(
      LocalDateTime(2026, 10, 1, 9, 0, 0),
      'America/New_York',
      'FREQ=DAILY;UNTIL=20261002T130000Z',
    ),
    window: _instantWindow('2026-10-01T00:00:00Z', '2026-10-04T00:00:00Z'),
    expected: [
      'v1:DT:2026-10-01T09:00:00@America/New_York|2026-10-01T13:00:00.000Z',
      'v1:DT:2026-10-02T09:00:00@America/New_York|2026-10-02T13:00:00.000Z',
    ],
  ),
];

RecurrenceSpec _dateTimeSpec(
  LocalDateTime anchor,
  String timeZone,
  String rule,
) => RecurrenceSpec.parse(
  anchor: RecurrenceAnchor(source: RecurrenceAnchorSource.start, value: anchor),
  timeZone: timeZone,
  rrule: rule,
);

RecurrenceSpec _dateSpec(LocalDate anchor, String timeZone, String rule) =>
    RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.due,
        value: anchor,
      ),
      timeZone: timeZone,
      rrule: rule,
    );

InstantWindow _instantWindow(String start, String end) => InstantWindow(
  startInclusive: DateTime.parse(start),
  endExclusive: DateTime.parse(end),
);

String describeOccurrence(RecurrenceOccurrence occurrence) =>
    '${occurrence.occurrenceId.value}|'
    '${occurrence.resolvedInstant?.toIso8601String() ?? 'DATE'}';
