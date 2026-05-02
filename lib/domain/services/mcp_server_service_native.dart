import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:dayspark/data/local/database/app_database.dart';

class McpServerService {
  final AppDatabase _db;
  StreamableMcpServer? _server;

  McpServerService(this._db);

  bool get isRunning => _server != null;

  Future<void> start({String host = 'localhost', int port = 3000}) async {
    if (_server != null) return;

    _server = StreamableMcpServer(
      serverFactory: _createServer,
      host: host,
      port: port,
      path: '/mcp',
    );
    await _server!.start();
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }

  McpServer _createServer(String sessionId) {
    final server = McpServer(
      Implementation(name: 'dayspark', version: '0.15.0'),
      options: McpServerOptions(
        instructions: 'DaySpark calendar & todo MCP server. '
            'Use list_events/list_todos to read data, '
            'create_event/create_todo to add items, '
            'complete_todo to mark done, '
            'search to find events or todos by keyword.',
      ),
    );

    _registerTools(server);
    _registerResources(server);
    return server;
  }

  void _registerTools(McpServer server) {
    server.registerTool(
      'list_events',
      title: 'List Events',
      description: 'List calendar events in a date range',
      inputSchema: JsonObject(
        properties: {
          'start': JsonSchema.string(
            description: 'Start date (yyyy-MM-dd), defaults to today',
          ),
          'end': JsonSchema.string(
            description: 'End date (yyyy-MM-dd), defaults to 7 days from start',
          ),
          'limit': JsonSchema.integer(
            description: 'Max results (default 20)',
          ),
        },
      ),
      annotations: ToolAnnotations(readOnlyHint: true),
      callback: (args, _) async {
        final now = DateTime.now();
        final startDate = _parseDate(args['start'] as String?,
                year: now.year, month: now.month, day: now.day) ??
            DateTime(now.year, now.month, now.day);
        final endDate = _parseDate(args['end'] as String?) ??
            startDate.add(const Duration(days: 8));
        final limit = (args['limit'] as int?) ?? 20;

        final events = await (_db.select(_db.events)
              ..where((t) => t.deletedAt.isNull())
              ..where(
                (t) =>
                    t.startDt.isSmallerThanValue(endDate) &
                    t.endDt.isBiggerThanValue(startDate),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
              ..limit(limit))
            .get();

        return CallToolResult(
          content: [
            TextContent(
              text: JsonEncoder.withIndent('  ').convert(
                events
                    .map((e) => {
                          'id': e.id,
                          'summary': e.summary,
                          'start': e.startDt.toIso8601String(),
                          'end': e.endDt.toIso8601String(),
                          'isAllDay': e.isAllDay,
                          if (e.location != null) 'location': e.location,
                        })
                    .toList(),
              ),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'list_todos',
      title: 'List Todos',
      description: 'List pending todos',
      inputSchema: JsonObject(
        properties: {
          'status': JsonSchema.string(
            description:
                'Filter by status: NEEDS-ACTION, IN-PROCESS, COMPLETED, CANCELLED',
          ),
          'limit': JsonSchema.integer(description: 'Max results (default 20)'),
        },
      ),
      annotations: ToolAnnotations(readOnlyHint: true),
      callback: (args, _) async {
        final limit = (args['limit'] as int?) ?? 20;
        final statusFilter = args['status'] as String?;

        var query = _db.select(_db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)])
          ..limit(limit);

        if (statusFilter != null) {
          query = query..where((t) => t.status.equals(statusFilter));
        } else {
          query = query
            ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED']));
        }

        final todos = await query.get();

        return CallToolResult(
          content: [
            TextContent(
              text: JsonEncoder.withIndent('  ').convert(
                todos
                    .map((t) => {
                          'id': t.id,
                          'summary': t.summary,
                          'status': t.status,
                          if (t.dueDate != null)
                            'dueDate': t.dueDate!.toIso8601String(),
                          'priority': t.priority,
                        })
                    .toList(),
              ),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'create_event',
      title: 'Create Event',
      description: 'Create a new calendar event',
      inputSchema: JsonObject(
        properties: {
          'summary': JsonSchema.string(description: 'Event title'),
          'start': JsonSchema.string(
            description: 'Start time (ISO 8601 or yyyy-MM-dd HH:mm)',
          ),
          'end': JsonSchema.string(
            description:
                'End time (ISO 8601 or yyyy-MM-dd HH:mm). Defaults to 1 hour after start.',
          ),
          'isAllDay': JsonSchema.boolean(description: 'All-day event (default false)'),
          'description': JsonSchema.string(description: 'Event description'),
          'location': JsonSchema.string(description: 'Event location'),
        },
        required: ['summary', 'start'],
      ),
      annotations: ToolAnnotations(destructiveHint: false),
      callback: (args, _) async {
        final summary = args['summary'] as String;
        final start = _parseDateTime(args['start'] as String);
        if (start == null) {
          return CallToolResult(
            content: [TextContent(text: 'Error: invalid start datetime')],
            isError: true,
          );
        }
        final end = _parseDateTime(args['end'] as String?) ??
            start.add(const Duration(hours: 1));
        final isAllDay = (args['isAllDay'] as bool?) ?? false;
        final description = args['description'] as String?;
        final location = args['location'] as String?;

        final calendars = await (_db.select(_db.calendars)).get();
        if (calendars.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'Error: no calendar available')],
            isError: true,
          );
        }

        final id = await _db.into(_db.events).insert(
              EventsCompanion.insert(
                calendarId: calendars.first.id,
                uid: 'local-${DateTime.now().millisecondsSinceEpoch}',
                summary: summary,
                startDt: isAllDay
                    ? DateTime(start.year, start.month, start.day)
                    : start,
                endDt: isAllDay
                    ? DateTime(start.year, start.month, start.day)
                        .add(const Duration(days: 1))
                    : end,
                isAllDay: Value(isAllDay),
                description: Value(description),
                location: Value(location),
                isDirty: const Value(true),
              ),
            );

        return CallToolResult(
          content: [
            TextContent(text: 'Event "$summary" created (id: $id)'),
          ],
        );
      },
    );

    server.registerTool(
      'create_todo',
      title: 'Create Todo',
      description: 'Create a new todo item',
      inputSchema: JsonObject(
        properties: {
          'summary': JsonSchema.string(description: 'Todo title'),
          'dueDate': JsonSchema.string(
            description: 'Due date (yyyy-MM-dd)',
          ),
          'description': JsonSchema.string(description: 'Todo description'),
          'priority': JsonSchema.integer(
            description: 'Priority 0-9 (0 = none, 1 = highest)',
          ),
        },
        required: ['summary'],
      ),
      annotations: ToolAnnotations(destructiveHint: false),
      callback: (args, _) async {
        final summary = args['summary'] as String;
        final dueDate = _parseDate(args['dueDate'] as String?);
        final description = args['description'] as String?;
        final priority = (args['priority'] as int?) ?? 0;

        final calendars = await (_db.select(_db.calendars)).get();
        if (calendars.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'Error: no calendar available')],
            isError: true,
          );
        }

        final id = await _db.into(_db.todos).insert(
              TodosCompanion.insert(
                calendarId: calendars.first.id,
                uid: 'local-${DateTime.now().millisecondsSinceEpoch}',
                summary: summary,
                dueDate: Value(dueDate),
                description: Value(description),
                priority: Value(priority),
                isDirty: const Value(true),
              ),
            );

        return CallToolResult(
          content: [
            TextContent(text: 'Todo "$summary" created (id: $id)'),
          ],
        );
      },
    );

    server.registerTool(
      'complete_todo',
      title: 'Complete Todo',
      description: 'Mark a todo as completed',
      inputSchema: JsonObject(
        properties: {
          'id': JsonSchema.integer(description: 'Todo ID'),
        },
        required: ['id'],
      ),
      annotations: ToolAnnotations(destructiveHint: false),
      callback: (args, _) async {
        final id = args['id'] as int;
        final todo = await (_db.select(_db.todos)
              ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (todo == null) {
          return CallToolResult(
            content: [TextContent(text: 'Error: todo $id not found')],
            isError: true,
          );
        }

        await (_db.update(_db.todos)..where((t) => t.id.equals(id))).write(
          TodosCompanion(
            status: const Value('COMPLETED'),
            completedAt: Value(DateTime.now()),
            percentComplete: const Value(100),
            isDirty: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );

        return CallToolResult(
          content: [
            TextContent(text: 'Todo "${todo.summary}" completed'),
          ],
        );
      },
    );

    server.registerTool(
      'search',
      title: 'Search',
      description: 'Search events and todos by keyword',
      inputSchema: JsonObject(
        properties: {
          'query': JsonSchema.string(description: 'Search keyword'),
          'limit': JsonSchema.integer(description: 'Max results per type (default 10)'),
        },
        required: ['query'],
      ),
      annotations: ToolAnnotations(readOnlyHint: true),
      callback: (args, _) async {
        final keyword = '%${args['query'] as String}%';
        final limit = (args['limit'] as int?) ?? 10;

        final events = await (_db.select(_db.events)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    (t.summary.like(keyword) |
                        t.description.like(keyword)),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.startDt)])
              ..limit(limit))
            .get();

        final todos = await (_db.select(_db.todos)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    (t.summary.like(keyword) |
                        t.description.like(keyword)),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.dueDate)])
              ..limit(limit))
            .get();

        return CallToolResult(
          content: [
            TextContent(
              text: JsonEncoder.withIndent('  ').convert({
                'events': events
                    .map((e) => {
                          'id': e.id,
                          'summary': e.summary,
                          'start': e.startDt.toIso8601String(),
                        })
                    .toList(),
                'todos': todos
                    .map((t) => {
                          'id': t.id,
                          'summary': t.summary,
                          'status': t.status,
                          if (t.dueDate != null)
                            'dueDate': t.dueDate!.toIso8601String(),
                        })
                    .toList(),
              }),
            ),
          ],
        );
      },
    );
  }

  void _registerResources(McpServer server) {
    server.registerResource(
      'events_today',
      'calendar://events/today',
      (description: 'Today\'s events', mimeType: 'application/json'),
      (uri, _) async {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = todayStart.add(const Duration(days: 1));

        final events = await (_db.select(_db.events)
              ..where((t) => t.deletedAt.isNull())
              ..where(
                (t) =>
                    t.startDt.isSmallerThanValue(todayEnd) &
                    t.endDt.isBiggerThanValue(todayStart),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.startDt)]))
            .get();

        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              mimeType: 'application/json',
              text: JsonEncoder.withIndent('  ').convert(
                events
                    .map((e) => {
                          'id': e.id,
                          'summary': e.summary,
                          'start':
                              '${e.startDt.hour.toString().padLeft(2, '0')}:${e.startDt.minute.toString().padLeft(2, '0')}',
                          'end':
                              '${e.endDt.hour.toString().padLeft(2, '0')}:${e.endDt.minute.toString().padLeft(2, '0')}',
                          'isAllDay': e.isAllDay,
                        })
                    .toList(),
              ),
            ),
          ],
        );
      },
    );

    server.registerResource(
      'todos_pending',
      'calendar://todos/pending',
      (description: 'Pending todos', mimeType: 'application/json'),
      (uri, _) async {
        final todos = await (_db.select(_db.todos)
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.status.isNotIn(['COMPLETED', 'CANCELLED']))
              ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
            .get();

        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              mimeType: 'application/json',
              text: JsonEncoder.withIndent('  ').convert(
                todos
                    .map((t) => {
                          'id': t.id,
                          'summary': t.summary,
                          'status': t.status,
                          if (t.dueDate != null)
                            'dueDate': t.dueDate!.toIso8601String(),
                          'priority': t.priority,
                        })
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  DateTime? _parseDate(String? s, {int? year, int? month, int? day}) {
    if (s == null) {
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
      return null;
    }
    final parts = s.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return null;
  }

  DateTime? _parseDateTime(String? s) {
    if (s == null) return null;
    return DateTime.tryParse(s);
  }
}
