import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/events_table.dart';

part 'events_dao.g.dart';

@DriftAccessor(tables: [Events])
class EventsDao extends DatabaseAccessor<AppDatabase>
    with _$EventsDaoMixin {
  EventsDao(super.db);

  Stream<List<Event>> watchByDateRange(DateTime start, DateTime end) {
    return (select(events)
          ..where((t) =>
              t.startDt.isBiggerOrEqualValue(start) &
              t.startDt.isSmallerOrEqualValue(end))
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)]))
        .watch();
  }

  Future<void> markDirty(int id) {
    return (update(events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        isDirty: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> upsert(Event entry) {
    return into(events).insertOnConflictUpdate(entry);
  }

  Stream<List<Event>> watchByCalendar(int calendarId) {
    return (select(events)..where((t) => t.calendarId.equals(calendarId)))
        .watch();
  }
}
