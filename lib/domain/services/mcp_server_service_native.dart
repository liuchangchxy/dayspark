import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:dayspark/data/local/database/app_database.dart';

/// Embedded MCP Server that exposes calendar/todo data to external AI agents.
/// Runs a StreamableHTTP server on localhost for desktop platforms.
class McpServerService {
  final AppDatabase _db;
  McpServer? _server;
  HttpServer? _httpServer;

  McpServerService(this._db);

  Future<void> start({int port = 3001}) async {
    _server = McpServer(
      Implementation(name: 'calendar-todo-mcp', version: '1.0.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          resources: ServerCapabilitiesResources(),
        ),
      ),
    );

    _registerTools();
    _registerResources();

    // Create StreamableHTTP transport - it handles individual HTTP requests,
    // we bind the HttpServer and delegate requests to it.
    final transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: () =>
            'cal-todo-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    await _server!.connect(transport);

    // Bind an HTTP server and route /mcp requests to the transport.
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _httpServer!.listen((HttpRequest request) {
      if (request.uri.path == '/mcp') {
        transport.handleRequest(request);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found. MCP endpoint is at /mcp')
          ..close();
      }
    });
  }

  void _registerTools() {
    _server!.registerTool(
      'list_events',
      description: 'List calendar events for a date range',
      inputSchema: ToolInputSchema(
        properties: {
          'start': JsonSchema.string(description: 'Start date (ISO 8601)'),
          'end': JsonSchema.string(description: 'End date (ISO 8601)'),
        },
        required: ['start', 'end'],
      ),
      callback: (args, extra) async {
        final start = DateTime.parse(args['start'] as String);
        final end = DateTime.parse(args['end'] as String);
        final events =
            await (_db.select(_db.events)..where(
                  (t) =>
                      t.startDt.isBiggerOrEqualValue(start) &
                      t.startDt.isSmallerThanValue(end),
                ))
                .get();
        return CallToolResult(
          content: [
            TextContent(text: jsonEncode(events.map(_eventToMap).toList())),
          ],
        );
      },
    );

    _server!.registerTool(
      'list_todos',
      description: 'List pending todo items',
      inputSchema: ToolInputSchema(
        properties: {
          'status': JsonSchema.string(
            description: 'Filter by status: "all", "pending", "completed"',
          ),
        },
      ),
      callback: (args, extra) async {
        final statusFilter = args['status'] as String? ?? 'pending';
        var query = _db.select(_db.todos);
        if (statusFilter == 'pending') {
          query = query..where((t) => t.status.equals('NEEDS-ACTION'));
        } else if (statusFilter == 'completed') {
          query = query..where((t) => t.status.equals('COMPLETED'));
        }
        final todos = await query.get();
        return CallToolResult(
          content: [
            TextContent(text: jsonEncode(todos.map(_todoToMap).toList())),
          ],
        );
      },
    );

    _server!.registerTool(
      'create_todo',
      description: 'Create a new todo item',
      inputSchema: ToolInputSchema(
        properties: {
          'summary': JsonSchema.string(description: 'Todo title'),
          'dueDate': JsonSchema.string(description: 'Due date (ISO 8601)'),
          'priority': JsonSchema.integer(
            description: 'Priority 1=high, 5=medium, 9=low, 0=none',
          ),
          'description': JsonSchema.string(description: 'Description'),
        },
        required: ['summary'],
      ),
      callback: (args, extra) async {
        final summary = args['summary'] as String;
        final dueDate = args['dueDate'] != null
            ? DateTime.parse(args['dueDate'] as String)
            : null;
        final priority = args['priority'] as int? ?? 0;
        final description = args['description'] as String?;

        // Find first calendar
        final cals = await (_db.select(_db.calendars)).get();
        if (cals.isEmpty) {
          return CallToolResult(
            content: [const TextContent(text: 'Error: No calendar found')],
            isError: true,
          );
        }

        await _db
            .into(_db.todos)
            .insert(
              TodosCompanion.insert(
                calendarId: cals.first.id,
                uid: 'mcp-${DateTime.now().millisecondsSinceEpoch}',
                summary: summary,
                dueDate: dueDate != null
                    ? Value(dueDate)
                    : const Value.absent(),
                priority: Value(priority),
                description: Value(description),
                isDirty: const Value(true),
              ),
            );

        return CallToolResult(
          content: [TextContent(text: 'Todo "$summary" created')],
        );
      },
    );

    _server!.registerTool(
      'create_event',
      description: 'Create a new calendar event',
      inputSchema: ToolInputSchema(
        properties: {
          'summary': JsonSchema.string(description: 'Event title'),
          'start': JsonSchema.string(description: 'Start time (ISO 8601)'),
          'end': JsonSchema.string(description: 'End time (ISO 8601)'),
          'isAllDay': JsonSchema.boolean(description: 'All-day event'),
          'location': JsonSchema.string(description: 'Location'),
          'description': JsonSchema.string(description: 'Description'),
        },
        required: ['summary', 'start', 'end'],
      ),
      callback: (args, extra) async {
        final summary = args['summary'] as String;
        final start = DateTime.parse(args['start'] as String);
        final end = DateTime.parse(args['end'] as String);
        final isAllDay = args['isAllDay'] as bool? ?? false;
        final location = args['location'] as String?;
        final description = args['description'] as String?;

        final cals = await (_db.select(_db.calendars)).get();
        if (cals.isEmpty) {
          return CallToolResult(
            content: [const TextContent(text: 'Error: No calendar found')],
            isError: true,
          );
        }

        await _db
            .into(_db.events)
            .insert(
              EventsCompanion.insert(
                calendarId: cals.first.id,
                uid: 'mcp-${DateTime.now().millisecondsSinceEpoch}',
                summary: summary,
                startDt: start,
                endDt: end,
                isAllDay: Value(isAllDay),
                location: Value(location),
                description: Value(description),
                isDirty: const Value(true),
              ),
            );

        return CallToolResult(
          content: [TextContent(text: 'Event "$summary" created')],
        );
      },
    );

    _server!.registerTool(
      'complete_todo',
      description: 'Mark a todo as completed',
      inputSchema: ToolInputSchema(
        properties: {'id': JsonSchema.integer(description: 'Todo ID')},
        required: ['id'],
      ),
      callback: (args, extra) async {
        final id = args['id'] as int;
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
          content: [TextContent(text: 'Todo $id marked as completed')],
        );
      },
    );

    _server!.registerTool(
      'search',
      description: 'Search events and todos by keyword',
      inputSchema: ToolInputSchema(
        properties: {'query': JsonSchema.string(description: 'Search keyword')},
        required: ['query'],
      ),
      callback: (args, extra) async {
        final q = args['query'] as String;
        final pattern = '%$q%';
        final events =
            await (_db.select(_db.events)..where(
                  (t) => t.summary.like(pattern) | t.description.like(pattern),
                ))
                .get();
        final todos =
            await (_db.select(_db.todos)..where(
                  (t) => t.summary.like(pattern) | t.description.like(pattern),
                ))
                .get();
        return CallToolResult(
          content: [
            TextContent(
              text: jsonEncode({
                'events': events.map(_eventToMap).toList(),
                'todos': todos.map(_todoToMap).toList(),
              }),
            ),
          ],
        );
      },
    );
  }

  void _registerResources() {
    _server!.registerResource(
      "Today's Events",
      'calendar://events/today',
      (
        description: 'All calendar events for today',
        mimeType: 'application/json',
      ),
      (uri, extra) async {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1));
        final events =
            await (_db.select(_db.events)..where(
                  (t) =>
                      t.startDt.isBiggerOrEqualValue(start) &
                      t.startDt.isSmallerThanValue(end),
                ))
                .get();
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              mimeType: 'application/json',
              text: jsonEncode(events.map(_eventToMap).toList()),
            ),
          ],
        );
      },
    );

    _server!.registerResource(
      'Pending Todos',
      'calendar://todos/pending',
      (
        description: 'All pending (incomplete) todo items',
        mimeType: 'application/json',
      ),
      (uri, extra) async {
        final todos = await (_db.select(
          _db.todos,
        )..where((t) => t.status.equals('NEEDS-ACTION'))).get();
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              mimeType: 'application/json',
              text: jsonEncode(todos.map(_todoToMap).toList()),
            ),
          ],
        );
      },
    );
  }

  Map<String, dynamic> _eventToMap(Event e) => {
    'id': e.id,
    'summary': e.summary,
    'start': e.startDt.toIso8601String(),
    'end': e.endDt.toIso8601String(),
    'isAllDay': e.isAllDay,
    'location': e.location,
    'description': e.description,
  };

  Map<String, dynamic> _todoToMap(Todo t) => {
    'id': t.id,
    'summary': t.summary,
    'dueDate': t.dueDate?.toIso8601String(),
    'priority': t.priority,
    'status': t.status,
    'description': t.description,
  };

  Future<void> stop() async {
    await _httpServer?.close();
    await _server?.close();
    _httpServer = null;
    _server = null;
  }
}
