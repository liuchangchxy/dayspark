import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/calendars_table.dart';

part 'calendars_dao.g.dart';

@DriftAccessor(tables: [Calendars])
class CalendarsDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarsDaoMixin {
  CalendarsDao(super.db);

  Stream<List<Calendar>> watchAll() {
    return (select(
      calendars,
    )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();
  }

  Future<void> upsert(Calendar entry) {
    return into(calendars).insertOnConflictUpdate(entry);
  }

  Future<int> insertCalendar(CalendarsCompanion entry) {
    return into(calendars).insert(entry);
  }

  Future<bool> updateCalendar(int id, CalendarsCompanion entry) async {
    final rows = await (update(calendars)..where((t) => t.id.equals(id))).write(entry);
    return rows > 0;
  }

  Future<int> deleteCalendar(int id) async {
    return (delete(calendars)..where((t) => t.id.equals(id))).go();
  }
}
