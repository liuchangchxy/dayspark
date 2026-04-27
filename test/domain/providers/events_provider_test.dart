import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase testDb;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(testDb)],
    );
  });

  tearDown(() async {
    container.dispose();
    await testDb.close();
  });

  group('eventsProvider', () {
    test('eventsInDateRangeProvider returns events in range', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));

      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'April Event',
              startDt: DateTime(2026, 4, 15, 10),
              endDt: DateTime(2026, 4, 15, 11),
            ),
          );
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e2',
              summary: 'May Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 1, 1),
            ),
          );

      final events = await container.read(
        eventsInDateRangeProvider(
          DateTimeRange(
            start: DateTime(2026, 4, 1),
            end: DateTime(2026, 4, 30),
          ),
        ).future,
      );

      expect(events.length, 1);
      expect(events.first.summary, 'April Event');
    });

    test('createEvent inserts event', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));

      final id = await container
          .read(createEventProvider)
          .call(
            calendarId: calId,
            uid: 'new-uid',
            summary: 'New Event',
            startDt: DateTime(2026, 6, 1),
            endDt: DateTime(2026, 6, 1, 1),
            isAllDay: false,
          );

      expect(id, greaterThan(0));

      final event = await (testDb.select(
        testDb.events,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(event.summary, 'New Event');
    });
  });
}
