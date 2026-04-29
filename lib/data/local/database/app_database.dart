import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/accounts_table.dart';
import 'tables/calendars_table.dart';
import 'tables/events_table.dart';
import 'tables/todos_table.dart';
import 'tables/tags_table.dart';
import 'tables/event_tags_table.dart';
import 'tables/todo_tags_table.dart';
import 'tables/attachments_table.dart';
import 'tables/sync_queue_table.dart';
import 'tables/reminders_table.dart';

import 'daos/calendars_dao.dart';
import 'daos/events_dao.dart';
import 'daos/todos_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Calendars,
    Events,
    Todos,
    Tags,
    EventTags,
    TodoTags,
    Attachments,
    SyncQueue,
    Reminders,
  ],
  daos: [CalendarsDao, EventsDao, TodosDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Seed a default local calendar so the app works without CalDAV
      await into(calendars).insert(
        CalendarsCompanion.insert(
          caldavHref: 'local://default',
          name: 'Personal',
          color: const Value('#2563EB'),
        ),
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(accounts);
        await m.addColumn(calendars, calendars.accountId);
      }
      if (from < 3) {
        await m.addColumn(todos, todos.deletedAt);
      }
      // Ensure default calendar exists for existing installs
      if (from >= 1) {
        final existing = await (select(calendars)).get();
        if (existing.isEmpty) {
          await into(calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: 'local://default',
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
  late final calendarsDao = CalendarsDao(this);
  @override
  late final eventsDao = EventsDao(this);
  @override
  late final todosDao = TodosDao(this);

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'calendar_todo',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
