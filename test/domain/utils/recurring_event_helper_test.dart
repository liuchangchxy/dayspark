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
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'One-time event',
              startDt: DateTime(2026, 5, 1, 10),
              endDt: DateTime(2026, 5, 1, 11),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final range = DateTimeRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 1),
      );

      final result = expandRecurringEvents(events, range);

      expect(result.length, 1);
      expect(result.first.title, 'One-time event');
    });

    test('expands daily recurring event into multiple instances', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e2',
              summary: 'Daily standup',
              startDt: DateTime(2026, 5, 1, 9),
              endDt: DateTime(2026, 5, 1, 9, 30),
              rrule: const Value('RRULE:FREQ=DAILY;COUNT=5'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final range = DateTimeRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 1),
      );

      final result = expandRecurringEvents(events, range);

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

    test('only returns instances within the given range', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e3',
              summary: 'Weekly review',
              startDt: DateTime(2026, 1, 1, 10),
              endDt: DateTime(2026, 1, 1, 11),
              rrule: const Value('RRULE:FREQ=WEEKLY;COUNT=10'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      // Only look at February
      final range = DateTimeRange(
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 2, 28),
      );

      final result = expandRecurringEvents(events, range);

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
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e4',
              summary: 'Bad rrule event',
              startDt: DateTime(2026, 5, 1, 10),
              endDt: DateTime(2026, 5, 1, 11),
              rrule: const Value('NOT_A_VALID_RRULE'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final range = DateTimeRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 1),
      );

      final result = expandRecurringEvents(events, range);

      // Should fall back gracefully
      expect(result.length, 1);
      expect(result.first.title, 'Bad rrule event');
    });

    test('uses colorForCalendar callback', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e5',
              summary: 'Colored event',
              startDt: DateTime(2026, 5, 1, 10),
              endDt: DateTime(2026, 5, 1, 11),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final range = DateTimeRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 1),
      );

      final result = expandRecurringEvents(
        events,
        range,
        colorForCalendar: (id) => Colors.red,
      );

      expect(result.first.color, Colors.red);
    });
  });
}
