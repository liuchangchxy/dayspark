import 'dart:convert';
import 'dart:io';

import 'package:rrule/rrule.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// MCP layer constants, error codes, validation helpers and the small JSON
// Schema validator that backs every tools/call argument check. Business
// failures always surface as tool results ({code, message, hint} inside
// content text with isError:true) — JSON-RPC errors are reserved for
// protocol violations in endpoint.dart.

// Reported as serverInfo.version in initialize. Must track pubspec.yaml's
// major.minor.patch - enforced by tool/check_version_consistency.sh.
const String mcpServerVersion = '0.25.0';
const String mcpLatestProtocolVersion = '2025-06-18';
const List<String> mcpSupportedProtocolVersions = [
  '2024-11-05',
  '2025-03-26',
  '2025-06-18',
];

const String mcpCodeValidation = 'VALIDATION';
const String mcpCodeWindowTooLarge = 'WINDOW_TOO_LARGE';
const String mcpCodeEventNotFound = 'EVENT_NOT_FOUND';
const String mcpCodeTaskNotFound = 'TASK_NOT_FOUND';
const String mcpCodeResourceNotFound = 'RESOURCE_NOT_FOUND';
const String mcpCodeForbiddenScope = 'FORBIDDEN_SCOPE';
const String mcpCodeUnknownTool = 'UNKNOWN_TOOL';
const String mcpCodeWriteRejected = 'WRITE_REJECTED';
const String mcpCodeWriteConflict = 'WRITE_CONFLICT';
const String mcpCodeInternal = 'INTERNAL';

const String mcpScopeRead = 'mcp:read';
const String mcpScopeWrite = 'mcp:write';
const String mcpScopeFull = '$mcpScopeRead $mcpScopeWrite';
const List<String> mcpSupportedScopes = [mcpScopeRead, mcpScopeWrite];

const String hintValidation =
    'Fix the highlighted argument and retry the same tool call.';
const String hintWindowTooLarge =
    'Narrow the window to at most 366 days or lower the limit.';
const String hintEventNotFound =
    'No visible event with that id — list windows with get_events or browse trash with list_trash(kind: event).';
const String hintTaskNotFound =
    'No visible task with that id — find it with list_tasks or browse trash with list_trash(kind: task).';
const String hintForbiddenScope =
    'Obtain an access token whose scope covers this operation (mcp:read / mcp:write) and retry.';
const String hintUnknownTool =
    'Call tools/list to see the available tools and their schemas.';
const String hintDatetime =
    'include timezone offset or Z — e.g. 2026-09-23T10:00:00+08:00 or 2026-09-23T02:00:00Z.';
const String hintIana =
    'Use a valid IANA timezone name such as Asia/Shanghai or America/New_York.';
const String hintStructuredRrule =
    'Pass a structured object {freq, interval?, until?, byday?...} instead of an RFC 5545 string.';
const String hintIdempotencyReuse =
    'idempotency_key was already used with a different request body — use a fresh key for a new write, or resend the identical body to replay.';

class McpToolException implements Exception {
  McpToolException(this.code, this.message, this.hint);

  final String code;
  final String message;
  final String hint;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'message': message,
        'hint': hint,
      };

  @override
  String toString() => 'McpToolException($code): $message';
}

McpToolException mcpValidation(
  String message, {
  String hint = hintValidation,
}) =>
    McpToolException(mcpCodeValidation, message, hint);

String defaultHint(String code) => switch (code) {
      mcpCodeWindowTooLarge => hintWindowTooLarge,
      mcpCodeEventNotFound => hintEventNotFound,
      mcpCodeTaskNotFound => hintTaskNotFound,
      mcpCodeForbiddenScope => hintForbiddenScope,
      mcpCodeUnknownTool => hintUnknownTool,
      _ => hintValidation,
    };

// Canonical fixed-width UTC ISO-8601 ('...THH:MM:SS.ffffffZ'). Every MCP
// output datetime and every payload datetime this writer emits uses it —
// record_query.dart orders window/due fields by lexicographic compare on
// exactly this shape, and non-'Z' strings drop out of those filters.
String isoZ(DateTime value) {
  final s = value.toUtc().toIso8601String();
  if (!s.endsWith('Z')) {
    return s;
  }
  final body = s.substring(0, s.length - 1);
  final dot = body.indexOf('.');
  if (dot < 0) {
    return '$body.000000Z';
  }
  final digits = body.length - dot - 1;
  if (digits == 6) {
    return s;
  }
  if (digits > 6) {
    return '${body.substring(0, dot + 7)}Z';
  }
  return '$body${'0' * (6 - digits)}Z';
}

// Strict ISO 8601 with an explicit zone: naive wall-time strings
// ('2026-09-23T10:00:00') are rejected at the tool boundary so no
// timezone-less datetime can ever reach the payload or the query layer.
DateTime parseStrictUtc(Object? raw, String field) {
  if (raw is! String || !_isoWithZone.hasMatch(raw)) {
    throw mcpValidation(
      '$field must be an ISO 8601 datetime with an explicit timezone',
      hint: hintDatetime,
    );
  }
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    throw mcpValidation(
      '$field must be an ISO 8601 datetime with an explicit timezone',
      hint: hintDatetime,
    );
  }
}

final RegExp _isoWithZone = RegExp(
  r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?'
  r'(Z|z|[+-]\d{2}:\d{2})$',
);

bool _tzLoaded = false;

void _ensureTz() {
  if (!_tzLoaded) {
    tzdata.initializeTimeZones();
    _tzLoaded = true;
  }
}

String parseIanaZone(Object? raw, String field) {
  if (raw is! String || raw.isEmpty) {
    throw mcpValidation(
      '$field must be a non-empty IANA timezone name',
      hint: hintIana,
    );
  }
  _ensureTz();
  try {
    tz.getLocation(raw);
  } on Exception {
    throw mcpValidation(
      '$field is not a known IANA timezone: $raw',
      hint: hintIana,
    );
  }
  return raw;
}

tz.Location ianaLocation(String timezone) {
  _ensureTz();
  return tz.getLocation(timezone);
}

// Structured recurrence object → RFC 5545 string for the payload. Bare
// strings are rejected (MCP hard rule: RRULE is always structured); the
// serialization itself goes through the rrule lib so parse round-trips.
String parseRruleStructured(Object? raw, String field) {
  if (raw is String) {
    throw mcpValidation(
      '$field must be a structured recurrence object, not an RFC 5545 string',
      hint: hintStructuredRrule,
    );
  }
  if (raw is! Map) {
    throw mcpValidation(
      '$field must be an object like {"freq": "WEEKLY", "interval": 1}',
      hint: hintStructuredRrule,
    );
  }
  final map = Map<String, dynamic>.from(raw);
  const allowed = {
    'freq',
    'interval',
    'until',
    'count',
    'byday',
    'bymonthday',
    'bymonth',
    'byhour',
    'byminute',
    'bysecond',
    'bysetpos',
  };
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw mcpValidation(
        '$field.$key is not a supported recurrence part',
        hint: 'Supported parts: ${allowed.join(', ')}.',
      );
    }
  }
  final freqRaw = map['freq'];
  if (freqRaw is! String) {
    throw mcpValidation(
      '$field.freq must be a string such as "WEEKLY"',
      hint: hintStructuredRrule,
    );
  }
  final freq = switch (freqRaw.toUpperCase()) {
    'SECONDLY' => Frequency.secondly,
    'MINUTELY' => Frequency.minutely,
    'HOURLY' => Frequency.hourly,
    'DAILY' => Frequency.daily,
    'WEEKLY' => Frequency.weekly,
    'MONTHLY' => Frequency.monthly,
    'YEARLY' => Frequency.yearly,
    _ => throw mcpValidation(
        '$field.freq "$freqRaw" is not a valid recurrence frequency',
        hint:
            'Use one of SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY.',
      ),
  };

  int? optionalInt(String key, {int? min, int? max}) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw mcpValidation('$field.$key must be an integer');
    }
    if (min != null && value < min) {
      throw mcpValidation('$field.$key must be >= $min');
    }
    if (max != null && value > max) {
      throw mcpValidation('$field.$key must be <= $max');
    }
    return value;
  }

  List<int> intList(
    String key, {
    int min = -366,
    int max = 366,
    bool nonZero = false,
  }) {
    final value = map[key];
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw mcpValidation('$field.$key must be an array of integers');
    }
    return value.map((rawItem) {
      if (rawItem is! int) {
        throw mcpValidation('$field.$key must contain integers only');
      }
      if (rawItem < min || rawItem > max) {
        throw mcpValidation(
          '$field.$key values must be between $min and $max',
        );
      }
      if (nonZero && rawItem == 0) {
        throw mcpValidation('$field.$key values must not be 0');
      }
      return rawItem;
    }).toList();
  }

  final interval = optionalInt('interval', min: 1);
  final count = optionalInt('count', min: 1);
  DateTime? until;
  if (map['until'] != null) {
    until = parseStrictUtc(map['until'], '$field.until');
  }
  if (until != null && count != null) {
    throw mcpValidation(
      '$field must not set both until and count '
      '(RFC 5545: UNTIL and COUNT are mutually exclusive)',
    );
  }

  final bydayRaw = map['byday'];
  final byWeekDays = <ByWeekDayEntry>[];
  if (bydayRaw != null) {
    if (bydayRaw is! List) {
      throw mcpValidation('$field.byday must be an array of day codes');
    }
    final dayPattern = RegExp(
      r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$',
      caseSensitive: false,
    );
    for (final entry in bydayRaw) {
      if (entry is! String) {
        throw mcpValidation(
          '$field.byday entries must be strings like "MO"',
        );
      }
      final match = dayPattern.firstMatch(entry);
      if (match == null) {
        throw mcpValidation(
          '$field.byday entry "$entry" is invalid',
          hint: 'Use weekday codes MO..SU, optionally with an ordinal '
              'such as "2FR".',
        );
      }
      final ordinal =
          match.group(1) == null ? null : int.parse(match.group(1)!);
      if (ordinal != null &&
          freq != Frequency.monthly &&
          freq != Frequency.yearly) {
        throw mcpValidation(
          '$field.byday ordinal is only allowed with MONTHLY or YEARLY',
          hint: 'Drop the numeric prefix (use "FR" not "2FR") '
              'for $freqRaw rules.',
        );
      }
      final dayCode = match.group(2)!.toUpperCase();
      const dayNumbers = {
        'MO': DateTime.monday,
        'TU': DateTime.tuesday,
        'WE': DateTime.wednesday,
        'TH': DateTime.thursday,
        'FR': DateTime.friday,
        'SA': DateTime.saturday,
        'SU': DateTime.sunday,
      };
      byWeekDays.add(ByWeekDayEntry(dayNumbers[dayCode]!, ordinal));
    }
  }

  try {
    final rule = RecurrenceRule(
      frequency: freq,
      until: until,
      count: count,
      interval: interval,
      byWeekDays: byWeekDays,
      byMonthDays: intList('bymonthday', min: -31, max: 31, nonZero: true),
      byMonths: intList('bymonth', min: 1, max: 12),
      byHours: intList('byhour', min: 0, max: 23),
      byMinutes: intList('byminute', min: 0, max: 59),
      bySeconds: intList('bysecond', min: 0, max: 59),
      bySetPositions: intList('bysetpos', nonZero: true),
    );
    return rule.toString();
  } on McpToolException {
    rethrow;
  } catch (e) {
    stderr.writeln('mcp: recurrence parse failed for $field: $e');
    throw mcpValidation(
      '$field is not a valid recurrence combination',
      hint: 'Check that each BY* part is legal for the chosen freq.',
    );
  }
}

Map<String, Object?> recurrenceSchema() => <String, Object?>{
      // No top-level `type`: a bare RFC 5545 string must reach the handler
      // so it can be rejected with the structured-object hint instead of a
      // generic schema type error.
      'additionalProperties': false,
      'required': ['freq'],
      'description':
          'Structured recurrence object (freq, interval, until, byday...); '
          'serialized to RFC 5545 for storage. Bare RFC strings are rejected.',
      'properties': <String, Object?>{
        'freq': {
          'type': 'string',
          'enum': [
            'SECONDLY',
            'MINUTELY',
            'HOURLY',
            'DAILY',
            'WEEKLY',
            'MONTHLY',
            'YEARLY',
          ],
        },
        'interval': {'type': 'integer', 'minimum': 1},
        'until': {'type': 'string'},
        'count': {'type': 'integer', 'minimum': 1},
        'byday': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'bymonthday': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': -31, 'maximum': 31},
        },
        'bymonth': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': 1, 'maximum': 12},
        },
        'byhour': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': 0, 'maximum': 23},
        },
        'byminute': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': 0, 'maximum': 59},
        },
        'bysecond': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': 0, 'maximum': 59},
        },
        'bysetpos': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': -366, 'maximum': 366},
        },
      },
    };

// Minimal JSON Schema validator covering the subset the frozen tool schemas
// use: type (incl. unions), properties/required/additionalProperties, enum,
// items, minimum/maximum, minLength/maxLength, minItems/maxItems. Failures
// throw VALIDATION with the offending path so hints can steer the retry.
void validateAgainstSchema(
  Map<String, Object?> schema,
  Object? value, [
  String path = 'arguments',
]) {
  final type = schema['type'];
  if (type != null) {
    _checkType(type, value, path);
  }
  final enumValues = schema['enum'];
  if (enumValues is List) {
    if (!enumValues.contains(value)) {
      throw mcpValidation(
        '$path must be one of: ${enumValues.join(', ')}',
      );
    }
  }
  if (value is Map) {
    final rawProperties = schema['properties'];
    final properties = rawProperties is Map
        ? rawProperties.map((k, v) => MapEntry(k.toString(), v))
        : <String, Object?>{};
    final rawRequired = schema['required'];
    final required = rawRequired is List
        ? rawRequired.map((e) => e.toString()).toList()
        : const <String>[];
    for (final key in required) {
      if (!value.containsKey(key)) {
        throw mcpValidation(
          '$path: missing required property "$key"',
          hint: 'Provide "$key" as documented in the tool inputSchema.',
        );
      }
    }
    if (schema['additionalProperties'] == false) {
      for (final key in value.keys) {
        if (!properties.containsKey(key.toString())) {
          throw mcpValidation(
            '$path.$key is not an accepted argument',
            hint: 'Remove "$key"; allowed arguments: '
                '${properties.keys.join(', ')}.',
          );
        }
      }
    }
    for (final entry in value.entries) {
      final propSchema = properties[entry.key];
      if (propSchema is Map) {
        validateAgainstSchema(
          Map<String, Object?>.from(propSchema),
          entry.value,
          '$path.${entry.key}',
        );
      }
    }
  }
  if (value is List) {
    final items = schema['items'];
    final minItems = schema['minItems'];
    if (minItems is int && value.length < minItems) {
      throw mcpValidation('$path must contain at least $minItems item(s)');
    }
    final maxItems = schema['maxItems'];
    if (maxItems is int && value.length > maxItems) {
      throw mcpValidation('$path must contain at most $maxItems item(s)');
    }
    if (items is Map) {
      for (var i = 0; i < value.length; i++) {
        validateAgainstSchema(
          Map<String, Object?>.from(items),
          value[i],
          '$path[$i]',
        );
      }
    }
  }
  if (value is num) {
    final minimum = schema['minimum'];
    if (minimum is num && value < minimum) {
      throw mcpValidation('$path must be >= $minimum');
    }
    final maximum = schema['maximum'];
    if (maximum is num && value > maximum) {
      throw mcpValidation('$path must be <= $maximum');
    }
  }
  if (value is String) {
    final minLength = schema['minLength'];
    if (minLength is int && value.length < minLength) {
      throw mcpValidation(
        minLength == 0
            ? '$path must not be empty'
            : '$path must be at least $minLength character(s)',
      );
    }
    final maxLength = schema['maxLength'];
    if (maxLength is int && value.length > maxLength) {
      throw mcpValidation('$path must be at most $maxLength character(s)');
    }
  }
}

void _checkType(Object type, Object? value, String path) {
  final names =
      type is List ? type.map((e) => e.toString()) : [type.toString()];
  final matched = names.any((name) => _matchesSingleType(name, value));
  if (!matched) {
    throw mcpValidation('$path must be of type ${names.join(' or ')}');
  }
}

bool _matchesSingleType(String name, Object? value) => switch (name) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      'null' => value == null,
      _ => true,
    };

// Per-process idempotency_key → request fingerprint registry. A replay with
// the identical body flows into applyInternalOp (which returns the stored
// first verdict); the same key with a different body is rejected before any
// write. Process-local by design — sync_ops stores results, not requests.
class IdempotencyRegistry {
  static const int maxEntries = 4096;

  final Map<String, String> _fingerprints = <String, String>{};

  String key(String userId, String opId) => '$userId $opId';

  void record(String userId, String opId, String fingerprint) {
    final mapKey = key(userId, opId);
    if (_fingerprints.containsKey(mapKey)) {
      return;
    }
    if (_fingerprints.length >= maxEntries) {
      _fingerprints.remove(_fingerprints.keys.first);
    }
    _fingerprints[mapKey] = fingerprint;
  }

  bool contains(String userId, String opId) =>
      _fingerprints.containsKey(key(userId, opId));

  bool matches(String userId, String opId, String fingerprint) =>
      _fingerprints[key(userId, opId)] == fingerprint;
}

// Key-order-independent JSON for fingerprint comparison.
String stableJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${stableJson(value[k])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(stableJson).join(',')}]';
  }
  return jsonEncode(value);
}
