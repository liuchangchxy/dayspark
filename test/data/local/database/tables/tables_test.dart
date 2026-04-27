import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('CalendarsTable', () {
    test('insert and read a calendar', () async {
      final id = await db
          .into(db.calendars)
          .insert(
            CalendarsCompanion.insert(
              caldavHref: '/calendars/user/main/',
              name: 'My Calendar',
            ),
          );
      final calendar = await (db.select(
        db.calendars,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(calendar.name, 'My Calendar');
      expect(calendar.color, '#2563EB'); // default color
      expect(calendar.timezone, 'UTC'); // default timezone
      expect(calendar.caldavHref, '/calendars/user/main/');
    });

    test('insert calendar with explicit color and timezone', () async {
      final id = await db
          .into(db.calendars)
          .insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Work',
              color: const Value('#FF0000'),
              timezone: const Value('Asia/Shanghai'),
            ),
          );
      final calendar = await (db.select(
        db.calendars,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(calendar.color, '#FF0000');
      expect(calendar.timezone, 'Asia/Shanghai');
    });
  });

  group('EventsTable', () {
    test('insert and read an event', () async {
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      final eventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'uid-123',
              summary: 'Team Meeting',
              startDt: DateTime(2026, 4, 17, 15, 0),
              endDt: DateTime(2026, 4, 17, 16, 0),
            ),
          );
      final event = await (db.select(
        db.events,
      )..where((t) => t.id.equals(eventId))).getSingle();
      expect(event.summary, 'Team Meeting');
      expect(event.uid, 'uid-123');
      expect(event.isAllDay, false); // default
    });
  });

  group('TodosTable', () {
    test('insert and read a todo', () async {
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 'todo-456',
              summary: 'Buy groceries',
            ),
          );
      final todo = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.summary, 'Buy groceries');
      expect(todo.priority, 0); // default
      expect(todo.status, 'NEEDS-ACTION'); // default
    });

    test('insert todo with explicit priority and status', () async {
      final calId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'));
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 'todo-789',
              summary: 'Urgent task',
              priority: const Value(5),
              status: const Value('IN-PROCESS'),
            ),
          );
      final todo = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.priority, 5);
      expect(todo.status, 'IN-PROCESS');
    });
  });

  group('TagsTable', () {
    test('insert and read a tag', () async {
      final id = await db
          .into(db.tags)
          .insert(TagsCompanion.insert(name: 'Work'));
      final tag = await (db.select(
        db.tags,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(tag.name, 'Work');
      expect(tag.color, '#6B7280'); // default color
    });
  });

  group('SyncQueueTable', () {
    test('insert and read a sync queue item', () async {
      final id = await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              operation: 'create',
              resourceType: 'event',
              resourceId: 1,
            ),
          );
      final item = await (db.select(
        db.syncQueue,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(item.operation, 'create');
      expect(item.resourceType, 'event');
      expect(item.retryCount, 0); // default
    });
  });

  group('RemindersTable', () {
    test('insert and read a reminder', () async {
      final triggerTime = DateTime(2026, 4, 17, 14, 30);
      final id = await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: 1,
              triggerTime: triggerTime,
            ),
          );
      final reminder = await (db.select(
        db.reminders,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(reminder.parentType, 'event');
      expect(reminder.parentId, 1);
      expect(reminder.isTriggered, false); // default
    });
  });
}
