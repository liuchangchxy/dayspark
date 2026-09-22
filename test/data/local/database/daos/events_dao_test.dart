import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int calId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    await db.close();
  });

  group('EventsDao', () {
    test('watchByDateRange returns events in range', () async {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Meeting',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
            ),
          );
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
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

    test('watchDeletedEvents and restoreEvent roundtrip', () async {
      final id = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Soft deleted',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
              deletedAt: Value(DateTime.now()),
            ),
          );

      final deleted = await db.eventsDao.watchDeletedEvents().first;
      expect(deleted.length, 1);
      expect(deleted.first.id, id);

      await db.eventsDao.restoreEvent(id);

      expect(await db.eventsDao.watchDeletedEvents().first, isEmpty);
      final restored = await (db.select(
        db.events,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(restored.deletedAt, isNull);
    });

    test('hardDeleteEventWithChildren removes event and child rows', () async {
      final tagId = await db
          .into(db.tags)
          .insert(TagsCompanion.insert(name: 'tag'));
      final eventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Doomed',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
              deletedAt: Value(DateTime.now()),
            ),
          );
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime(2026, 4, 17, 9),
            ),
          );
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              filePath: '/tmp/a.txt',
              fileName: 'a.txt',
            ),
          );
      await db
          .into(db.eventTags)
          .insert(EventTagsCompanion.insert(eventId: eventId, tagId: tagId));

      await db.eventsDao.hardDeleteEventWithChildren(eventId);

      expect(
        await (db.select(
          db.events,
        )..where((t) => t.id.equals(eventId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(db.reminders)..where(
              (t) => t.parentType.equals('event') & t.parentId.equals(eventId),
            ))
            .get(),
        isEmpty,
      );
      expect(
        await (db.select(db.attachments)..where(
              (t) => t.parentType.equals('event') & t.parentId.equals(eventId),
            ))
            .get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.eventTags,
        )..where((t) => t.eventId.equals(eventId))).get(),
        isEmpty,
      );
    });

    test('emptyEventTrash deletes only soft-deleted events', () async {
      final keepId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Keep me',
              startDt: DateTime(2026, 4, 17, 10),
              endDt: DateTime(2026, 4, 17, 11),
            ),
          );
      final trashId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Trash me',
              startDt: DateTime(2026, 4, 18, 10),
              endDt: DateTime(2026, 4, 18, 11),
              deletedAt: Value(DateTime.now()),
            ),
          );

      await db.eventsDao.emptyEventTrash();

      expect(
        await (db.select(
          db.events,
        )..where((t) => t.id.equals(trashId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.events,
        )..where((t) => t.id.equals(keepId))).get(),
        hasLength(1),
      );
    });
  });
}
