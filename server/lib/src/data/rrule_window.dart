import 'dart:convert';

import 'package:rrule/rrule.dart';

import '../db.dart';

const int windowExpansionCap = 500;

class WindowInstance {
  const WindowInstance({
    required this.master,
    required this.start,
    required this.end,
  });

  final RecordRow master;
  final DateTime start;
  final DateTime end;
}

class WindowExpansion {
  const WindowExpansion({
    required this.instances,
    required this.truncated,
    required this.invalidRruleIds,
  });

  final List<WindowInstance> instances;
  final bool truncated;
  final List<String> invalidRruleIds;
}

// Half-open [from, to) expansion over rows already window-filtered by
// queryRecords: recurring masters (payload.rrule set) generate one instance
// per occurrence overlapping the window, non-recurring rows contribute their
// raw interval when it overlaps. Invalid rrule strings fall back to the raw
// [start, end) overlap and are listed in invalidRruleIds so callers can
// surface degraded recurrence. Total instances are capped (500 by default);
// truncated tells the caller the window held more.
WindowExpansion expandRecordsInWindow(
  Iterable<RecordRow> rows, {
  required DateTime from,
  required DateTime to,
  int cap = windowExpansionCap,
}) {
  final fromUtc = from.toUtc();
  final toUtc = to.toUtc();
  final instances = <WindowInstance>[];
  final invalidRruleIds = <String>[];
  var truncated = false;

  for (final row in rows) {
    if (truncated) {
      break;
    }
    if (row.type != 'event') {
      continue;
    }
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    final start = _parseUtc(payload['startDt']);
    if (start == null || !start.isBefore(toUtc)) {
      continue;
    }
    final isAllDay = payload['isAllDay'] == true;
    final duration =
        effectiveEventEnd(start, _parseUtc(payload['endDt']) ?? start,
                isAllDay: isAllDay)
            .difference(start);

    final rawRrule = payload['rrule'];
    if (rawRrule is! String || rawRrule.isEmpty) {
      if (_overlaps(start, duration, fromUtc, toUtc)) {
        instances.add(
          WindowInstance(master: row, start: start, end: start.add(duration)),
        );
      }
      continue;
    }

    RecurrenceRule rule;
    try {
      rule = RecurrenceRule.fromString(rawRrule);
    } catch (_) {
      invalidRruleIds.add(row.id);
      if (_overlaps(start, duration, fromUtc, toUtc)) {
        instances.add(
          WindowInstance(master: row, start: start, end: start.add(duration)),
        );
      }
      continue;
    }

    // Occurrences run from DTSTART forward, so the search starts at the
    // first instant that could still overlap the window; before=to keeps
    // infinite rules finite.
    final afterBound = fromUtc.subtract(duration);
    final after = afterBound.isBefore(start) ? null : afterBound;
    for (final raw in rule.getInstances(
      start: start,
      after: after,
      before: toUtc,
    )) {
      final instanceStart = raw.toUtc();
      if (!_overlaps(instanceStart, duration, fromUtc, toUtc)) {
        continue;
      }
      if (instances.length >= cap) {
        truncated = true;
        break;
      }
      instances.add(
        WindowInstance(
          master: row,
          start: instanceStart,
          end: instanceStart.add(duration),
        ),
      );
    }
  }

  instances.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.master.id.compareTo(b.master.id);
  });
  return WindowExpansion(
    instances: instances,
    truncated: truncated,
    invalidRruleIds: invalidRruleIds,
  );
}

// Exclusive-end view of a record's raw interval: end wins when it is after
// start, otherwise a zero-length all-day row occupies its day and any other
// zero-length row gets a 1h floor (same S1 guard as the client calendar).
// record_query.dart mirrors this rule in SQL.
DateTime effectiveEventEnd(
  DateTime start,
  DateTime end, {
  required bool isAllDay,
}) {
  if (end.isAfter(start)) {
    return end;
  }
  return isAllDay
      ? start.add(const Duration(days: 1))
      : start.add(const Duration(hours: 1));
}

bool _overlaps(DateTime start, Duration duration, DateTime from, DateTime to) =>
    start.isBefore(to) && start.add(duration).isAfter(from);

DateTime? _parseUtc(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return null;
  }
  return parsed.toUtc();
}
