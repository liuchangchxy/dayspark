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

    // 软删现在保留提醒行（与待办侧对称），所以"永久删除必须硬删行"是这条链上
    // 唯一的清道夫：漏了它，回收站清空后惰性行就永久留在库里成垃圾。
    test('emptyEventTrash 连带硬删回收站事件的 reminders 行（活跃事件不受影响）',
        () async {
      final liveId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Live',
              startDt: DateTime(2026, 4, 19, 10),
              endDt: DateTime(2026, 4, 19, 11),
            ),
          );
      final trashId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Trashed',
              startDt: DateTime(2026, 4, 20, 10),
              endDt: DateTime(2026, 4, 20, 11),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final liveReminderId = await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: liveId,
              triggerTime: DateTime(2026, 4, 19, 9),
            ),
          );
      final trashReminderId = await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: trashId,
              triggerTime: DateTime(2026, 4, 20, 9),
            ),
          );

      await db.eventsDao.emptyEventTrash();

      final remaining = await db.select(db.reminders).get();
      expect(
        remaining.map((r) => r.id),
        [liveReminderId],
        reason: '回收站事件的提醒行（$trashReminderId）必须随硬删消失，活跃事件的保留',
      );
    });
  });
}
