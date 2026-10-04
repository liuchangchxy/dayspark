import 'package:drift/drift.dart';

import 'tables/calendars_table.dart';
import 'tables/events_table.dart';
import 'tables/todos_table.dart';
import 'tables/tags_table.dart';
import 'tables/event_tags_table.dart';
import 'tables/todo_tags_table.dart';
import 'tables/attachments_table.dart';
import 'tables/reminders_table.dart';
import 'tables/sync_outbox_table.dart';
import 'tables/task_allocations_table.dart';

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
    SyncOutbox,
    TaskAllocations,
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
  int get schemaVersion => 12;

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
      if (from < 9) {
        // v9: sync outbox + per-record sync identity/rev. Additive only —
        // existing rows keep their data; sync_id stays NULL until the row
        // is first enqueued (NULL means "never pushed").
        await m.addColumn(events, events.syncId);
        await m.addColumn(events, events.serverRev);
        await m.addColumn(todos, todos.syncId);
        await m.addColumn(todos, todos.serverRev);
        await m.createTable(syncOutbox);
      }
      if (from < 10) {
        await m.createTable(taskAllocations);
        await m.createIndex(taskAllocationsTodoId);
        await m.createIndex(taskAllocationsTimeRange);
      }
      if (from < 11) {
        await customStatement('DROP INDEX IF EXISTS task_allocations_todo_id');
        await customStatement(
          'DROP INDEX IF EXISTS task_allocations_time_range',
        );
        await customStatement(
          'ALTER TABLE task_allocations RENAME TO task_allocations_v10',
        );
        await customStatement('''
          CREATE TABLE IF NOT EXISTS "task_allocations" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "todo_id" INTEGER NULL REFERENCES todos (id) ON DELETE CASCADE,
            "todo_sync_id" TEXT NULL,
            "occurrence_id" TEXT NULL,
            "start_at" INTEGER NOT NULL,
            "end_at" INTEGER NOT NULL,
            "state" TEXT NOT NULL DEFAULT 'active',
            "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
            "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
            "sync_id" TEXT NULL,
            "server_rev" INTEGER NOT NULL DEFAULT 0
          );
        ''');
        await customStatement('''
          INSERT INTO task_allocations (
            id, todo_id, start_at, end_at, state, created_at, updated_at
          )
          SELECT id, todo_id, start_at, end_at, state, created_at, updated_at
          FROM task_allocations_v10
        ''');
        await customStatement('DROP TABLE task_allocations_v10');
        await customStatement(
          'CREATE INDEX task_allocations_todo_id ON task_allocations (todo_id)',
        );
        await customStatement(
          'CREATE INDEX task_allocations_todo_sync_id ON task_allocations (todo_sync_id)',
        );
        await customStatement(
          'CREATE INDEX task_allocations_sync_id ON task_allocations (sync_id)',
        );
        await customStatement(
          'CREATE INDEX task_allocations_time_range ON task_allocations (start_at, end_at)',
        );
      }
      if (from < 12) {
        await m.addColumn(todos, todos.recurrenceAnchorSource);
        await m.addColumn(todos, todos.recurrenceValueType);
        await m.addColumn(todos, todos.recurrenceAnchorValue);
        await m.addColumn(todos, todos.recurrenceTimeZone);
        await m.addColumn(todos, todos.recurrenceRule);
        await m.addColumn(todos, todos.recurrenceLegacyState);
        await m.addColumn(todos, todos.recurrenceRevision);
        await customStatement('''
          UPDATE todos
          SET recurrence_legacy_state = 'unknownLegacy', recurrence_revision = 0
          WHERE rrule IS NOT NULL
        ''');
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
