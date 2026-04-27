import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';

void main() {
  late AppDatabase testDb;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await testDb.close();
  });

  group('Reminders', () {
    test('insert and read reminder', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      final eventId = await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 2),
            ),
          );

      final triggerTime = DateTime(2026, 4, 30, 23, 55);
      await testDb.into(testDb.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: triggerTime,
            ),
          );

      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders.length, 1);
      expect(reminders.first.parentType, 'event');
      expect(reminders.first.parentId, eventId);
      expect(reminders.first.isTriggered, false);
    });

    test('query reminders by parent', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      final eventId = await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 2),
            ),
          );
      final todoId = await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't1',
              summary: 'Task',
            ),
          );

      await testDb.into(testDb.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime(2026, 4, 30, 23, 55),
            ),
          );
      await testDb.into(testDb.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime(2026, 4, 30, 23, 45),
            ),
          );
      await testDb.into(testDb.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: DateTime(2026, 4, 29),
            ),
          );

      final eventReminders = await (testDb.select(testDb.reminders)
            ..where((t) =>
                t.parentType.equals('event') & t.parentId.equals(eventId)))
          .get();
      expect(eventReminders.length, 2);

      final todoReminders = await (testDb.select(testDb.reminders)
            ..where((t) =>
                t.parentType.equals('todo') & t.parentId.equals(todoId)))
          .get();
      expect(todoReminders.length, 1);
    });

    test('delete reminder', () async {
      final id = await testDb.into(testDb.reminders).insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: 1,
              triggerTime: DateTime(2026, 5, 1),
            ),
          );

      await (testDb.delete(testDb.reminders)..where((t) => t.id.equals(id))).go();
      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders.length, 0);
    });
  });
}
