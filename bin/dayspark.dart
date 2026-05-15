// ignore_for_file: avoid_print

// DaySpark CLI — headless terminal interface for DaySpark.
//
// Build standalone:  dart compile exe bin/dayspark.dart -o dayspark-cli
// Then use:  ./dayspark-cli todo add "Buy milk"
// Or symlink:  ln -s $(pwd)/dayspark-cli /usr/local/bin/dayspark
//
// Examples:
//   dayspark todo add "Buy milk" --due 2026-05-20 --priority 1
//   dayspark todo list
//   dayspark todo complete 42
//   dayspark todo delete 42
//   dayspark event add "Team standup" --start "2026-05-15 09:00" --end "2026-05-15 09:30"
//   dayspark event list --date 2026-05-15
//   dayspark search meeting

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

Database _openDb([String? overridePath]) {
  final path = overridePath ?? _getDbPath();
  final dir = Directory(p.dirname(path));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final db = sqlite3.open(path);
  _initSchema(db);
  return db;
}

/// Creates tables if they don't exist (matches the Flutter app's Drift schema).
void _initSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS calendars (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      caldav_href TEXT NOT NULL,
      name TEXT NOT NULL,
      color TEXT,
      account_id INTEGER,
      ctag TEXT,
      sync_token TEXT
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      calendar_id INTEGER NOT NULL REFERENCES calendars(id),
      uid TEXT NOT NULL,
      summary TEXT NOT NULL,
      start_dt TEXT NOT NULL,
      end_dt TEXT NOT NULL,
      is_all_day INTEGER NOT NULL DEFAULT 0,
      description TEXT,
      location TEXT,
      rrule TEXT,
      rid TEXT,
      etag TEXT,
      is_dirty INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS todos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      calendar_id INTEGER NOT NULL REFERENCES calendars(id),
      uid TEXT NOT NULL,
      summary TEXT NOT NULL,
      due_date TEXT,
      start_date TEXT,
      priority INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'NEEDS-ACTION',
      description TEXT,
      rrule TEXT,
      completed_at TEXT,
      percent_complete INTEGER NOT NULL DEFAULT 0,
      etag TEXT,
      is_dirty INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      parent_id INTEGER
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_type TEXT NOT NULL,
      parent_id INTEGER NOT NULL,
      trigger_time TEXT NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color TEXT NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS todo_tags (
      todo_id INTEGER NOT NULL REFERENCES todos(id),
      tag_id INTEGER NOT NULL REFERENCES tags(id),
      PRIMARY KEY (todo_id, tag_id)
    )
  ''');

  // Seed default calendar if empty
  final cals = db.select('SELECT COUNT(*) AS cnt FROM calendars');
  if (cals.first['cnt'] == 0) {
    db.execute(
      "INSERT INTO calendars (caldav_href, name, color) VALUES ('local://default', 'Personal', '#2563EB')",
    );
  }
}

String _getDbPath() {
  final home = Platform.environment['HOME'] ?? '/tmp';
  if (Platform.isLinux) {
    final data = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    return p.join(data, 'com.dayspark.app', 'calendar_todo.db');
  }
  if (Platform.isMacOS) {
    return p.join(home, 'Library', 'Application Support', 'com.dayspark.app', 'calendar_todo.db');
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? '$home\\AppData';
    return p.join(appData, 'com.dayspark.app', 'calendar_todo.db');
  }
  return p.join(home, '.dayspark', 'calendar_todo.db');
}

void main(List<String> args) async {
  if (args.isEmpty || args.first == 'help') {
    printUsage();
    return;
  }

  final db = _openDb();
  try {
    final cmd = args.first;
    final rest = args.skip(1).toList();
    switch (cmd) {
      case 'todo':   handleTodo(db, rest);
      case 'event':  handleEvent(db, rest);
      case 'search': handleSearch(db, rest);
      default:       stderr.writeln('Unknown: $cmd'); printUsage(); exitCode = 1;
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  } finally {
    db.dispose();
  }
}

void printUsage() {
  print('''
DaySpark CLI — manage your calendar and todos from the terminal.

Usage:
  dayspark todo add <summary> [--due yyyy-MM-dd] [--priority 1|5|9] [--desc <text>]
  dayspark todo list [--all] [--date yyyy-MM-dd]
  dayspark todo complete <id>
  dayspark todo delete <id>

  dayspark event add <summary> --start "yyyy-MM-dd HH:mm" [--end "..." --desc <text> --loc <text> --all-day]
  dayspark event list [--date yyyy-MM-dd]

  dayspark search <query>
  dayspark help
''');
}

// ──── Todo commands ──────────────────────────────────────────────

void handleTodo(Database db, List<String> args) {
  if (args.isEmpty) { stderr.writeln('Subcommands: add, list, complete, delete'); exitCode = 1; return; }
  switch (args[0]) {
    case 'add':      todoAdd(db, args.skip(1).toList());
    case 'list':     todoList(db, args.skip(1).toList());
    case 'complete': todoComplete(db, args.skip(1).toList());
    case 'delete':   todoDelete(db, args.skip(1).toList());
    default:         stderr.writeln('Unknown: todo ${args[0]}'); exitCode = 1;
  }
}

int _getCalendarId(Database db) {
  final rows = db.select('SELECT id FROM calendars LIMIT 1');
  if (rows.isEmpty) {
    stderr.writeln('No calendar found. Run the GUI app first to create one.');
    exit(1);
  }
  return rows.first['id'] as int;
}

void todoAdd(Database db, List<String> args) {
  if (args.isEmpty || args.first.startsWith('--')) {
    stderr.writeln('Usage: dayspark todo add <summary> [options]'); exitCode = 1; return;
  }
  final summary = args.first;
  final flags = parseFlags(args.skip(1).toList());
  final calId = _getCalendarId(db);
  final now = DateTime.now().toUtc().toIso8601String();
  final uid = 'cli-${DateTime.now().millisecondsSinceEpoch}';
  final dueDate = flags['due'] ?? '';
  final priority = int.tryParse(flags['priority'] ?? '') ?? 5;
  final desc = flags['desc'] ?? '';

  db.execute(
    'INSERT INTO todos (calendar_id, uid, summary, priority, due_date, description, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [calId, uid, summary, priority, dueDate.isEmpty ? null : dueDate, desc.isEmpty ? null : desc, now, now],
  );
  final id = db.lastInsertRowId;
  print('Todo created (id: $id): $summary');
}

void todoList(Database db, List<String> args) {
  final flags = parseFlags(args);
  final showAll = flags.containsKey('all');
  final dateFilter = flags['date'];

  List<Row> rows;
  if (showAll) {
    rows = db.select('SELECT * FROM todos WHERE deleted_at IS NULL ORDER BY sort_order, priority, due_date');
  } else if (dateFilter != null) {
    rows = db.select(
      'SELECT * FROM todos WHERE deleted_at IS NULL AND due_date >= ? AND due_date < ? ORDER BY sort_order',
      [dateFilter, (() {
        final d = DateTime.tryParse(dateFilter);
        if (d == null) return '';
        return DateTime(d.year, d.month, d.day + 1).toIso8601String().substring(0, 10);
      })()],
    );
  } else {
    rows = db.select(
      "SELECT * FROM todos WHERE deleted_at IS NULL AND status NOT IN ('COMPLETED','CANCELLED') ORDER BY sort_order, priority, due_date",
    );
  }

  if (rows.isEmpty) { print('No todos found.'); return; }
  for (final r in rows) {
    final done = r['status'] == 'COMPLETED';
    final prefix = done ? '✓' : '○';
    final due = r['due_date'] != null ? ' [due: ${(r['due_date'] as String).substring(0, 10)}]' : '';
    final p = (r['priority'] as int?) ?? 0;
    final prioStr = p > 0 ? ' [p$p]' : '';
    print('  $prefix #${r['id']} ${r['summary']}$due$prioStr');
  }
  print('\n${rows.length} todo(s)');
}

void todoComplete(Database db, List<String> args) {
  if (args.isEmpty) { stderr.writeln('Usage: dayspark todo complete <id>'); exitCode = 1; return; }
  final id = int.tryParse(args.first);
  if (id == null) { stderr.writeln('Invalid id: ${args.first}'); exitCode = 1; return; }
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute('UPDATE todos SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?', ['COMPLETED', now, now, id]);
  print('Todo #$id completed.');
}

void todoDelete(Database db, List<String> args) {
  if (args.isEmpty) { stderr.writeln('Usage: dayspark todo delete <id>'); exitCode = 1; return; }
  final id = int.tryParse(args.first);
  if (id == null) { stderr.writeln('Invalid id: ${args.first}'); exitCode = 1; return; }
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute('UPDATE todos SET deleted_at = ?, updated_at = ? WHERE id = ?', [now, now, id]);
  print('Todo #$id deleted.');
}

// ──── Event commands ─────────────────────────────────────────────

void handleEvent(Database db, List<String> args) {
  if (args.isEmpty) { stderr.writeln('Subcommands: add, list'); exitCode = 1; return; }
  switch (args[0]) {
    case 'add':  eventAdd(db, args.skip(1).toList());
    case 'list': eventList(db, args.skip(1).toList());
    default:     stderr.writeln('Unknown: event ${args[0]}'); exitCode = 1;
  }
}

void eventAdd(Database db, List<String> args) {
  if (args.isEmpty || args.first.startsWith('--')) {
    stderr.writeln('Usage: dayspark event add <summary> --start "yyyy-MM-dd HH:mm" [options]');
    exitCode = 1; return;
  }
  final summary = args.first;
  final flags = parseFlags(args.skip(1).toList());
  final startStr = flags['start'];
  if (startStr == null) { stderr.writeln('--start is required.'); exitCode = 1; return; }
  final start = DateTime.tryParse(startStr);
  if (start == null) { stderr.writeln('Invalid --start format.'); exitCode = 1; return; }

  final endStr = flags['end'];
  final end = endStr != null ? (DateTime.tryParse(endStr) ?? start.add(const Duration(hours: 1))) : start.add(const Duration(hours: 1));
  final isAllDay = flags.containsKey('all-day');
  final desc = flags['desc'] ?? '';
  final loc = flags['loc'] ?? '';

  final calId = _getCalendarId(db);
  final now = DateTime.now().toUtc().toIso8601String();
  final uid = 'cli-${DateTime.now().millisecondsSinceEpoch}';
  final startDt = isAllDay ? DateTime(start.year, start.month, start.day).toIso8601String() : start.toIso8601String();
  final endDt = isAllDay ? DateTime(start.year, start.month, start.day).add(const Duration(days: 1)).toIso8601String() : end.toIso8601String();

  db.execute(
    'INSERT INTO events (calendar_id, uid, summary, start_dt, end_dt, is_all_day, description, location, is_dirty, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
    [calId, uid, summary, startDt, endDt, isAllDay ? 1 : 0, desc.isEmpty ? null : desc, loc.isEmpty ? null : loc, now, now],
  );
  final id = db.lastInsertRowId;
  print('Event created (id: $id): $summary');
}

void eventList(Database db, List<String> args) {
  final flags = parseFlags(args);
  final now = DateTime.now();
  DateTime start, end;
  if (flags['date'] != null) {
    final d = DateTime.tryParse(flags['date']!);
    if (d == null) { stderr.writeln('Invalid --date'); exitCode = 1; return; }
    start = DateTime(d.year, d.month, d.day);
    end = start.add(const Duration(days: 1));
  } else {
    start = DateTime(now.year, now.month, now.day);
    end = start.add(const Duration(days: 1));
  }

  final rows = db.select(
    'SELECT * FROM events WHERE deleted_at IS NULL AND start_dt < ? AND end_dt > ? ORDER BY start_dt',
    [end.toIso8601String(), start.toIso8601String()],
  );

  if (rows.isEmpty) { print('No events found.'); return; }
  for (final r in rows) {
    final allDay = (r['is_all_day'] as int?) == 1;
    final time = allDay ? '[All day]' : '${(r['start_dt'] as String).substring(11, 16)}-${(r['end_dt'] as String).substring(11, 16)}';
    final locStr = r['location'] != null ? ' @ ${r['location']}' : '';
    print('  #${r['id']} $time ${r['summary']}$locStr');
  }
  print('\n${rows.length} event(s)');
}

// ──── Search ──────────────────────────────────────────────────────

void handleSearch(Database db, List<String> args) {
  if (args.isEmpty) { stderr.writeln('Usage: dayspark search <query>'); exitCode = 1; return; }
  final query = '%${args.join(' ')}%';

  final events = db.select(
    'SELECT * FROM events WHERE deleted_at IS NULL AND (summary LIKE ?1 OR description LIKE ?1) ORDER BY start_dt LIMIT 20',
    [query],
  );
  final todos = db.select(
    'SELECT * FROM todos WHERE deleted_at IS NULL AND (summary LIKE ?1 OR description LIKE ?1) ORDER BY due_date LIMIT 20',
    [query],
  );

  if (events.isEmpty && todos.isEmpty) { print('No results.'); return; }
  if (events.isNotEmpty) {
    print('Events:');
    for (final r in events) {
      final date = (r['start_dt'] as String).substring(0, 10);
      print('  #${r['id']} ${r['summary']} ($date)');
    }
  }
  if (todos.isNotEmpty) {
    print('Todos:');
    for (final r in todos) {
      final due = r['due_date'] != null ? ' (due: ${(r['due_date'] as String).substring(0, 10)})' : '';
      print('  #${r['id']} ${r['summary']}$due');
    }
  }
  print('\n${events.length + todos.length} result(s)');
}

// ──── Helpers ─────────────────────────────────────────────────────

Map<String, String?> parseFlags(List<String> args) {
  final flags = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      final key = args[i].substring(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        flags[key] = args[i + 1];
        i++;
      } else {
        flags[key] = null;
      }
    }
  }
  return flags;
}
