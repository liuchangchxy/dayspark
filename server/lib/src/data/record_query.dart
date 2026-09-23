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

  final conditions = <String>['user_id = ?'];
  final variables = <Variable>[Variable.withString(userId)];

  if (type != null) {
    conditions.add('type = ?');
    variables.add(Variable.withString(type.name));
  }

  if (!includeTrashed) {
    conditions.add(
      "deleted = 0 AND json_extract(payload_json, '\$.deletedAt') IS NULL",
    );
  }

  if (from != null || to != null) {
    conditions.add(_windowClause(from: from, to: to, variables: variables));
  }

  if (dueOn != null || dueFrom != null || dueTo != null) {
    conditions.add(
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
    conditions.add(
      "(LOWER(CAST(json_extract(payload_json, '\$.summary') AS TEXT)) "
      "LIKE ? ESCAPE '\\' OR "
      "LOWER(CAST(json_extract(payload_json, '\$.description') AS TEXT)) "
      "LIKE ? ESCAPE '\\')",
    );
    variables.add(Variable.withString(pattern));
    variables.add(Variable.withString(pattern));
  }

  if (cursor != null) {
    conditions.add('id > ?');
    variables.add(Variable.withString(cursor));
  }

  final sql = 'SELECT * FROM records WHERE ${conditions.join(' AND ')} '
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

String _iso(DateTime value) => value.toUtc().toIso8601String();

String _windowClause({
  required DateTime? from,
  required DateTime? to,
  required List<Variable> variables,
}) {
  const startRaw = "json_extract(payload_json, '\$.startDt')";
  const startDay = "julianday(json_extract(payload_json, '\$.startDt'))";
  const endDay = "julianday(json_extract(payload_json, '\$.endDt'))";
  const allDay = "json_extract(payload_json, '\$.isAllDay')";
  const isRrule = "COALESCE(json_extract(payload_json, '\$.rrule'), '') != ''";
  // Mirrors effectiveEventEnd in rrule_window.dart: zero-length all-day
  // rows occupy their day, other zero-length rows get a 1h floor.
  final effectiveEnd = '(CASE WHEN $endDay > $startDay THEN $endDay '
      "WHEN $allDay IN (1, 'true') THEN $startDay + 1.0 "
      'ELSE $startDay + 1.0 / 24.0 END)';

  final buffer = StringBuffer();
  buffer.write('$startRaw IS NOT NULL AND $startDay IS NOT NULL AND (');
  if (to != null) {
    buffer.write('($isRrule AND $startDay < julianday(?))');
    buffer.write(' OR (NOT ($isRrule) AND $startDay < julianday(?)');
    if (from != null) {
      buffer.write(' AND $effectiveEnd > julianday(?)');
    }
    buffer.write(')');
    variables.add(Variable.withString(_iso(to)));
    variables.add(Variable.withString(_iso(to)));
    if (from != null) {
      variables.add(Variable.withString(_iso(from)));
    }
  } else {
    buffer.write('($isRrule');
    if (from != null) {
      buffer.write(' OR (NOT ($isRrule) AND $effectiveEnd > julianday(?))');
      variables.add(Variable.withString(_iso(from)));
    }
    buffer.write(')');
  }
  buffer.write(')');
  return buffer.toString();
}

String _dueClause({
  required String? dueOn,
  required DateTime? dueFrom,
  required DateTime? dueTo,
  required String timezone,
  required List<Variable> variables,
}) {
  const dueDay = "julianday(json_extract(payload_json, '\$.dueDate'))";
  const dueRaw = "json_extract(payload_json, '\$.dueDate')";
  final parts = <String>['$dueRaw IS NOT NULL', '$dueDay IS NOT NULL'];
  if (dueOn != null) {
    final (dayStart, dayEnd) = localDayBoundsUtc(dueOn, timezone);
    parts.add('$dueDay >= julianday(?)');
    parts.add('$dueDay < julianday(?)');
    variables.add(Variable.withString(_iso(dayStart)));
    variables.add(Variable.withString(_iso(dayEnd)));
  }
  if (dueFrom != null) {
    parts.add('$dueDay >= julianday(?)');
    variables.add(Variable.withString(_iso(dueFrom)));
  }
  if (dueTo != null) {
    parts.add('$dueDay < julianday(?)');
    variables.add(Variable.withString(_iso(dueTo)));
  }
  return '(${parts.join(' AND ')})';
}
