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
import 'package:drift/drift.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/data/local/database/app_database_file.dart';

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

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'help') {
    printUsage();
    return;
  }

  final dbPath = _getDbPath();
  final dir = Directory(p.dirname(dbPath));
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final appDb = openDatabaseFile(dbPath);
  try {
    final cmd = args.first;
    final rest = args.skip(1).toList();
    switch (cmd) {
      case 'todo':   await handleTodo(appDb, rest);
      case 'event':  await handleEvent(appDb, rest);
      case 'search': await handleSearch(appDb, rest);
      default:       stderr.writeln('Unknown: $cmd'); printUsage(); exitCode = 1;
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  } finally {
    await appDb.close();
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

Future<int> _getCalendarId(AppDatabase appDb) async {
  final cals = await appDb.select(appDb.calendars).get();
  if (cals.isEmpty) {
    stderr.writeln('No calendar found. Run the GUI app first to create one.');
    exit(1);
  }
  return cals.first.id;
}

// ──── Todo commands ──────────────────────────────────────────────

Future<void> handleTodo(AppDatabase appDb, List<String> args) async {
  if (args.isEmpty) { stderr.writeln('Subcommands: add, list, complete, delete'); exitCode = 1; return; }
  switch (args[0]) {
    case 'add':      await todoAdd(appDb, args.skip(1).toList());
    case 'list':     await todoList(appDb, args.skip(1).toList());
    case 'complete': await todoComplete(appDb, args.skip(1).toList());
    case 'delete':   await todoDelete(appDb, args.skip(1).toList());
    default:         stderr.writeln('Unknown: todo ${args[0]}'); exitCode = 1;
  }
}

Future<void> todoAdd(AppDatabase appDb, List<String> args) async {
  if (args.isEmpty || args.first.startsWith('--')) {
    stderr.writeln('Usage: dayspark todo add <summary> [options]'); exitCode = 1; return;
  }
  final summary = args.first;
  final flags = parseFlags(args.skip(1).toList());
  final calId = await _getCalendarId(appDb);
  final now = DateTime.now().toUtc();
  final uid = 'cli-${now.millisecondsSinceEpoch}';

  DateTime? dueDate;
  final dueStr = flags['due'];
  if (dueStr != null && dueStr.isNotEmpty) {
    dueDate = DateTime.tryParse(dueStr);
  }

  final priority = int.tryParse(flags['priority'] ?? '') ?? 5;
  final desc = flags['desc'] ?? '';

  await appDb.into(appDb.todos).insert(TodosCompanion(
    calendarId: Value(calId),
    uid: Value(uid),
    summary: Value(summary),
    dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
    priority: Value(priority),
    description: desc.isNotEmpty ? Value(desc) : const Value.absent(),
    isDirty: const Value(true),
  ));
  print('Todo created: $summary');
}

Future<void> todoList(AppDatabase appDb, List<String> args) async {
  final flags = parseFlags(args);
  final showAll = flags.containsKey('all');
  final dateFilter = flags['date'];

  List<Todo> rows;
  if (showAll) {
    rows = await (appDb.select(appDb.todos)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.priority),
        (t) => OrderingTerm.asc(t.dueDate),
      ])
    ).get();
  } else if (dateFilter != null) {
    final d = DateTime.tryParse(dateFilter);
    if (d == null) { stderr.writeln('Invalid --date format.'); exitCode = 1; return; }
    final start = DateTime(d.year, d.month, d.day);
    final end = start.add(const Duration(days: 1));
    rows = await (appDb.select(appDb.todos)
      ..where((t) =>
        t.deletedAt.isNull() &
        t.dueDate.isBiggerOrEqualValue(start) &
        t.dueDate.isSmallerThanValue(end))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])
    ).get();
  } else {
    rows = await (appDb.select(appDb.todos)
      ..where((t) =>
        t.deletedAt.isNull() &
        t.status.isNotIn(const ['COMPLETED', 'CANCELLED']))
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.priority),
        (t) => OrderingTerm.asc(t.dueDate),
      ])
    ).get();
  }

  if (rows.isEmpty) { print('No todos found.'); return; }
  for (final r in rows) {
    final done = r.status == 'COMPLETED';
    final prefix = done ? '✓' : '○';
    final due = r.dueDate != null ? ' [due: ${r.dueDate.toString().substring(0, 10)}]' : '';
    final prioStr = r.priority > 0 ? ' [p${r.priority}]' : '';
    print('  $prefix #${r.id} ${r.summary}$due$prioStr');
  }
  print('\n${rows.length} todo(s)');
}

Future<void> todoComplete(AppDatabase appDb, List<String> args) async {
  if (args.isEmpty) { stderr.writeln('Usage: dayspark todo complete <id>'); exitCode = 1; return; }
  final id = int.tryParse(args.first);
  if (id == null) { stderr.writeln('Invalid id: ${args.first}'); exitCode = 1; return; }
  await appDb.todosDao.markComplete(id);
  print('Todo #$id completed.');
}

Future<void> todoDelete(AppDatabase appDb, List<String> args) async {
  if (args.isEmpty) { stderr.writeln('Usage: dayspark todo delete <id>'); exitCode = 1; return; }
  final id = int.tryParse(args.first);
  if (id == null) { stderr.writeln('Invalid id: ${args.first}'); exitCode = 1; return; }
  final now = DateTime.now().toUtc();
  await (appDb.update(appDb.todos)..where((t) => t.id.equals(id))).write(
    TodosCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ),
  );
  print('Todo #$id deleted.');
}

// ──── Event commands ─────────────────────────────────────────────

Future<void> handleEvent(AppDatabase appDb, List<String> args) async {
  if (args.isEmpty) { stderr.writeln('Subcommands: add, list'); exitCode = 1; return; }
  switch (args[0]) {
    case 'add':  await eventAdd(appDb, args.skip(1).toList());
    case 'list': await eventList(appDb, args.skip(1).toList());
    default:     stderr.writeln('Unknown: event ${args[0]}'); exitCode = 1;
  }
}

Future<void> eventAdd(AppDatabase appDb, List<String> args) async {
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

  final end = () {
    final endStr = flags['end'];
    if (endStr != null) {
      return DateTime.tryParse(endStr) ?? start.add(const Duration(hours: 1));
    }
    return start.add(const Duration(hours: 1));
  }();

  final isAllDay = flags.containsKey('all-day');
  final desc = flags['desc'] ?? '';
  final loc = flags['loc'] ?? '';
  final calId = await _getCalendarId(appDb);
  final now = DateTime.now().toUtc();
  final uid = 'cli-${now.millisecondsSinceEpoch}';
  final startDt = isAllDay ? DateTime(start.year, start.month, start.day) : start;
  final endDt = isAllDay ? DateTime(start.year, start.month, start.day).add(const Duration(days: 1)) : end;

  await appDb.into(appDb.events).insert(EventsCompanion(
    calendarId: Value(calId),
    uid: Value(uid),
    summary: Value(summary),
    startDt: Value(startDt),
    endDt: Value(endDt),
    isAllDay: Value(isAllDay),
    description: desc.isNotEmpty ? Value(desc) : const Value.absent(),
    location: loc.isNotEmpty ? Value(loc) : const Value.absent(),
    isDirty: const Value(true),
  ));
  print('Event created: $summary');
}

Future<void> eventList(AppDatabase appDb, List<String> args) async {
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

  final rows = await (appDb.select(appDb.events)
    ..where((t) =>
      t.deletedAt.isNull() &
      t.startDt.isSmallerThanValue(end) &
      t.endDt.isBiggerThanValue(start))
    ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
  ).get();

  if (rows.isEmpty) { print('No events found.'); return; }
  for (final r in rows) {
    final time = r.isAllDay
        ? '[All day]'
        : '${r.startDt.toString().substring(11, 16)}-${r.endDt.toString().substring(11, 16)}';
    final locStr = r.location != null ? ' @ ${r.location}' : '';
    print('  #${r.id} $time ${r.summary}$locStr');
  }
  print('\n${rows.length} event(s)');
}

// ──── Search ──────────────────────────────────────────────────────

Future<void> handleSearch(AppDatabase appDb, List<String> args) async {
  if (args.isEmpty) { stderr.writeln('Usage: dayspark search <query>'); exitCode = 1; return; }
  final query = args.join(' ');

  final events = await appDb.eventsDao.searchEvents(query);
  final todos = await appDb.todosDao.searchTodos(query);

  if (events.isEmpty && todos.isEmpty) { print('No results.'); return; }
  if (events.isNotEmpty) {
    print('Events:');
    for (final r in events) {
      final date = r.startDt.toString().substring(0, 10);
      print('  #${r.id} ${r.summary} ($date)');
    }
  }
  if (todos.isNotEmpty) {
    print('Todos:');
    for (final r in todos) {
      final due = r.dueDate != null ? ' (due: ${r.dueDate.toString().substring(0, 10)})' : '';
      print('  #${r.id} ${r.summary}$due');
    }
  }
  print('\n${events.length + todos.length} result(s)');
}
