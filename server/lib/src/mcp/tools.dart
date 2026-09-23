import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:timezone/timezone.dart' as tz;

import '../data/record_query.dart';
import '../data/record_writer.dart';
import '../data/rrule_window.dart';
import '../db.dart';
import 'schemas.dart';

// The frozen MCP tool surface (Task-2 brief): 7 read + 10 write tools over
// record_query / record_writer / rrule_window. Handlers never see JSON-RPC —
// they throw McpToolException and endpoint.dart renders errors-as-tool-results.

class McpToolContext {
  McpToolContext({
    required this.db,
    required this.userId,
    required this.notifySeq,
    required this.idempotency,
    required this.now,
  });

  final AppDatabase db;
  final String userId;
  final void Function(String userId, int seq) notifySeq;
  final IdempotencyRegistry idempotency;
  final DateTime now;
}

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.readOnly,
    required this.destructive,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final bool readOnly;
  final bool destructive;
  final Future<Map<String, Object?>> Function(
    McpToolContext ctx,
    Map<String, Object?> args,
  ) handler;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': <String, Object?>{
          'readOnlyHint': readOnly,
          'destructiveHint': destructive,
        },
      };
}

const int _maxWindowDays = 366;
const int _defaultListLimit = 50;
const int _maxListLimit = 200;

Map<String, Object?> _objectSchema(
  Map<String, Object?> properties, {
  List<String> required = const [],
  String? description,
}) =>
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      if (required.isNotEmpty) 'required': required,
      if (description != null) 'description': description,
      'properties': properties,
    };

final Map<String, Object?> _limitSchema = {
  'type': 'integer',
  'minimum': 1,
  'maximum': _maxListLimit,
  'description': 'page size (default $_defaultListLimit, max $_maxListLimit)',
};

final Map<String, Object?> _idSchema = {
  'type': 'string',
  'minLength': 1,
};

bool _trashed(RecordRow row) {
  if (row.deleted) {
    return true;
  }
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  return payload['deletedAt'] != null;
}

String? _payloadIso(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : isoZ(parsed);
}

Future<RecordRow?> _findRow(
  McpToolContext ctx,
  String id, {
  required String type,
}) {
  return (ctx.db.select(ctx.db.records)
        ..where((t) =>
            t.userId.equals(ctx.userId) &
            t.id.equals(id) &
            t.type.equals(type)))
      .getSingleOrNull();
}

Future<RecordRow> _requireVisible(
  McpToolContext ctx, {
  required String id,
  required String type,
}) async {
  final row = await _findRow(ctx, id, type: type);
  if (row == null || _trashed(row)) {
    throw type == 'event'
        ? McpToolException(
            mcpCodeEventNotFound,
            'event not found: $id',
            hintEventNotFound,
          )
        : McpToolException(
            mcpCodeTaskNotFound,
            'task not found: $id',
            hintTaskNotFound,
          );
  }
  return row;
}

Map<String, Object?> eventJson(RecordRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  return <String, Object?>{
    'event_id': row.id,
    'title': payload['summary'],
    'start': _payloadIso(payload['startDt']),
    'end': _payloadIso(payload['endDt']),
    'all_day': payload['isAllDay'] == true,
    'description': payload['description'],
    'location': payload['location'],
    'recurrence': payload['rrule'],
    'trashed': _trashed(row),
    'created_at': _payloadIso(payload['createdAt']),
    'updated_at': _payloadIso(payload['updatedAt']),
    'rev': row.rev,
  };
}

Map<String, Object?> taskJson(RecordRow row) {
  final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
  return <String, Object?>{
    'task_id': row.id,
    'title': payload['summary'],
    'due': _payloadIso(payload['dueDate']),
    'priority': payload['priority'] ?? 0,
    'status': payload['status'] ?? 'NEEDS-ACTION',
    'description': payload['description'],
    'tags': payload['tags'],
    'percent': payload['percentComplete'] ?? 0,
    'completed_at': _payloadIso(payload['completedAt']),
    'trashed': _trashed(row),
    'created_at': _payloadIso(payload['createdAt']),
    'updated_at': _payloadIso(payload['updatedAt']),
    'rev': row.rev,
  };
}

bool _isOpenStatus(Object? status) =>
    status != 'COMPLETED' && status != 'CANCELLED';

bool _matchesStatus(Map<String, dynamic> payload, String filter) {
  final status = payload['status'] ?? 'NEEDS-ACTION';
  return switch (filter) {
    'open' => _isOpenStatus(status),
    'completed' => status == 'COMPLETED',
    'cancelled' => status == 'CANCELLED',
    'any' => true,
    _ => true,
  };
}

Future<Map<String, Object?>> _opJson(OpResult result) async =>
    <String, Object?>{
      'opId': result.opId,
      'status': result.status.name,
      if (result.code != null) 'code': result.code,
      'rev': result.serverRecord?.rev,
    };

// Single write path for every AI mutation: opId = idempotency_key when the
// caller supplied one (with per-record fingerprint enforcement), otherwise a
// fresh uuid; lands in applyInternalOp so LWW/seq/post-commit notify match
// the HTTP push route exactly.
Future<OpResult> _applyWrite(
  McpToolContext ctx, {
  required String recordId,
  required RecordType type,
  required Map<String, Object?> fields,
  required Map<String, Object?> requestArgs,
  String? idempotencyKey,
}) async {
  final opId = idempotencyKey ?? newOpId();
  if (idempotencyKey != null) {
    final fingerprint = stableJson(requestArgs);
    if (ctx.idempotency.contains(ctx.userId, opId) &&
        !ctx.idempotency.matches(ctx.userId, opId, fingerprint)) {
      throw mcpValidation(
        'idempotency_key "$idempotencyKey" was reused with a different request body',
        hint: hintIdempotencyReuse,
      );
    }
    final result = await applyInternalOp(
      db: ctx.db,
      userId: ctx.userId,
      op: PushOp(
        opId: opId,
        op: OpType.upsert,
        recordId: recordId,
        type: type,
        fields: fields,
      ),
      notify: ctx.notifySeq,
    );
    ctx.idempotency.record(ctx.userId, opId, fingerprint);
    return result;
  }
  return applyInternalOp(
    db: ctx.db,
    userId: ctx.userId,
    op: PushOp(
      opId: opId,
      op: OpType.upsert,
      recordId: recordId,
      type: type,
      fields: fields,
    ),
    notify: ctx.notifySeq,
  );
}

Future<OpResult> _writeChecked(
  McpToolContext ctx, {
  required String recordId,
  required RecordType type,
  required Map<String, Object?> fields,
  required Map<String, Object?> requestArgs,
  String? idempotencyKey,
}) async {
  final result = await _applyWrite(
    ctx,
    recordId: recordId,
    type: type,
    fields: fields,
    requestArgs: requestArgs,
    idempotencyKey: idempotencyKey,
  );
  if (result.status == OpStatus.conflict) {
    throw McpToolException(
      mcpCodeWriteConflict,
      'write conflicted with a newer tombstone (code: ${result.code})',
      defaultHint(mcpCodeWriteConflict),
    );
  }
  if (result.status != OpStatus.applied) {
    throw McpToolException(
      mcpCodeWriteRejected,
      'write rejected by the sync layer (code: ${result.code})',
      'Retry with a complete, valid record body; check for a type mismatch '
          'on an existing record id.',
    );
  }
  return result;
}

String _requireTitle(Object? raw, String field) {
  if (raw is! String || raw.trim().isEmpty) {
    throw mcpValidation(
      '$field must be a non-empty string',
      hint: 'Provide a short, specific $field.',
    );
  }
  return raw.trim();
}

int _limitOf(Object? raw, {int fallback = _defaultListLimit}) {
  if (raw == null) {
    return fallback;
  }
  if (raw is! int) {
    throw mcpValidation('limit must be an integer');
  }
  if (raw < 1 || raw > _maxListLimit) {
    throw mcpValidation('limit must be between 1 and $_maxListLimit');
  }
  return raw;
}

void _checkWindow(DateTime from, DateTime to, String tool) {
  if (!to.isAfter(from)) {
    throw mcpValidation('$tool: to must be after from');
  }
  if (to.difference(from) > const Duration(days: _maxWindowDays)) {
    throw McpToolException(
      mcpCodeWindowTooLarge,
      '$tool window spans more than $_maxWindowDays days',
      hintWindowTooLarge,
    );
  }
}

// Pages queryRecords until [predicate] fills [limit] rows or the set is
// exhausted, so status/inbox post-filters keep a stable cursor contract
// (next_cursor = last delivered id, null when the set ended).
Future<({List<RecordRow> rows, String? nextCursor})> _collect(
  McpToolContext ctx, {
  RecordType? type,
  DateTime? from,
  DateTime? to,
  String? dueOn,
  DateTime? dueFrom,
  DateTime? dueTo,
  String? search,
  String? cursor,
  required int limit,
  required bool Function(RecordRow row) predicate,
}) async {
  final rows = <RecordRow>[];
  var currentCursor = cursor;
  while (true) {
    final page = await queryRecords(
      ctx.db,
      userId: ctx.userId,
      type: type,
      from: from,
      to: to,
      dueOn: dueOn,
      dueFrom: dueFrom,
      dueTo: dueTo,
      timezone: 'UTC',
      search: search,
      cursor: currentCursor,
      limit: limit,
    );
    for (final row in page.records) {
      if (!predicate(row)) {
        continue;
      }
      rows.add(row);
      if (rows.length >= limit) {
        return (rows: rows, nextCursor: row.id);
      }
    }
    if (!page.hasMore || page.nextCursor == null) {
      return (rows: rows, nextCursor: null);
    }
    currentCursor = page.nextCursor;
  }
}

Map<String, Object?> _taskPayloadCreate({
  required String title,
  required DateTime now,
  DateTime? due,
  int? priority,
  Object? description,
  Object? tags,
}) {
  return <String, Object?>{
    'summary': title,
    'description': description is String ? description : null,
    'dueDate': due == null ? null : isoZ(due),
    'startDate': null,
    'priority': priority ?? 0,
    'status': 'NEEDS-ACTION',
    'rrule': null,
    'completedAt': null,
    'percentComplete': 0,
    'deletedAt': null,
    'createdAt': isoZ(now),
    'updatedAt': isoZ(now),
    'sortOrder': 0,
    if (tags is List) 'tags': tags,
  };
}

Map<String, Object?> _eventPayloadCreate({
  required String title,
  required DateTime start,
  required DateTime end,
  required DateTime now,
  bool allDay = false,
  Object? description,
  Object? location,
  String? rrule,
}) {
  return <String, Object?>{
    'summary': title,
    'description': description is String ? description : null,
    'startDt': isoZ(start),
    'endDt': isoZ(end),
    'isAllDay': allDay,
    'location': location is String ? location : null,
    'rrule': rrule,
    'deletedAt': null,
    'createdAt': isoZ(now),
    'updatedAt': isoZ(now),
  };
}


final List<McpTool> mcpTools = <McpTool>[
  McpTool(
    name: 'get_events',
    description:
        'List calendar events in a time window (defaults: now → now+7d, max 366 days) '
        'with recurring events expanded into instances.',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema({
      'from': {
        'type': 'string',
        'description': 'ISO 8601 datetime with timezone (default: now)',
      },
      'to': {
        'type': 'string',
        'description': 'ISO 8601 datetime with timezone (default: from+7 days)',
      },
      'timezone': {
        'type': 'string',
        'description': 'IANA timezone name (validated; window is instant-based)',
      },
      'limit': _limitSchema,
    }),
    handler: (ctx, args) async {
      final now = ctx.now.toUtc();
      final from = args['from'] == null
          ? now
          : parseStrictUtc(args['from'], 'from');
      final to = args['to'] == null
          ? from.add(const Duration(days: 7))
          : parseStrictUtc(args['to'], 'to');
      _checkWindow(from, to, 'get_events');
      if (args['timezone'] != null) {
        parseIanaZone(args['timezone'], 'timezone');
      }
      final limit = _limitOf(args['limit']);

      final page = await queryRecords(
        ctx.db,
        userId: ctx.userId,
        type: RecordType.event,
        from: from,
        to: to,
        timezone: args['timezone'] as String? ?? 'UTC',
        limit: _maxListLimit,
      );
      final expansion = expandRecordsInWindow(
        page.records,
        from: from,
        to: to,
      );
      final all = expansion.instances;
      final events = <Map<String, Object?>>[];
      var truncated = expansion.truncated || page.hasMore;
      for (var i = 0; i < all.length; i++) {
        if (events.length >= limit) {
          truncated = true;
          break;
        }
        final instance = all[i];
        final payload =
            jsonDecode(instance.master.payloadJson) as Map<String, dynamic>;
        events.add(<String, Object?>{
          'event_id': instance.master.id,
          'title': payload['summary'],
          'start': isoZ(instance.start),
          'end': isoZ(instance.end),
          'all_day': payload['isAllDay'] == true,
          'description': payload['description'],
          'location': payload['location'],
          'recurrence': payload['rrule'],
          'is_recurrence': payload['rrule'] is String &&
              (payload['rrule'] as String).isNotEmpty,
        });
      }
      return <String, Object?>{
        'events': events,
        'truncated': truncated,
        'invalid_rrule_ids': expansion.invalidRruleIds,
        'window': {'from': isoZ(from), 'to': isoZ(to)},
      };
    },
  ),
  McpTool(
    name: 'get_event',
    description: 'Fetch one event by id (live records only; see list_trash for discarded ones).',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema(
      {'event_id': _idSchema},
      required: ['event_id'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['event_id']! as String,
        type: 'event',
      );
      return {'event': eventJson(row)};
    },
  ),
  McpTool(
    name: 'list_tasks',
    description:
        'List tasks with filter (today|overdue|upcoming|inbox), status, due range and cursor pagination. '
        'Day buckets use UTC (pass due_before/due_after for explicit ranges).',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema({
      'filter': {
        'type': 'string',
        'enum': ['today', 'overdue', 'upcoming', 'inbox'],
      },
      'status': {
        'type': 'string',
        'enum': ['open', 'completed', 'cancelled', 'any'],
        'description': 'completion filter (default: any)',
      },
      'due_before': {'type': 'string'},
      'due_after': {'type': 'string'},
      'limit': _limitSchema,
      'cursor': {'type': 'string'},
    }),
    handler: (ctx, args) async {
      final now = ctx.now.toUtc();
      String? dueOn;
      DateTime? dueFrom;
      DateTime? dueTo;
      var requireOpen = false;
      var requireNoDue = false;

      final filter = args['filter'] as String?;
      switch (filter) {
        case 'today':
          dueOn = '${now.year.toString().padLeft(4, '0')}-'
              '${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}';
        case 'upcoming':
          dueFrom = now;
        case 'overdue':
          dueTo = now;
          requireOpen = args['status'] == null;
        case 'inbox':
          requireNoDue = true;
      }
      if (args['due_before'] != null) {
        final bound = parseStrictUtc(args['due_before'], 'due_before');
        dueTo = dueTo == null || bound.isBefore(dueTo) ? bound : dueTo;
      }
      if (args['due_after'] != null) {
        final bound = parseStrictUtc(args['due_after'], 'due_after');
        dueFrom = dueFrom == null || bound.isAfter(dueFrom) ? bound : dueFrom;
      }
      final statusFilter = args['status'] as String? ?? 'any';
      final limit = _limitOf(args['limit']);

      bool predicate(RecordRow row) {
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        if (requireNoDue && payload['dueDate'] != null) {
          return false;
        }
        if (requireOpen && !_isOpenStatus(payload['status'])) {
          return false;
        }
        return _matchesStatus(payload, statusFilter);
      }

      final collected = await _collect(
        ctx,
        type: RecordType.todo,
        dueOn: dueOn,
        dueFrom: dueFrom,
        dueTo: dueTo,
        cursor: args['cursor'] as String?,
        limit: limit,
        predicate: predicate,
      );
      return <String, Object?>{
        'tasks': collected.rows.map(taskJson).toList(),
        'next_cursor': collected.nextCursor,
        'has_more': collected.nextCursor != null,
      };
    },
  ),
  McpTool(
    name: 'get_task',
    description: 'Fetch one task by id (live records only; see list_trash for discarded ones).',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema(
      {'task_id': _idSchema},
      required: ['task_id'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['task_id']! as String,
        type: 'todo',
      );
      return {'task': taskJson(row)};
    },
  ),
  McpTool(
    name: 'search',
    description: 'Case-insensitive search over title and description of events and/or tasks.',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema({
      'query': {'type': 'string', 'minLength': 1},
      'kind': {
        'type': 'string',
        'enum': ['event', 'task', 'all'],
      },
      'limit': _limitSchema,
    }),
    handler: (ctx, args) async {
      final query = (args['query']! as String).trim();
      if (query.isEmpty) {
        throw mcpValidation(
          'query must not be blank',
          hint: 'Search for a word that appears in the title or description.',
        );
      }
      final kind = args['kind'] as String? ?? 'all';
      final limit = _limitOf(args['limit']);
      final type = switch (kind) {
        'event' => RecordType.event,
        'task' => RecordType.todo,
        _ => null,
      };
      final page = await queryRecords(
        ctx.db,
        userId: ctx.userId,
        type: type,
        search: query,
        limit: limit,
      );
      final results = <Map<String, Object?>>[];
      for (final row in page.records) {
        if (row.type == 'event') {
          results.add({'kind': 'event', ...eventJson(row)});
        } else {
          results.add({'kind': 'task', ...taskJson(row)});
        }
      }
      return <String, Object?>{
        'results': results,
        'count': results.length,
      };
    },
  ),
  McpTool(
    name: 'find_free_time',
    description:
        'Find the earliest free slots in a window. v1 busy set = calendar events only '
        '(expanded); working defaults 09:00-18:00 Mon-Fri in the given IANA timezone; '
        'returns up to 10 slots.',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema({
      'from': {'type': 'string'},
      'to': {'type': 'string'},
      'duration_minutes': {'type': 'integer', 'minimum': 1, 'maximum': 1440},
      'timezone': {'type': 'string'},
      'working_hours_start': {
        'type': 'string',
        'description': 'HH:MM local (default 09:00)',
      },
      'working_hours_end': {
        'type': 'string',
        'description': 'HH:MM local (default 18:00)',
      },
      'working_days': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'],
        },
        'minItems': 1,
        'maxItems': 7,
      },
    },
      required: ['from', 'to', 'duration_minutes', 'timezone'],
    ),
    handler: (ctx, args) async {
      final from = parseStrictUtc(args['from'], 'from');
      final to = parseStrictUtc(args['to'], 'to');
      _checkWindow(from, to, 'find_free_time');
      final durationMinutes = args['duration_minutes']! as int;
      final duration = Duration(minutes: durationMinutes);
      if (duration > to.difference(from)) {
        throw mcpValidation(
          'duration_minutes ($durationMinutes) is longer than the window',
          hint: 'Pick a duration that fits inside [from, to).',
        );
      }
      final timezone = parseIanaZone(args['timezone'], 'timezone');
      final location = ianaLocation(timezone);

      (int, int) parseHours(Object? raw, String field) {
        final text = raw as String? ?? '';
        final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
        if (match == null) {
          throw mcpValidation(
            '$field must be HH:MM (24h), e.g. 09:00',
          );
        }
        final hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        if (hour > 23 || minute > 59) {
          throw mcpValidation('$field is not a valid time of day: $text');
        }
        return (hour, minute);
      }

      final (startHour, startMinute) =
          parseHours(args['working_hours_start'], 'working_hours_start');
      final (endHour, endMinute) =
          parseHours(args['working_hours_end'], 'working_hours_end');
      if (endHour < startHour ||
          (endHour == startHour && endMinute <= startMinute)) {
        throw mcpValidation(
          'working_hours_end must be after working_hours_start',
        );
      }
      const dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
      final rawDays = (args['working_days'] as List?)?.cast<String>().toSet() ??
          {'MO', 'TU', 'WE', 'TH', 'FR'};
      final workingDayNumbers = <int>{
        for (final code in rawDays) dayCodes.indexOf(code) + 1,
      };

      final page = await queryRecords(
        ctx.db,
        userId: ctx.userId,
        type: RecordType.event,
        from: from,
        to: to,
        timezone: 'UTC',
        limit: _maxListLimit,
      );
      final expansion = expandRecordsInWindow(
        page.records,
        from: from,
        to: to,
      );
      final busy = <(DateTime, DateTime)>[
        for (final instance in expansion.instances)
          (
            instance.start.isBefore(from) ? from : instance.start,
            instance.end.isAfter(to) ? to : instance.end,
          ),
      ].where((interval) => interval.$2.isAfter(interval.$1)).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));

      final merged = <(DateTime, DateTime)>[];
      for (final interval in busy) {
        if (merged.isEmpty || interval.$1.isAfter(merged.last.$2)) {
          merged.add(interval);
          continue;
        }
        if (interval.$2.isAfter(merged.last.$2)) {
          merged[merged.length - 1] = (merged.last.$1, interval.$2);
        }
      }

      final slots = <Map<String, Object?>>[];
      final fromLocal = tz.TZDateTime.from(from, location);
      final toLocal = tz.TZDateTime.from(to, location);
      var day = tz.TZDateTime(
        location,
        fromLocal.year,
        fromLocal.month,
        fromLocal.day,
      );
      final lastDay = tz.TZDateTime(
        location,
        toLocal.year,
        toLocal.month,
        toLocal.day,
      );
      while (!day.isAfter(lastDay) && slots.length < 10) {
        if (workingDayNumbers.contains(day.weekday)) {
          final workStart = tz.TZDateTime(
            location,
            day.year,
            day.month,
            day.day,
            startHour,
            startMinute,
          ).toUtc();
          final workEnd = tz.TZDateTime(
            location,
            day.year,
            day.month,
            day.day,
            endHour,
            endMinute,
          ).toUtc();
          final windowStart = workStart.isBefore(from) ? from : workStart;
          final windowEnd = workEnd.isAfter(to) ? to : workEnd;
          var cursor = windowStart;
          for (final interval in merged) {
            if (slots.length >= 10) {
              break;
            }
            if (interval.$2.isBefore(windowStart) ||
                interval.$1.isAfter(windowEnd)) {
              continue;
            }
            if (interval.$1.isAfter(cursor)) {
              final gapEnd =
                  interval.$1.isBefore(windowEnd) ? interval.$1 : windowEnd;
              _fillSlots(slots, cursor, gapEnd, duration);
            }
            if (interval.$2.isAfter(cursor)) {
              cursor = interval.$2;
            }
            if (!cursor.isBefore(windowEnd)) {
              break;
            }
          }
          if (cursor.isBefore(windowEnd)) {
            _fillSlots(slots, cursor, windowEnd, duration);
          }
        }
        day = tz.TZDateTime(location, day.year, day.month, day.day + 1);
      }

      return <String, Object?>{
        'slots': slots,
        'timezone': timezone,
        'duration_minutes': durationMinutes,
        'window': {'from': isoZ(from), 'to': isoZ(to)},
      };
    },
  ),
  McpTool(
    name: 'list_trash',
    description:
        'Browse the recycle bin: soft-trashed (deletedAt) and tombstoned records. Read-only.',
    readOnly: true,
    destructive: false,
    inputSchema: _objectSchema({
      'kind': {
        'type': 'string',
        'enum': ['event', 'task', 'all'],
      },
    }),
    handler: (ctx, args) async {
      final kind = args['kind'] as String? ?? 'all';
      final type = switch (kind) {
        'event' => RecordType.event,
        'task' => RecordType.todo,
        _ => null,
      };
      final page = await queryRecords(
        ctx.db,
        userId: ctx.userId,
        type: type,
        trashedOnly: true,
        limit: _maxListLimit,
      );
      final items = <Map<String, Object?>>[];
      for (final row in page.records) {
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        final trashedAt =
            _payloadIso(payload['deletedAt']) ?? isoZ(row.serverTs);
        if (row.type == 'event') {
          items.add({
            'id': row.id,
            'kind': 'event',
            ...eventJson(row),
            'trashed_at': trashedAt,
          });
        } else {
          items.add({
            'id': row.id,
            'kind': 'task',
            ...taskJson(row),
            'trashed_at': trashedAt,
          });
        }
      }
      return <String, Object?>{
        'items': items,
        'count': items.length,
        'has_more': page.hasMore,
      };
    },
  ),
  McpTool(
    name: 'create_event',
    description:
        'Create a calendar event. Datetimes are ISO 8601 with explicit timezone; '
        'recurrence is a structured object.',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema({
      'title': {'type': 'string', 'minLength': 1},
      'start': {'type': 'string'},
      'end': {'type': 'string'},
      'timezone': {'type': 'string'},
      'all_day': {'type': 'boolean'},
      'description': {'type': ['string', 'null']},
      'location': {'type': ['string', 'null']},
      'recurrence': recurrenceSchema(),
      'idempotency_key': {'type': 'string', 'minLength': 1, 'maxLength': 128},
    },
      required: ['title', 'start', 'end'],
    ),
    handler: (ctx, args) async {
      final title = _requireTitle(args['title'], 'title');
      final start = parseStrictUtc(args['start'], 'start');
      final end = parseStrictUtc(args['end'], 'end');
      if (!end.isAfter(start)) {
        throw mcpValidation('end must be after start');
      }
      if (args['timezone'] != null) {
        parseIanaZone(args['timezone'], 'timezone');
      }
      final rrule = args['recurrence'] == null
          ? null
          : parseRruleStructured(args['recurrence'], 'recurrence');
      final now = ctx.now.toUtc();
      final fields = _eventPayloadCreate(
        title: title,
        start: start,
        end: end,
        now: now,
        allDay: args['all_day'] == true,
        description: args['description'],
        location: args['location'],
        rrule: rrule,
      );
      final result = await _writeChecked(
        ctx,
        recordId: newOpId(),
        type: RecordType.event,
        fields: fields,
        requestArgs: args,
        idempotencyKey: args['idempotency_key'] as String?,
      );
      // An idempotent replay carries the FIRST call's record id — always
      // resolve through the op result, never through a freshly generated id.
      final created =
          await _findRow(ctx, result.serverRecord!.id, type: 'event');
      return <String, Object?>{
        'event': eventJson(created!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'update_event',
    description:
        'PATCH an event: only the fields you pass are changed; pass null to clear '
        'description/location/recurrence.',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema({
      'event_id': _idSchema,
      'title': {'type': 'string', 'minLength': 1},
      'start': {'type': 'string'},
      'end': {'type': 'string'},
      'timezone': {'type': 'string'},
      'all_day': {'type': 'boolean'},
      'description': {'type': ['string', 'null']},
      'location': {'type': ['string', 'null']},
      'recurrence': recurrenceSchema(),
      'idempotency_key': {'type': 'string', 'minLength': 1, 'maxLength': 128},
    },
      required: ['event_id'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['event_id']! as String,
        type: 'event',
      );
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final now = ctx.now.toUtc();
      final fields = <String, Object?>{};

      if (args.containsKey('title')) {
        fields['summary'] = _requireTitle(args['title'], 'title');
      }
      DateTime? start;
      if (args.containsKey('start')) {
        start = parseStrictUtc(args['start'], 'start');
        fields['startDt'] = isoZ(start);
      }
      DateTime? end;
      if (args.containsKey('end')) {
        end = parseStrictUtc(args['end'], 'end');
        fields['endDt'] = isoZ(end);
      }
      final effectiveStart =
          start ?? (payload['startDt'] == null ? null : DateTime.tryParse(payload['startDt'] as String));
      final effectiveEnd =
          end ?? (payload['endDt'] == null ? null : DateTime.tryParse(payload['endDt'] as String));
      if (effectiveStart != null && effectiveEnd != null) {
        if (!effectiveEnd.toUtc().isAfter(effectiveStart.toUtc())) {
          throw mcpValidation('end must be after start');
        }
      }
      if (args.containsKey('timezone')) {
        parseIanaZone(args['timezone'], 'timezone');
      }
      if (args.containsKey('all_day')) {
        fields['isAllDay'] = args['all_day'];
      }
      if (args.containsKey('description')) {
        fields['description'] = args['description'];
      }
      if (args.containsKey('location')) {
        fields['location'] = args['location'];
      }
      if (args.containsKey('recurrence')) {
        fields['rrule'] = args['recurrence'] == null
            ? null
            : parseRruleStructured(args['recurrence'], 'recurrence');
      }
      if (fields.isEmpty) {
        throw mcpValidation(
          'no updatable fields supplied',
          hint: 'Pass at least one of title, start, end, description, location, recurrence, all_day.',
        );
      }
      fields['updatedAt'] = isoZ(now);
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.event,
        fields: fields,
        requestArgs: args,
        idempotencyKey: args['idempotency_key'] as String?,
      );
      final updated = await _findRow(ctx, row.id, type: 'event');
      return <String, Object?>{
        'event': eventJson(updated!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'trash_event',
    description:
        'Move an event to the recycle bin (soft delete via deletedAt — restorable in the app). '
        'Not a permanent delete.',
    readOnly: false,
    destructive: true,
    inputSchema: _objectSchema(
      {'event_id': _idSchema},
      required: ['event_id'],
    ),
    handler: (ctx, args) async {
      final row = await _findRow(
        ctx,
        args['event_id']! as String,
        type: 'event',
      );
      if (row == null) {
        throw McpToolException(
          mcpCodeEventNotFound,
          'event not found: ${args['event_id']}',
          hintEventNotFound,
        );
      }
      if (_trashed(row)) {
        return <String, Object?>{
          'event': eventJson(row),
          'trashed': true,
          'changed': false,
        };
      }
      final now = ctx.now.toUtc();
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.event,
        fields: {
          'deletedAt': isoZ(now),
          'updatedAt': isoZ(now),
        },
        requestArgs: args,
      );
      final updated = await _findRow(ctx, row.id, type: 'event');
      return <String, Object?>{
        'event': eventJson(updated!),
        'trashed': true,
        'changed': true,
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'create_task',
    description:
        'Create a task. due is ISO 8601 with explicit timezone; tags are stored on the '
        'record (tag entities sync in a later phase).',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema({
      'title': {'type': 'string', 'minLength': 1},
      'due': {'type': 'string'},
      'priority': {'type': 'integer', 'minimum': 0, 'maximum': 9},
      'description': {'type': ['string', 'null']},
      'tags': {
        'type': 'array',
        'items': {'type': 'string', 'minLength': 1},
      },
      'idempotency_key': {'type': 'string', 'minLength': 1, 'maxLength': 128},
    },
      required: ['title'],
    ),
    handler: (ctx, args) async {
      final title = _requireTitle(args['title'], 'title');
      final due =
          args['due'] == null ? null : parseStrictUtc(args['due'], 'due');
      final now = ctx.now.toUtc();
      final fields = _taskPayloadCreate(
        title: title,
        now: now,
        due: due,
        priority: args['priority'] as int?,
        description: args['description'],
        tags: args['tags'],
      );
      final result = await _writeChecked(
        ctx,
        recordId: newOpId(),
        type: RecordType.todo,
        fields: fields,
        requestArgs: args,
        idempotencyKey: args['idempotency_key'] as String?,
      );
      final created =
          await _findRow(ctx, result.serverRecord!.id, type: 'todo');
      return <String, Object?>{
        'task': taskJson(created!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'update_task',
    description:
        'PATCH a task: only the fields you pass are changed; pass null to clear '
        'due/description. Use complete_task/reopen_task for status.',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema({
      'task_id': _idSchema,
      'title': {'type': 'string', 'minLength': 1},
      'due': {'type': ['string', 'null']},
      'priority': {'type': ['integer', 'null'], 'minimum': 0, 'maximum': 9},
      'description': {'type': ['string', 'null']},
      'tags': {
        'type': ['array', 'null'],
        'items': {'type': 'string', 'minLength': 1},
      },
      'idempotency_key': {'type': 'string', 'minLength': 1, 'maxLength': 128},
    },
      required: ['task_id'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['task_id']! as String,
        type: 'todo',
      );
      final now = ctx.now.toUtc();
      final fields = <String, Object?>{};
      if (args.containsKey('title')) {
        fields['summary'] = _requireTitle(args['title'], 'title');
      }
      if (args.containsKey('due')) {
        fields['dueDate'] = args['due'] == null
            ? null
            : isoZ(parseStrictUtc(args['due'], 'due'));
      }
      if (args.containsKey('priority')) {
        fields['priority'] = args['priority'] ?? 0;
      }
      if (args.containsKey('description')) {
        fields['description'] = args['description'];
      }
      if (args.containsKey('tags')) {
        fields['tags'] = args['tags'];
      }
      if (fields.isEmpty) {
        throw mcpValidation(
          'no updatable fields supplied',
          hint: 'Pass at least one of title, due, priority, description, tags.',
        );
      }
      fields['updatedAt'] = isoZ(now);
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.todo,
        fields: fields,
        requestArgs: args,
        idempotencyKey: args['idempotency_key'] as String?,
      );
      final updated = await _findRow(ctx, row.id, type: 'todo');
      return <String, Object?>{
        'task': taskJson(updated!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'complete_task',
    description: 'Mark a task completed (status COMPLETED, percent 100, completedAt set).',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema(
      {'task_id': _idSchema},
      required: ['task_id'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['task_id']! as String,
        type: 'todo',
      );
      final now = ctx.now.toUtc();
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.todo,
        fields: {
          'status': 'COMPLETED',
          'percentComplete': 100,
          'completedAt': isoZ(now),
          'updatedAt': isoZ(now),
        },
        requestArgs: args,
      );
      final updated = await _findRow(ctx, row.id, type: 'todo');
      return <String, Object?>{
        'task': taskJson(updated!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'reopen_task',
    description: 'Reopen a completed task (status NEEDS-ACTION, percent 0, completedAt cleared).',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema(
      {'task_id': _idSchema},
      required: ['task_id'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['task_id']! as String,
        type: 'todo',
      );
      final now = ctx.now.toUtc();
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.todo,
        fields: {
          'status': 'NEEDS-ACTION',
          'percentComplete': 0,
          'completedAt': null,
          'updatedAt': isoZ(now),
        },
        requestArgs: args,
      );
      final updated = await _findRow(ctx, row.id, type: 'todo');
      return <String, Object?>{
        'task': taskJson(updated!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'snooze_task',
    description:
        'Defer a task to a later instant: moves due to until (ISO 8601 with timezone). '
        'Reminder rows do not sync yet, so the synced due date is the snooze surface.',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema(
      {
        'task_id': _idSchema,
        'until': {'type': 'string'},
      },
      required: ['task_id', 'until'],
    ),
    handler: (ctx, args) async {
      final row = await _requireVisible(
        ctx,
        id: args['task_id']! as String,
        type: 'todo',
      );
      final until = parseStrictUtc(args['until'], 'until');
      final now = ctx.now.toUtc();
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.todo,
        fields: {
          'dueDate': isoZ(until),
          'updatedAt': isoZ(now),
        },
        requestArgs: args,
      );
      final updated = await _findRow(ctx, row.id, type: 'todo');
      return <String, Object?>{
        'task': taskJson(updated!),
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'trash_task',
    description:
        'Move a task to the recycle bin (soft delete via deletedAt — restorable in the app). '
        'Not a permanent delete.',
    readOnly: false,
    destructive: true,
    inputSchema: _objectSchema(
      {'task_id': _idSchema},
      required: ['task_id'],
    ),
    handler: (ctx, args) async {
      final row = await _findRow(
        ctx,
        args['task_id']! as String,
        type: 'todo',
      );
      if (row == null) {
        throw McpToolException(
          mcpCodeTaskNotFound,
          'task not found: ${args['task_id']}',
          hintTaskNotFound,
        );
      }
      if (_trashed(row)) {
        return <String, Object?>{
          'task': taskJson(row),
          'trashed': true,
          'changed': false,
        };
      }
      final now = ctx.now.toUtc();
      final result = await _writeChecked(
        ctx,
        recordId: row.id,
        type: RecordType.todo,
        fields: {
          'deletedAt': isoZ(now),
          'updatedAt': isoZ(now),
        },
        requestArgs: args,
      );
      final updated = await _findRow(ctx, row.id, type: 'todo');
      return <String, Object?>{
        'task': taskJson(updated!),
        'trashed': true,
        'changed': true,
        'op': await _opJson(result),
      };
    },
  ),
  McpTool(
    name: 'batch_create_tasks',
    description:
        'Create many tasks in one call (Todoist-style batch). Each item may carry its own '
        'idempotency_key; schema validation runs before any write.',
    readOnly: false,
    destructive: false,
    inputSchema: _objectSchema({
      'tasks': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 100,
        'items': _objectSchema({
          'title': {'type': 'string', 'minLength': 1},
          'due': {'type': 'string'},
          'priority': {'type': 'integer', 'minimum': 0, 'maximum': 9},
          'description': {'type': ['string', 'null']},
          'tags': {
            'type': 'array',
            'items': {'type': 'string', 'minLength': 1},
          },
          'idempotency_key': {
            'type': 'string',
            'minLength': 1,
            'maxLength': 128,
          },
        }, required: ['title']),
      },
    },
      required: ['tasks'],
    ),
    handler: (ctx, args) async {
      final tasks = (args['tasks']! as List).cast<Map>();
      final results = <Map<String, Object?>>[];
      var created = 0;
      var failed = 0;
      for (var i = 0; i < tasks.length; i++) {
        final item = Map<String, Object?>.from(tasks[i]);
        try {
          final title = _requireTitle(item['title'], 'tasks[$i].title');
          final due = item['due'] == null
              ? null
              : parseStrictUtc(item['due'], 'tasks[$i].due');
          final now = ctx.now.toUtc();
          final result = await _writeChecked(
            ctx,
            recordId: newOpId(),
            type: RecordType.todo,
            fields: _taskPayloadCreate(
              title: title,
              now: now,
              due: due,
              priority: item['priority'] as int?,
              description: item['description'],
              tags: item['tags'],
            ),
            requestArgs: item,
            idempotencyKey: item['idempotency_key'] as String?,
          );
          final row =
              await _findRow(ctx, result.serverRecord!.id, type: 'todo');
          created++;
          results.add(<String, Object?>{
            'index': i,
            'status': result.status.name,
            'task': taskJson(row!),
          });
        } on McpToolException catch (e) {
          failed++;
          results.add(<String, Object?>{
            'index': i,
            'status': 'rejected',
            ...e.toJson(),
          });
        }
      }
      return <String, Object?>{
        'results': results,
        'created': created,
        'failed': failed,
        '_isError': failed > 0,
      };
    },
  ),
];

void _fillSlots(
  List<Map<String, Object?>> slots,
  DateTime gapStart,
  DateTime gapEnd,
  Duration duration,
) {
  if (slots.length >= 10) {
    return;
  }
  if (gapEnd.difference(gapStart) >= duration) {
    slots.add(<String, Object?>{
      'start': isoZ(gapStart),
      'end': isoZ(gapStart.add(duration)),
    });
  }
}
