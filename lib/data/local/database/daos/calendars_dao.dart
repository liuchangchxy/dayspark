import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/calendars_table.dart';

part 'calendars_dao.g.dart';

@DriftAccessor(tables: [Calendars])
class CalendarsDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarsDaoMixin {
  CalendarsDao(super.db);

  Stream<List<Calendar>> watchAll() {
    return (select(calendars)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<void> upsert(Calendar entry) {
    return into(calendars).insertOnConflictUpdate(entry);
  }
}
