import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'calendar_todo.db'));
    return NativeDatabase.createInBackground(file);
  });
}
