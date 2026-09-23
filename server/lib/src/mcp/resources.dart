import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';

import '../data/record_query.dart';
import '../data/rrule_window.dart';
import '../db.dart';
import 'schemas.dart';
import 'tools.dart';

// The three MCP resource snapshots. Resources carry no parameters, so the
// day buckets are UTC-based — descriptions state that explicitly and hints
// steer fine-grained questions to the list_tasks/get_events tools.

class McpResource {
  const McpResource({
    required this.uri,
    required this.name,
    required this.description,
    required this.kind,
  });

  final String uri;
  final String name;
  final String description;
  final String kind;

  Map<String, Object?> toJson() => <String, Object?>{
        'uri': uri,
        'name': name,
        'description': description,
        'mimeType': 'application/json',
      };
}

const List<McpResource> mcpResources = [
  McpResource(
    uri: 'dayspark://today',
    name: 'Today',
    description:
        'Snapshot (UTC day) of tasks due today plus events happening today. '
        'For a local-timezone view use the list_tasks/get_events tools.',
    kind: 'today',
  ),
  McpResource(
    uri: 'dayspark://overdue',
    name: 'Overdue',
    description:
        'Snapshot of open tasks whose due date is in the past (UTC now). '
        'Fine-grained ranges: list_tasks with due_before/due_after.',
    kind: 'overdue',
  ),
  McpResource(
    uri: 'dayspark://inbox',
    name: 'Inbox',
    description:
        'Snapshot of tasks without a due date (floating inbox items). '
        'Filter or sort them with the list_tasks tool.',
    kind: 'inbox',
  ),
];

Future<Map<String, Object?>> readMcpResource(
  McpToolContext ctx,
  String uri,
) async {
  final resource = mcpResources.where((r) => r.uri == uri).firstOrNull;
  if (resource == null) {
    throw McpToolException(
      mcpCodeResourceNotFound,
      'resource not found: $uri',
      'Call resources/list to see the available URIs '
          '(dayspark://today, dayspark://overdue, dayspark://inbox).',
    );
  }
  final generatedAt = ctx.now.toUtc();
  final tasks = switch (resource.kind) {
    'today' => _todayTasks(ctx, generatedAt),
    'overdue' => _overdueTasks(ctx, generatedAt),
    _ => _inboxTasks(ctx),
  };
  final events = switch (resource.kind) {
    'today' => _todayEvents(ctx, generatedAt),
    _ => Future<List<Map<String, Object?>>>.value(const []),
  };
  return <String, Object?>{
    'kind': resource.kind,
    'uri': resource.uri,
    'generatedAt': isoZ(generatedAt),
    'tasks': await tasks,
    'events': await events,
  };
}

Future<List<Map<String, Object?>>> _todayTasks(
  McpToolContext ctx,
  DateTime now,
) async {
  final page = await queryRecords(
    ctx.db,
    userId: ctx.userId,
    type: RecordType.todo,
    dueOn: _utcDate(now),
    timezone: 'UTC',
    limit: recordQueryMaxLimit,
  );
  return page.records.map(taskJson).toList();
}

Future<List<Map<String, Object?>>> _overdueTasks(
  McpToolContext ctx,
  DateTime now,
) async {
  final page = await queryRecords(
    ctx.db,
    userId: ctx.userId,
    type: RecordType.todo,
    dueTo: now,
    timezone: 'UTC',
    limit: recordQueryMaxLimit,
  );
  return page.records
      .where((row) {
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        return payload['status'] != 'COMPLETED' &&
            payload['status'] != 'CANCELLED';
      })
      .map(taskJson)
      .toList();
}

Future<List<Map<String, Object?>>> _inboxTasks(McpToolContext ctx) async {
  final rows = <RecordRow>[];
  String? cursor;
  while (rows.length < recordQueryMaxLimit) {
    final page = await queryRecords(
      ctx.db,
      userId: ctx.userId,
      type: RecordType.todo,
      cursor: cursor,
      limit: recordQueryMaxLimit,
    );
    for (final row in page.records) {
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      if (payload['dueDate'] == null) {
        rows.add(row);
        if (rows.length >= recordQueryMaxLimit) {
          break;
        }
      }
    }
    if (!page.hasMore || page.nextCursor == null) {
      break;
    }
    cursor = page.nextCursor;
  }
  return rows.map(taskJson).toList();
}

Future<List<Map<String, Object?>>> _todayEvents(
  McpToolContext ctx,
  DateTime now,
) async {
  final dayStart = DateTime.utc(now.year, now.month, now.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final page = await queryRecords(
    ctx.db,
    userId: ctx.userId,
    type: RecordType.event,
    from: dayStart,
    to: dayEnd,
    timezone: 'UTC',
    limit: recordQueryMaxLimit,
  );
  final expansion = expandRecordsInWindow(
    page.records,
    from: dayStart,
    to: dayEnd,
  );
  return [
    for (final instance in expansion.instances)
      <String, Object?>{
        'event_id': instance.master.id,
        'title':
            (jsonDecode(instance.master.payloadJson)
                as Map<String, dynamic>)['summary'],
        'start': isoZ(instance.start),
        'end': isoZ(instance.end),
        'all_day': (jsonDecode(instance.master.payloadJson)
            as Map<String, dynamic>)['isAllDay'] == true,
      },
  ];
}

String _utcDate(DateTime now) => '${now.year.toString().padLeft(4, '0')}-'
    '${now.month.toString().padLeft(2, '0')}-'
    '${now.day.toString().padLeft(2, '0')}';
