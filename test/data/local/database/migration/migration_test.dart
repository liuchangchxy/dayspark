import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:dayspark/data/local/database/app_database.dart';

/// Helper: converts a [DateTime] to Unix seconds (Drift's default storage).
int _ts(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

/// Creates a temporary file with a v1-schema SQLite database seeded with
/// realistic data, then returns the [File]. The caller must delete the file.
File _createV1Database() {
  final file = File(
    '${Directory.systemTemp.path}/test_migrate_${DateTime.now().microsecondsSinceEpoch}.db',
  );
  final raw = sqlite3.open(file.path);

  // v1 schema: 8 tables (accounts did NOT exist, sync_queue did)

  // Calendars — NO account_id
  raw.execute('''
    CREATE TABLE calendars (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      caldav_href TEXT NOT NULL,
      name TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT '#2563EB',
      timezone TEXT NOT NULL DEFAULT 'UTC',
      sync_token TEXT,
      etag TEXT,
      last_synced_at INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // Events — NO deleted_at
  raw.execute('''
    CREATE TABLE events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      calendar_id INTEGER NOT NULL REFERENCES calendars(id),
      uid TEXT NOT NULL,
      summary TEXT NOT NULL,
      start_dt INTEGER NOT NULL,
      end_dt INTEGER NOT NULL,
      is_all_day INTEGER NOT NULL DEFAULT 0,
      description TEXT,
      location TEXT,
      rrule TEXT,
      etag TEXT,
      is_dirty INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
    )
  ''');

  // Todos — NO deleted_at, sort_order, parent_id
  raw.execute('''
    CREATE TABLE todos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      calendar_id INTEGER NOT NULL REFERENCES calendars(id),
      uid TEXT NOT NULL,
      summary TEXT NOT NULL,
      due_date INTEGER,
      start_date INTEGER,
      priority INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'NEEDS-ACTION',
      description TEXT,
      rrule TEXT,
      completed_at INTEGER,
      percent_complete INTEGER NOT NULL DEFAULT 0,
      etag TEXT,
      is_dirty INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
    )
  ''');

  // Tags
  raw.execute('''
    CREATE TABLE tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT '#6B7280'
    )
  ''');

  // EventTags
  raw.execute('''
    CREATE TABLE event_tags (
      event_id INTEGER NOT NULL REFERENCES events(id),
      tag_id INTEGER NOT NULL REFERENCES tags(id),
      PRIMARY KEY (event_id, tag_id)
    )
  ''');

  // TodoTags
  raw.execute('''
    CREATE TABLE todo_tags (
      todo_id INTEGER NOT NULL REFERENCES todos(id),
      tag_id INTEGER NOT NULL REFERENCES tags(id),
      PRIMARY KEY (todo_id, tag_id)
    )
  ''');

  // Attachments
  raw.execute('''
    CREATE TABLE attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_type TEXT NOT NULL,
      parent_id INTEGER NOT NULL,
      file_path TEXT NOT NULL,
      file_name TEXT NOT NULL,
      file_size INTEGER NOT NULL DEFAULT 0,
      mime_type TEXT,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
    )
  ''');

  // Reminders
  raw.execute('''
    CREATE TABLE reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_type TEXT NOT NULL,
      parent_id INTEGER NOT NULL,
      trigger_time INTEGER NOT NULL,
      is_triggered INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // sync_queue (existed at v1, dropped in v5)
  raw.execute('''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      action TEXT NOT NULL,
      table_name TEXT NOT NULL,
      row_id INTEGER NOT NULL,
      payload TEXT,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
    )
  ''');

  // Seed realistic data using Unix seconds (Drift default storage)
  final now = _ts(DateTime.now());
  final eventStart = _ts(DateTime(2026, 5, 1, 10));
  final eventEnd = _ts(DateTime(2026, 5, 1, 11));
  final reminderTime = _ts(DateTime(2026, 5, 1, 9, 45));

  raw.execute(
    "INSERT INTO calendars (caldav_href, name) VALUES ('local://default', 'Personal')",
  );

  raw.execute(
    'INSERT INTO events (calendar_id, uid, summary, start_dt, end_dt, created_at, updated_at) '
    "VALUES (1, 'evt-001', 'Meeting', $eventStart, $eventEnd, $now, $now)",
  );

  raw.execute(
    'INSERT INTO todos (calendar_id, uid, summary, created_at, updated_at) '
    "VALUES (1, 'td-001', 'Buy milk', $now, $now)",
  );

  raw.execute(
    "INSERT INTO tags (name) VALUES ('urgent')",
  );

  raw.execute('INSERT INTO event_tags (event_id, tag_id) VALUES (1, 1)');
  raw.execute('INSERT INTO todo_tags (todo_id, tag_id) VALUES (1, 1)');

  raw.execute(
    'INSERT INTO reminders (parent_type, parent_id, trigger_time) '
    "VALUES ('event', 1, $reminderTime)",
  );

  raw.execute(
    'INSERT INTO attachments (parent_type, parent_id, file_path, file_name, created_at) '
    "VALUES ('todo', 1, '/tmp/receipt.pdf', 'receipt.pdf', $now)",
  );

  raw.execute(
    'INSERT INTO sync_queue (action, table_name, row_id, payload, created_at) '
    "VALUES ('create', 'todos', 1, '{\"uid\":\"td-001\"}', $now)",
  );

  // Set drift version to 1
  raw.execute('PRAGMA user_version = 1');
  raw.dispose();

  return file;
}

/// Opens [file] with Drift at the current schemaVersion and verifies data.
Future<void> _runAndVerify(File file) async {
  final db = AppDatabase.forExecutor(NativeDatabase(file));

  try {
    // All 8 original tables: data survived
    expect((await (db.select(db.calendars)).get()).length, 1);
    expect((await (db.select(db.events)).get()).length, 1);
    expect((await (db.select(db.todos)).get()).length, 1);
    expect((await (db.select(db.tags)).get()).length, 1);
    expect((await (db.select(db.eventTags)).get()).length, 1);
    expect((await (db.select(db.todoTags)).get()).length, 1);
    expect((await (db.select(db.reminders)).get()).length, 1);
    expect((await (db.select(db.attachments)).get()).length, 1);

    // sync_queue dropped in v5 migration (no DAO, can't query — that's ok)

    // New columns from v2–v7 migrations exist with correct defaults
    final calendars = await (db.select(db.calendars)).get();
    expect(calendars.first.accountId, isNull); // v2: add account_id

    final todos = await (db.select(db.todos)).get();
    expect(todos.first.deletedAt, isNull);  // v3: add deleted_at
    expect(todos.first.sortOrder, 0);       // v4: add sort_order
    expect(todos.first.parentId, isNull);   // v7: add parent_id

    final events = await (db.select(db.events)).get();
    expect(events.first.deletedAt, isNull); // v6: add deleted_at

    // v5: sync_queue dropped — not queryable, no crash = success

    // Original data values intact
    expect(calendars.first.caldavHref, 'local://default');
    expect(events.first.uid, 'evt-001');
    expect(todos.first.uid, 'td-001');
    expect(calendars.first.name, 'Personal');

    // New rows work with current schema
    final newCalId = await db.into(db.calendars).insert(
      CalendarsCompanion.insert(caldavHref: '/cal/work/', name: 'Work'),
    );
    expect(newCalId, greaterThan(0));

    await db.into(db.events).insert(
      EventsCompanion.insert(
        calendarId: newCalId,
        uid: 'evt-new',
        summary: 'New event',
        startDt: DateTime(2026, 6, 1),
        endDt: DateTime(2026, 6, 1),
      ),
    );

    await db.into(db.todos).insert(
      TodosCompanion.insert(calendarId: newCalId, uid: 'td-new', summary: 'New todo'),
    );
  } finally {
    await db.close();
  }
}

void main() {
  group('Database migration', () {
    test('v1 → v7 full migration preserves data integrity', () async {
      final file = _createV1Database();
      try {
        await _runAndVerify(file);
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('fresh database at v7 initializes correctly', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        expect(db.schemaVersion, 7);
        expect(db.migration.onCreate, isNotNull);
        expect(db.migration.onUpgrade, isNotNull);

        final calendars = await (db.select(db.calendars)).get();
        expect(calendars.length, 1);
        expect(calendars.first.caldavHref, 'local://default');
      } finally {
        await db.close();
      }
    });

    test('schema snapshot exists for v7', () async {
      final schemaFile = File('drift_schemas/app_database/drift_schema_v7.json');
      expect(await schemaFile.exists(), true,
          reason: 'Run `dart run drift_dev make-migrations` to generate');
    });
  });
}
