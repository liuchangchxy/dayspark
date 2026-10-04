import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('TodoRecurrenceDto', () {
    test('round trips DATE and DATE-TIME as distinct values', () {
      for (final spec in [
        {
          'anchor': {
            'source': 'due',
            'valueType': 'date',
            'value': '2026-10-05',
          },
          'timeZone': 'Asia/Shanghai',
          'rrule': 'FREQ=DAILY;COUNT=2',
        },
        {
          'anchor': {
            'source': 'start',
            'valueType': 'dateTime',
            'value': '2026-10-05T09:30:00',
          },
          'timeZone': 'Asia/Tokyo',
          'rrule': 'FREQ=WEEKLY;COUNT=2',
        },
      ]) {
        final value = TodoRecurrenceDto.fromTodoPayload({
          'recurrenceSpec': spec,
          'recurrenceRevision': 4,
          'recurrenceLegacyState': 'knownZoned',
          'rrule': spec['rrule'],
        });
        final restored = TodoRecurrenceDto.fromTodoPayload(value.toJson());
        expect(
          restored.spec!.anchor.value.valueType,
          value.spec!.anchor.value.valueType,
        );
        expect(
          restored.spec!.anchor.value.canonical,
          value.spec!.anchor.value.canonical,
        );
        expect(restored.spec!.timeZone, value.spec!.timeZone);
        expect(restored.revision, 4);
      }
    });

    test(
      'old payload remains accepted and classifies recurring data safely',
      () {
        final ordinary = TodoRecurrenceDto.fromTodoPayload({
          'summary': 'plain',
        });
        final legacy = TodoRecurrenceDto.fromTodoPayload({
          'summary': 'old series',
          'rrule': 'FREQ=DAILY',
          'startDate': '2026-10-05T01:00:00Z',
        });
        expect(ordinary.legacyState, isNull);
        expect(legacy.spec, isNull);
        expect(legacy.legacyState, RecurrenceLegacyState.unknownLegacy);
        expect(legacy.revision, 0);
      },
    );

    test('rejects partial recurrence and unknown tuple members', () {
      expect(
        () => TodoRecurrenceDto.fromTodoPayload({
          'recurrenceSpec': {'timeZone': 'UTC'},
          'recurrenceRevision': 1,
          'recurrenceLegacyState': 'knownZoned',
        }),
        throwsFormatException,
      );
      expect(
        () => RecurrenceSpecDto.fromJson({
          'anchor': {
            'source': 'start',
            'valueType': 'date',
            'value': '2026-10-05',
            'hidden': true,
          },
          'timeZone': 'UTC',
          'rrule': 'FREQ=DAILY',
        }),
        throwsFormatException,
      );
    });

    test('unknown record payload keys stay forward-compatible', () {
      final record = SyncRecord.fromJson({
        'id': 'todo-1',
        'type': 'todo',
        'payload': {
          'summary': 'title',
          'futureField': {'x': 1},
        },
        'rev': 1,
        'deleted': false,
        'serverTs': '2026-10-05T00:00:00Z',
      });
      expect(record.payload['futureField'], {'x': 1});
    });
  });
}
