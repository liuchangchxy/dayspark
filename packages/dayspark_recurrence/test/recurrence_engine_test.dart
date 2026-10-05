import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'shared_vectors.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('strict RRULE validation', () {
    test('canonicalizes supported rules without changing their meaning', () {
      final rule = ValidatedRRule.parse(
        'byday=WE,MO;freq=weekly;count=4',
        valueType: RecurrenceValueType.dateTime,
      );
      expect(rule.canonical, 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4');
      expect(rule.toLibraryRule().count, 4);
    });

    test('classifies unknown valid RFC parts as unsupported', () {
      expect(
        () => ValidatedRRule.parse(
          'FREQ=DAILY;X-UNKNOWN=1',
          valueType: RecurrenceValueType.date,
        ),
        throwsA(
          isA<RecurrenceRuleException>().having(
            (error) => error.kind,
            'kind',
            RecurrenceRuleErrorKind.unsupported,
          ),
        ),
      );
    });

    test('rejects malformed, duplicated and incompatible fields', () {
      for (final value in [
        'FREQ=DAILY;FREQ=WEEKLY',
        'FREQ=DAILY;INTERVAL=0',
        'FREQ=DAILY;COUNT=1;UNTIL=20261001',
        'FREQ=WEEKLY;BYMONTHDAY=3',
        'FREQ=DAILY;BYDAY=0MO',
        'FREQ=MONTHLY;BYMONTHDAY=0',
        'FREQ=DAILY;INTERVAL=1000001',
        'FREQ=DAILY;COUNT=10001',
        'FREQ=MONTHLY;BYMONTHDAY=32',
        'FREQ=DAILY;UNTIL=20260230',
        'FREQ=DAILY;UNTIL=20261001T120000',
      ]) {
        expect(
          () => ValidatedRRule.parse(
            value,
            valueType: RecurrenceValueType.dateTime,
          ),
          throwsA(isA<RecurrenceRuleException>()),
          reason: value,
        );
      }
    });

    test('allows ordinal BYDAY only for MONTHLY and YEARLY', () {
      expect(
        ValidatedRRule.parse(
          'FREQ=MONTHLY;BYDAY=-1FR',
          valueType: RecurrenceValueType.date,
        ).canonical,
        'FREQ=MONTHLY;BYDAY=-1FR',
      );
      expect(
        () => ValidatedRRule.parse(
          'FREQ=WEEKLY;BYDAY=1MO',
          valueType: RecurrenceValueType.date,
        ),
        throwsA(isA<RecurrenceRuleException>()),
      );
    });

    test('rejects unsupported frequencies instead of delegating them', () {
      expect(
        () => ValidatedRRule.parse(
          'FREQ=SECONDLY',
          valueType: RecurrenceValueType.dateTime,
        ),
        throwsA(
          isA<RecurrenceRuleException>().having(
            (error) => error.kind,
            'kind',
            RecurrenceRuleErrorKind.unsupported,
          ),
        ),
      );
    });
  });

  group('identity and value types', () {
    test('DATE-TIME and DATE occurrence ids round-trip canonically', () {
      final dateTimeId = OccurrenceId.forNominal(
        LocalDateTime(2026, 3, 8, 2, 30, 0),
        'America/New_York',
      );
      expect(dateTimeId.value, 'v1:DT:2026-03-08T02:30:00@America/New_York');
      expect(OccurrenceId.parse(dateTimeId.value), dateTimeId);

      final dateId = OccurrenceId.forNominal(
        LocalDate(2026, 11, 2),
        'Asia/Shanghai',
      );
      expect(dateId.value, 'v2:DATE:2026-11-02');
      expect(OccurrenceId.parse(dateId.value), dateId);
      final legacyDateId = OccurrenceId.parse(
        'v1:DATE:2026-11-02@Asia/Shanghai',
      );
      expect(legacyDateId.nominal, dateId.nominal);
      expect(legacyDateId.timeZone?.id, 'Asia/Shanghai');
      expect(
        () => OccurrenceId.parse('v2:DATE:2026-02-30'),
        throwsFormatException,
      );
    });

    test('selects start over due and leaves missing anchors unsupported', () {
      final start = LocalDateTime(2026, 10, 5, 9, 0, 0);
      final due = LocalDate(2026, 10, 8);
      expect(
        selectRecurrenceAnchor(start: start, due: due)?.source,
        RecurrenceAnchorSource.start,
      );
      expect(
        selectRecurrenceAnchor(due: due)?.source,
        RecurrenceAnchorSource.due,
      );
      expect(selectRecurrenceAnchor(), isNull);
    });

    test('rejects impossible dates and non-IANA-shaped zones', () {
      expect(() => LocalDate(2026, 2, 30), throwsArgumentError);
      expect(
        () => RecurrenceSpec.parse(
          anchor: RecurrenceAnchor(
            source: RecurrenceAnchorSource.start,
            value: LocalDate(2026, 1, 1),
          ),
          timeZone: '+08:00',
          rrule: 'FREQ=DAILY;COUNT=2',
        ),
        throwsArgumentError,
      );
    });
  });

  group('nominal expansion and resolution', () {
    test('matches the shared externally specified vectors', () {
      const engine = RecurrenceEngine();
      for (final vector in recurrenceParityVectors()) {
        final occurrences = engine.expand(
          vector.spec,
          window: vector.window,
          limit: 100,
        );
        expect(
          occurrences.map(describeOccurrence).toList(),
          vector.expected,
          reason: vector.name,
        );
      }
    });

    test(
      'resolves a gap by the pre-transition offset and keeps nominal key',
      () {
        const engine = RecurrenceEngine();
        final spec = _spec(
          LocalDateTime(2026, 3, 8, 2, 30, 0),
          'America/New_York',
          'FREQ=DAILY;COUNT=1',
        );
        final occurrence = engine
            .expand(
              spec,
              window: _window('2026-03-08T07:00:00Z', '2026-03-08T08:00:00Z'),
              limit: 2,
            )
            .single;
        expect(
          occurrence.occurrenceId.value,
          'v1:DT:2026-03-08T02:30:00@America/New_York',
        );
        expect(occurrence.resolvedInstant, DateTime.utc(2026, 3, 8, 7, 30));
        final displayed = tz.TZDateTime.from(
          occurrence.resolvedInstant!,
          tz.getLocation('America/New_York'),
        );
        expect([displayed.hour, displayed.minute], [3, 30]);
        expect(displayed.timeZoneOffset, const Duration(hours: -4));
      },
    );

    test('resolves a fold to the earlier instant', () {
      const engine = RecurrenceEngine();
      final occurrence = engine
          .expand(
            _spec(
              LocalDateTime(2026, 11, 1, 1, 30, 0),
              'America/New_York',
              'FREQ=DAILY;COUNT=1',
            ),
            window: _window('2026-11-01T05:00:00Z', '2026-11-01T07:00:00Z'),
            limit: 2,
          )
          .single;
      expect(occurrence.resolvedInstant, DateTime.utc(2026, 11, 1, 5, 30));
      expect(
        occurrence.occurrenceId.value,
        'v1:DT:2026-11-01T01:30:00@America/New_York',
      );
    });

    test('COUNT includes a nominal gap occurrence', () {
      const engine = RecurrenceEngine();
      final occurrences = engine.expand(
        _spec(
          LocalDateTime(2026, 3, 7, 2, 30, 0),
          'America/New_York',
          'FREQ=DAILY;COUNT=3',
        ),
        window: _window('2026-03-07T00:00:00Z', '2026-03-11T00:00:00Z'),
        limit: 3,
      );
      expect(occurrences.map((item) => item.nominal.canonical), [
        '2026-03-07T02:30:00',
        '2026-03-08T02:30:00',
        '2026-03-09T02:30:00',
      ]);
    });

    test('DATE occurrences never expose a resolved instant', () {
      const engine = RecurrenceEngine();
      final spec = _spec(
        LocalDate(2026, 10, 5),
        'Asia/Shanghai',
        'FREQ=MONTHLY;BYMONTHDAY=5;COUNT=3',
      );
      final occurrences = engine.expand(
        spec,
        window: LocalDateWindow(
          startInclusive: LocalDate(2026, 10, 1),
          endExclusive: LocalDate(2027, 1, 1),
        ),
        limit: 3,
      );
      expect(occurrences.map((item) => item.nominal.canonical), [
        '2026-10-05',
        '2026-11-05',
        '2026-12-05',
      ]);
      expect(occurrences.every((item) => item.resolvedInstant == null), isTrue);
    });

    test('YEARLY recurrence preserves its anchor month and day', () {
      const engine = RecurrenceEngine();
      final occurrences = engine.expand(
        _spec(LocalDate(2026, 10, 5), 'UTC', 'FREQ=YEARLY;COUNT=3'),
        window: LocalDateWindow(
          startInclusive: LocalDate(2026, 1, 1),
          endExclusive: LocalDate(2029, 1, 1),
        ),
        limit: 3,
      );
      expect(occurrences.map((item) => item.nominal.canonical), [
        '2026-10-05',
        '2027-10-05',
        '2028-10-05',
      ]);
    });

    test('MONTHLY ordinal BYDAY expands to the nth weekday', () {
      const engine = RecurrenceEngine();
      final occurrences = engine.expand(
        _spec(LocalDate(2026, 10, 5), 'UTC', 'FREQ=MONTHLY;BYDAY=1MO;COUNT=3'),
        window: LocalDateWindow(
          startInclusive: LocalDate(2026, 10, 1),
          endExclusive: LocalDate(2027, 1, 1),
        ),
        limit: 3,
      );
      expect(occurrences.map((item) => item.nominal.canonical), [
        '2026-10-05',
        '2026-11-02',
        '2026-12-07',
      ]);
    });

    test('viewer local zone does not affect explicit series resolution', () {
      const engine = RecurrenceEngine();
      final spec = _spec(
        LocalDateTime(2026, 10, 5, 9, 0, 0),
        'Asia/Shanghai',
        'FREQ=DAILY;COUNT=1',
      );
      final window = _window('2026-10-05T00:00:00Z', '2026-10-06T00:00:00Z');
      final original = tz.local;
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
        expect(tz.local.name, 'UTC');
        final utcNamed = engine.expand(spec, window: window, limit: 1).single;
        tz.setLocalLocation(tz.getLocation('Etc/UTC'));
        expect(tz.local.name, 'Etc/UTC');
        final etcNamed = engine.expand(spec, window: window, limit: 1).single;
        expect(utcNamed.occurrenceId, etcNamed.occurrenceId);
        expect(utcNamed.resolvedInstant, etcNamed.resolvedInstant);
        expect(utcNamed.resolvedInstant, DateTime.utc(2026, 10, 5, 1));
      } finally {
        tz.setLocalLocation(original);
      }
    });

    test('requires a finite matching window and a positive bounded limit', () {
      const engine = RecurrenceEngine();
      final spec = _spec(LocalDate(2026, 1, 1), 'UTC', 'FREQ=DAILY');
      final window = LocalDateWindow(
        startInclusive: LocalDate(2026, 1, 1),
        endExclusive: LocalDate(2026, 1, 5),
      );
      expect(
        () => engine.expand(spec, window: window, limit: 0),
        throwsArgumentError,
      );
      expect(
        () => engine.expand(spec, window: window, limit: 3),
        throwsA(isA<RecurrenceExpansionException>()),
      );
      expect(
        () => engine.expand(
          spec,
          window: _window('2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z'),
          limit: 3,
        ),
        throwsArgumentError,
      );
    });

    test(
      'DATE identity ignores timezone metadata and bounds unbounded scans',
      () {
        const engine = RecurrenceEngine();
        final unknownZone = _spec(
          LocalDate(2026, 1, 1),
          'Mars/Olympus',
          'FREQ=DAILY;COUNT=1',
        );
        expect(
          engine
              .expand(
                unknownZone,
                window: LocalDateWindow(
                  startInclusive: LocalDate(2026, 1, 1),
                  endExclusive: LocalDate(2026, 1, 2),
                ),
                limit: 1,
              )
              .single
              .occurrenceId
              .value,
          'v2:DATE:2026-01-01',
        );

        final unbounded = _spec(
          LocalDate(1, 1, 1),
          'UTC',
          'FREQ=DAILY;INTERVAL=2',
        );
        expect(
          () => engine.expand(
            unbounded,
            window: LocalDateWindow(
              startInclusive: LocalDate(9000, 1, 1),
              endExclusive: LocalDate(9000, 1, 3),
            ),
            limit: 10,
          ),
          throwsA(isA<RecurrenceExpansionException>()),
        );
      },
    );

    test(
      'legacy v1 DATE allocation identities remain valid for their series',
      () {
        final spec = _spec(
          LocalDate(2026, 1, 1),
          'Asia/Shanghai',
          'FREQ=DAILY;COUNT=2',
        );
        expect(
          isOccurrenceValidForSpec(spec, 'v1:DATE:2026-01-02@Asia/Shanghai'),
          isTrue,
        );
        expect(
          isOccurrenceValidForSpec(spec, 'v1:DATE:2026-01-02@Asia/Tokyo'),
          isFalse,
        );
        expect(isOccurrenceValidForSpec(spec, 'v2:DATE:2026-01-02'), isTrue);
      },
    );

    test('fails closed beyond the bundled timezone transition horizon', () {
      const engine = RecurrenceEngine();
      final spec = _spec(
        LocalDateTime(9000, 1, 1, 9, 0, 0),
        'America/New_York',
        'FREQ=DAILY;COUNT=1',
      );
      expect(
        () => engine.expand(
          spec,
          window: _window('9000-01-01T00:00:00Z', '9000-01-02T00:00:00Z'),
          limit: 1,
        ),
        throwsA(isA<RecurrenceExpansionException>()),
      );
    });
  });
}

RecurrenceSpec _spec(
  RecurrenceLocalValue value,
  String timeZone,
  String rule,
) => RecurrenceSpec.parse(
  anchor: RecurrenceAnchor(source: RecurrenceAnchorSource.start, value: value),
  timeZone: timeZone,
  rrule: rule,
);

InstantWindow _window(String start, String end) => InstantWindow(
  startInclusive: DateTime.parse(start),
  endExclusive: DateTime.parse(end),
);
