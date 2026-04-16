import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(
            caldavHref: '/cal/',
            name: 'Test',
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('EventsDao', () {
    test('watchByDateRange returns events in range', () async {
      await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'Meeting',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
            ),
          );
      await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e2',
              summary: 'Other',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 1, 1),
            ),
          );

      final events = await db.eventsDao
          .watchByDateRange(DateTime(2026, 4, 1), DateTime(2026, 4, 30))
          .first;
      expect(events.length, 1);
      expect(events.first.summary, 'Meeting');
    });

    test('markDirty sets isDirty flag', () async {
      final eventId = await db.into(db.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e3',
              summary: 'Test',
              startDt: DateTime(2026, 1, 1),
              endDt: DateTime(2026, 1, 1, 1),
            ),
          );
      await db.eventsDao.markDirty(eventId);
      final event = await (db.select(db.events)
            ..where((t) => t.id.equals(eventId)))
          .getSingle();
      expect(event.isDirty, true);
    });
  });
}
