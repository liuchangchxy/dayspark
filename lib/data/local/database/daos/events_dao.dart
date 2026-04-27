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

  Future<void> upsert(Event entry) {
    return into(events).insertOnConflictUpdate(entry);
  }

  Future<List<Event>> searchEvents(String query) {
    final pattern = '%$query%';
    return (select(events)
          ..where((t) =>
              t.summary.like(pattern) | t.description.like(pattern))
          ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
          ..limit(50))
        .get();
  }
}
