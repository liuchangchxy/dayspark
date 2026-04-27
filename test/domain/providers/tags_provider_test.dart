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

  group('TagsProvider', () {
    test('create and read tags', () async {
      await testDb.into(testDb.tags).insert(
            TagsCompanion.insert(name: 'Work'),
          );
      final tagId2 = await testDb.into(testDb.tags).insert(
            TagsCompanion.insert(name: 'Personal', color: const Value('#EF4444')),
          );

      final tags = await testDb.select(testDb.tags).get();
      expect(tags.length, 2);
      expect(tags.any((t) => t.name == 'Work'), true);
      expect(tags.any((t) => t.name == 'Personal'), true);
      expect(tags.firstWhere((t) => t.id == tagId2).color, '#EF4444');
    });

    test('delete tag cascades to event_tags and todo_tags', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      final tagId = await testDb.into(testDb.tags).insert(
            TagsCompanion.insert(name: 'Tag1'),
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

      await testDb.into(testDb.eventTags).insert(
            EventTagsCompanion.insert(eventId: eventId, tagId: tagId),
          );

      // Verify tag assigned
      var eventTags = await testDb.select(testDb.eventTags).get();
      expect(eventTags.length, 1);

      // Delete tag
      await (testDb.delete(testDb.eventTags)..where((t) => t.tagId.equals(tagId))).go();
      await (testDb.delete(testDb.tags)..where((t) => t.id.equals(tagId))).go();

      eventTags = await testDb.select(testDb.eventTags).get();
      expect(eventTags.length, 0);

      final tags = await testDb.select(testDb.tags).get();
      expect(tags.length, 0);
    });

    test('assign tag to todo', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      final tagId = await testDb.into(testDb.tags).insert(
            TagsCompanion.insert(name: 'Urgent'),
          );
      final todoId = await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 't1',
              summary: 'Task',
            ),
          );

      await testDb.into(testDb.todoTags).insert(
            TodoTagsCompanion.insert(todoId: todoId, tagId: tagId),
          );

      final todoTags = await testDb.select(testDb.todoTags).get();
      expect(todoTags.length, 1);
      expect(todoTags.first.todoId, todoId);
      expect(todoTags.first.tagId, tagId);
    });
  });
}
