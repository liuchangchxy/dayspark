import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );

  // DAOs
  CalendarsDao get calendarsDao => CalendarsDao(this);
  EventsDao get eventsDao => EventsDao(this);
  TodosDao get todosDao => TodosDao(this);

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
