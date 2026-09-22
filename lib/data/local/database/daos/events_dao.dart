import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/events_table.dart';
import '../tables/event_tags_table.dart';
import '../tables/reminders_table.dart';
import '../tables/attachments_table.dart';

part 'events_dao.g.dart';

@DriftAccessor(tables: [Events, EventTags, Reminders, Attachments])
class EventsDao extends DatabaseAccessor<AppDatabase> with _$EventsDaoMixin {
  EventsDao(super.db);

  Stream<List<Event>> watchByDateRange(DateTime start, DateTime end) {
    return (select(events)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.startDt.isSmallerThanValue(end) &
                t.endDt.isBiggerThanValue(start),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)]))
        .watch();
  }

  Future<void> upsert(Event entry) {
    return into(events).insertOnConflictUpdate(entry);
  }

  Future<List<Event>> searchEvents(String query) {
    final pattern = '%$query%';
    return (select(events)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                (t.summary.like(pattern) | t.description.like(pattern)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
          ..limit(50))
        .get();
  }

  Stream<List<Event>> watchDeletedEvents() {
    return (select(events)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  Future<void> restoreEvent(int id) {
    return (update(events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        // Value(null) is required: absent columns are skipped on update.
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> hardDeleteEventWithChildren(int id) async {
    await transaction(() async {
      // Child tables first: event_tags references events by FK.
      await (delete(eventTags)..where((t) => t.eventId.equals(id))).go();
      await (delete(
        attachments,
      )..where((t) => t.parentType.equals('event') & t.parentId.equals(id)))
          .go();
      await (delete(
        reminders,
      )..where((t) => t.parentType.equals('event') & t.parentId.equals(id)))
          .go();
      await (delete(events)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> emptyEventTrash() async {
    final deleted =
        await (select(events)..where((t) => t.deletedAt.isNotNull())).get();
    final ids = deleted.map((e) => e.id).toList();
    if (ids.isEmpty) return;
    await transaction(() async {
      await (delete(eventTags)..where((t) => t.eventId.isIn(ids))).go();
      await (delete(
        attachments,
      )..where((t) => t.parentType.equals('event') & t.parentId.isIn(ids)))
          .go();
      await (delete(
        reminders,
      )..where((t) => t.parentType.equals('event') & t.parentId.isIn(ids)))
          .go();
      await (delete(events)..where((t) => t.id.isIn(ids))).go();
    });
  }
}
