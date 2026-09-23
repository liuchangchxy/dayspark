import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../db.dart';

const int recordQueryDefaultLimit = 50;
const int recordQueryMaxLimit = 200;

// One page of `records` rows ordered by id. The cursor is the id of the last
// delivered row (exclusive lower bound for the next page); null when the
// page ended the result set.
class RecordQueryPage {
  const RecordQueryPage({
    required this.records,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RecordRow> records;
  final String? nextCursor;
  final bool hasMore;
}

// Filter conventions (also the MCP layer's contract):
//
// - Instant windows ([from], [to], [dueFrom], [dueTo]) are UTC instants and
//   are timezone-independent; [to]/[dueTo] are exclusive, [from]/[dueFrom]
//   inclusive.
// - Calendar-date filters ([dueOn], 'YYYY-MM-DD') compute their local-day
//   bounds [00:00, next 00:00) in [timezone] (IANA) when given, else UTC —
//   every date-bucket filter honors this convention.
// - [from]/[to] filter event-shaped rows (payload startDt present): raw
//   records need a half-open [start, end) overlap, rrule masters qualify
//   when DTSTART < to so window expansion can see series that started
//   earlier (expand via rrule_window.dart).
// - [dueOn]/[dueFrom]/[dueTo] require payload dueDate (todos).
// - Soft-deleted rows (tombstone deleted=1 or payload.deletedAt set) are
//   excluded unless [includeTrashed].
// - [search] is a case-insensitive LIKE over summary and description with
//   %, _ and \ escaped literally.
//
// Time fields compare as canonical UTC ISO-8601 strings
// ('...THH:MM:SS.ffffffZ', fraction padded to 6 digits) — exact ordering
// with no floating-point path (julianday's ~73µs double ulp at current
// epochs silently dropped sub-ulp window admissions). Payload datetime
// fields MUST be canonical UTC '...Z' strings (the client's isoOf and any
// Task-2 writer's DateTime.parse(...).toUtc().toIso8601String() both do);
// a payload value that is not 'Z'-terminated normalizes to NULL here and
// falls out of window/due filters instead of being mis-ordered.
Future<RecordQueryPage> queryRecords(
  AppDatabase db, {
  required String userId,
  RecordType? type,
  bool includeTrashed = false,
  DateTime? from,
  DateTime? to,
  String? dueOn,
  DateTime? dueFrom,
  DateTime? dueTo,
  String timezone = 'UTC',
  String? search,
  String? cursor,
  int limit = recordQueryDefaultLimit,
}) async {
  final pageLimit =
      limit < 1 ? 1 : (limit > recordQueryMaxLimit ? recordQueryMaxLimit : limit);

  final base = <String>['user_id = ?'];
  final baseVariables = <Variable>[Variable.withString(userId)];

  if (type != null) {
    base.add('type = ?');
    baseVariables.add(Variable.withString(type.name));
  }

  if (!includeTrashed) {
    base.add(
      "deleted = 0 AND json_extract(payload_json, '\$.deletedAt') IS NULL",
    );
  }

  final outer = <String>[];
  final variables = <Variable>[...baseVariables];

  if (from != null || to != null) {
    final clause = _windowClause(from: from, to: to, variables: variables);
    outer.add(clause);
  }

  if (dueOn != null || dueFrom != null || dueTo != null) {
    outer.add(
      _dueClause(
        dueOn: dueOn,
        dueFrom: dueFrom,
        dueTo: dueTo,
        timezone: timezone,
        variables: variables,
      ),
    );
  }

  if (search != null) {
    final pattern = '%${_escapeLike(search.toLowerCase())}%';
    outer.add(
      "(LOWER(CAST(json_extract(payload_json, '\$.summary') AS TEXT)) "
      "LIKE ? ESCAPE '\\' OR "
      "LOWER(CAST(json_extract(payload_json, '\$.description') AS TEXT)) "
      "LIKE ? ESCAPE '\\')",
    );
    variables.add(Variable.withString(pattern));
    variables.add(Variable.withString(pattern));
  }

  if (cursor != null) {
    outer.add('id > ?');
    variables.add(Variable.withString(cursor));
  }

  final where = outer.isEmpty ? '' : ' WHERE ${outer.join(' AND ')}';
  final sql = 'WITH r AS ('
      'SELECT *, '
      "${_padIso('startDt')} AS _start, "
      "${_padIso('endDt')} AS _end, "
      "${_padIso('dueDate')} AS _due "
      'FROM records WHERE ${base.join(' AND ')}'
      ') SELECT * FROM r$where '
      'ORDER BY id ASC LIMIT ?';
  variables.add(Variable.withInt(pageLimit + 1));

  final rows = await db.customSelect(sql, variables: variables).get();
  final mapped = rows.map((row) => db.records.map(row.data)).toList();
  final hasMore = mapped.length > pageLimit;
  final page = hasMore ? mapped.sublist(0, pageLimit) : mapped;
  return RecordQueryPage(
    records: page,
    nextCursor: hasMore && page.isNotEmpty ? page.last.id : null,
    hasMore: hasMore,
  );
}

// Local-day bounds of a 'YYYY-MM-DD' date in [timezone] (IANA, default via
// the caller) expressed as the half-open UTC instant range
// [00:00, next-day 00:00). DST-safe: both edges are built from calendar
// dates in the zone, never from +24h arithmetic.
(DateTime, DateTime) localDayBoundsUtc(String date, String timezone) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (match == null) {
    throw FormatException('date must be YYYY-MM-DD: $date');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final location = _tzLocation(timezone);
  final start = tz.TZDateTime(location, year, month, day).toUtc();
  final next = DateTime.utc(year, month, day).add(const Duration(days: 1));
  final end =
      tz.TZDateTime(location, next.year, next.month, next.day).toUtc();
  return (start, end);
}

bool _tzDataLoaded = false;

tz.Location _tzLocation(String timezone) {
  if (!_tzDataLoaded) {
    tz.initializeTimeZones();
    _tzDataLoaded = true;
  }
  return tz.getLocation(timezone);
}

String _escapeLike(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

// Canonical UTC ISO-8601 with the fraction pinned to exactly 6 digits so
// lexicographic order == chronological order against _padIso output.
String _canonical(DateTime value) {
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

// SQL-side counterpart of _canonical for payload strings: pad/truncate the
// fraction to 6 digits; NULL for absent values and anything not
// 'Z'-terminated (offset-bearing strings cannot be ordered against UTC by
// lexicographic compare — writers must emit '...Z').
String _padIso(String key) {
  final x = "json_extract(payload_json, '\$.$key')";
  return '(CASE'
      " WHEN $x IS NULL OR substr($x, -1) != 'Z' THEN NULL"
      " WHEN instr($x, '.') = 0 THEN substr($x, 1, length($x) - 1) || '.000000Z'"
      " WHEN length($x) - instr($x, '.') - 1 >= 6 "
      " THEN substr($x, 1, instr($x, '.') + 6) || 'Z'"
      ' ELSE substr($x, 1, length($x) - 1)'
      " || substr('000000', 1, 6 - (length($x) - instr($x, '.') - 1)) || 'Z'"
      ' END)';
}

String _windowClause({
  required DateTime? from,
  required DateTime? to,
  required List<Variable> variables,
}) {
  const isRrule = "COALESCE(json_extract(payload_json, '\$.rrule'), '') != ''";
  final parts = <String>['_start IS NOT NULL'];
  if (to != null) {
    // Both branches need DTSTART/ start < to; instances never start earlier
    // than their master row's startDt.
    parts.add('_start < ?');
    variables.add(Variable.withString(_canonical(to)));
  }
  if (from != null) {
    // Mirrors effectiveEventEnd in rrule_window.dart, in the string domain:
    // positive duration compares the raw end; zero-length all-day rows
    // occupy [start, start+24h) ⇔ start > from−24h; other zero-length rows
    // get the 1h floor ⇔ start > from−1h. String domain cannot add, so the
    // shifted bounds are computed in Dart (µs-exact) instead.
    parts.add(
      '(($isRrule) OR NOT ($isRrule) AND ('
      'CASE WHEN _end > _start THEN _end > ? '
      "WHEN json_extract(payload_json, '\$.isAllDay') IN (1, 'true') "
      'THEN _start > ? '
      'ELSE _start > ? END))',
    );
    variables.add(Variable.withString(_canonical(from)));
    variables.add(
      Variable.withString(_canonical(from.subtract(const Duration(days: 1)))),
    );
    variables.add(
      Variable.withString(_canonical(from.subtract(const Duration(hours: 1)))),
    );
  }
  return parts.join(' AND ');
}

String _dueClause({
  required String? dueOn,
  required DateTime? dueFrom,
  required DateTime? dueTo,
  required String timezone,
  required List<Variable> variables,
}) {
  final parts = <String>['_due IS NOT NULL'];
  if (dueOn != null) {
    final (dayStart, dayEnd) = localDayBoundsUtc(dueOn, timezone);
    parts.add('_due >= ? AND _due < ?');
    variables.add(Variable.withString(_canonical(dayStart)));
    variables.add(Variable.withString(_canonical(dayEnd)));
  }
  if (dueFrom != null) {
    parts.add('_due >= ?');
    variables.add(Variable.withString(_canonical(dueFrom)));
  }
  if (dueTo != null) {
    parts.add('_due < ?');
    variables.add(Variable.withString(_canonical(dueTo)));
  }
  return '(${parts.join(' AND ')})';
}
