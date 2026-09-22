import 'package:drift/drift.dart';

import 'tables/calendars_table.dart';
import 'tables/events_table.dart';
import 'tables/todos_table.dart';
import 'tables/tags_table.dart';
import 'tables/event_tags_table.dart';
import 'tables/todo_tags_table.dart';
import 'tables/attachments_table.dart';
import 'tables/reminders_table.dart';

import 'daos/calendars_dao.dart';
import 'daos/events_dao.dart';
import 'daos/todos_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Calendars,
    Events,
    Todos,
    Tags,
    EventTags,
    TodoTags,
    Attachments,
    Reminders,
  ],
  daos: [CalendarsDao, EventsDao, TodosDao],
)
class AppDatabase extends _$AppDatabase {
  /// Creates a database with a given [executor]. Used by:
  ///   - Flutter app via [openFlutterDatabase] from `connect_flutter.dart`
  ///   - CLI via [AppDatabase.forFile] from `app_database_file.dart`
  ///   - Tests via [AppDatabase.forTesting]
  AppDatabase(super.executor);

  AppDatabase.forExecutor(super.executor);

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Seed a default local calendar so the app has one from the start
      await into(calendars).insert(
        CalendarsCompanion.insert(
          name: 'Personal',
          color: const Value('#2563EB'),
        ),
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // The former `from < 2` step (create accounts table + add
      // calendars.account_id) is intentionally gone: schema v8 removed both,
      // so recreating them mid-migration would only be dropped again below.
      if (from < 3) {
        await m.addColumn(todos, todos.deletedAt);
      }
      if (from < 4) {
        await m.addColumn(todos, todos.sortOrder);
      }
      if (from < 5) {
        await m.deleteTable('sync_queue');
      }
      if (from < 6) {
        await m.addColumn(events, events.deletedAt);
      }
      if (from < 7) {
        await m.addColumn(todos, todos.parentId);
      }
      if (from < 8) {
        // v8: drop the CalDAV sync columns and the accounts table.
        // dropColumn takes raw SQL names (no camelCase→snake_case conversion).
        // account_id only exists on installs that reached v2+, so guard its
        // drop: a v1 database would otherwise fail with "no such column".
        if (from >= 2) {
          await m.dropColumn(calendars, 'account_id');
        }
        await m.dropColumn(calendars, 'caldav_href');
        await m.dropColumn(calendars, 'sync_token');
        await m.dropColumn(calendars, 'etag');
        await m.dropColumn(events, 'uid');
        await m.dropColumn(events, 'etag');
        await m.dropColumn(events, 'is_dirty');
        await m.dropColumn(todos, 'uid');
        await m.dropColumn(todos, 'etag');
        await m.dropColumn(todos, 'is_dirty');
        await m.deleteTable('accounts');
      }
      // Ensure default calendar exists for existing installs
      if (from >= 1) {
        final existing = await (select(calendars)).get();
        if (existing.isEmpty) {
          await into(calendars).insert(
            CalendarsCompanion.insert(
              name: 'Personal',
              color: const Value('#2563EB'),
            ),
          );
        }
      }
    },
  );

  // DAOs
  @override
  CalendarsDao get calendarsDao => CalendarsDao(this);
  @override
  EventsDao get eventsDao => EventsDao(this);
  @override
  TodosDao get todosDao => TodosDao(this);
}
