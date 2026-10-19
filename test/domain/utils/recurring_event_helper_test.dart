import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/utils/recurring_event_helper.dart';

void main() {
  late AppDatabase testDb;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await testDb.close();
  });

  group('expandRecurringEvents', () {
    test('returns single adapter for event without rrule', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'One-time event',
              startDt: DateTime(2026, 5, 1, 10),
              endDt: DateTime(2026, 5, 1, 11),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 4, 1),
        after: DateTime(2026, 6, 1),
      );

      expect(result.length, 1);
      expect(result.first.title, 'One-time event');
    });

    test('expands daily recurring event into multiple instances', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Daily standup',
              startDt: DateTime(2026, 5, 1, 9),
              endDt: DateTime(2026, 5, 1, 9, 30),
              rrule: const Value('RRULE:FREQ=DAILY;COUNT=5'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 4, 1),
        after: DateTime(2026, 6, 1),
      );

      expect(result.length, 5);
      // Each instance should have the same title and duration
      for (final adapter in result) {
        expect(adapter.title, 'Daily standup');
        expect(
          adapter.end.difference(adapter.start),
          const Duration(minutes: 30),
        );
      }
    });

    test('only returns instances within the given window', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Weekly review',
              startDt: DateTime(2026, 1, 1, 10),
              endDt: DateTime(2026, 1, 1, 11),
              rrule: const Value('RRULE:FREQ=WEEKLY;COUNT=10'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      // Only look at February
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 2, 1),
        after: DateTime(2026, 2, 28),
      );

      // Weekly from Jan 1 for 10 weeks: Jan 1,8,15,22,29, Feb 5,12,19,26, Mar 5
      // Within Feb range: Feb 5,12,19,26 = 4 instances
      expect(result.length, 4);
      for (final adapter in result) {
        expect(adapter.start.month, 2);
      }
    });

    test('falls back to single event on invalid rrule', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Bad rrule event',
              startDt: DateTime(2026, 5, 1, 10),
              endDt: DateTime(2026, 5, 1, 11),
              rrule: const Value('NOT_A_VALID_RRULE'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 4, 1),
        after: DateTime(2026, 6, 1),
      );

      // Should fall back gracefully
      expect(result.length, 1);
      expect(result.first.title, 'Bad rrule event');
    });

    test('every occurrence carries the series anchor', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final seriesStart = DateTime(2026, 10, 1, 9);
      final seriesEnd = DateTime(2026, 10, 1, 9, 30);
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Daily standup',
              startDt: seriesStart,
              endDt: seriesEnd,
              rrule: const Value('RRULE:FREQ=DAILY;COUNT=5'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 10, 1),
        after: DateTime(2026, 10, 31),
      );

      expect(result.length, 5);
      for (final adapter in result) {
        expect(
          adapter.isRecurringOccurrence,
          isTrue,
          reason: 'an expanded instance is not the series row',
        );
        expect(adapter.occurrenceStart, adapter.start);
        expect(
          adapter.seriesStart,
          seriesStart,
          reason: 'DTSTART must survive expansion untouched',
        );
        expect(adapter.seriesEnd, seriesEnd);
      }
      // The rendered instances still walk forward day by day.
      expect(result[2].start, DateTime(2026, 10, 3, 9));
    });

    test('a non-recurring event is never marked as an occurrence', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'One-off',
              startDt: DateTime(2026, 10, 1, 9),
              endDt: DateTime(2026, 10, 1, 10),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 10, 1),
        after: DateTime(2026, 10, 31),
      );

      expect(result.single.isRecurringOccurrence, isFalse);
      expect(result.single.seriesStart, DateTime(2026, 10, 1, 9));
    });

    test(
      'occurrences keep wall-clock times across month and year ends',
      () async {
        final calId = await testDb
            .into(testDb.calendars)
            .insert(CalendarsCompanion.insert(name: 'Test'));
        final seriesStart = DateTime(2026, 12, 28, 9);
        final seriesEnd = DateTime(2026, 12, 28, 9, 30);
        await testDb
            .into(testDb.events)
            .insert(
              EventsCompanion.insert(
                calendarId: calId,
                summary: 'Year end',
                startDt: seriesStart,
                endDt: seriesEnd,
                rrule: const Value('RRULE:FREQ=DAILY;COUNT=10'),
              ),
            );

        final events = await testDb.select(testDb.events).get();
        final result = expandRecurringEvents(
          events,
          before: DateTime(2026, 12, 1),
          after: DateTime(2027, 2, 1),
        );

        expect(result.length, 10);
        for (var i = 0; i < result.length; i++) {
          final expected = DateTime(2026, 12, 28 + i, 9);
          expect(
            result[i].start,
            expected,
            reason: 'instance $i drifted off its wall-clock slot',
          );
          expect(
            result[i].end.difference(result[i].start),
            const Duration(minutes: 30),
          );
          expect(result[i].seriesStart, seriesStart);
        }
      },
    );

    test('uses colorForCalendar callback', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Colored event',
              startDt: DateTime(2026, 5, 1, 10),
              endDt: DateTime(2026, 5, 1, 11),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final result = expandRecurringEvents(
        events,
        before: DateTime(2026, 4, 1),
        after: DateTime(2026, 6, 1),
        colorForCalendar: (id) => Colors.red,
      );

      expect(result.first.color, Colors.red);
    });
  });
}
