import 'package:flutter/material.dart';
import 'package:rrule/rrule.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

/// The instants an EXDATE column excludes, one ISO-8601 value per line.
///
/// Stored as text on the event row so the exception travels with the record
/// through sync, backup and iCal without a second entity to reconcile. Bad
/// lines are dropped rather than failing the whole series.
/// Always a fresh, mutable set: callers that add an exclusion (EXDATE) must not
/// hit the empty constant, which is unmodifiable.
Set<DateTime> parseExdates(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <DateTime>{};
  final result = <DateTime>{};
  for (final line in raw.split('\n')) {
    final value = DateTime.tryParse(line.trim());
    if (value != null) result.add(value);
  }
  return result;
}

String encodeExdates(Iterable<DateTime> values) =>
    values.map((value) => value.toIso8601String()).join('\n');

/// True when [instant] is one of the series' excluded occurrences.
///
/// Compared to the second, because the stored anchors and the expanded
/// instances are produced by different code paths and can differ by
/// sub-second noise.
bool isExcludedOccurrence(Set<DateTime> exdates, DateTime instant) {
  for (final excluded in exdates) {
    if (excluded.year == instant.year &&
        excluded.month == instant.month &&
        excluded.day == instant.day &&
        excluded.hour == instant.hour &&
        excluded.minute == instant.minute) {
      return true;
    }
  }
  return false;
}

/// Expands a list of Drift [Event] records into [CalendaEventAdapter] instances.
///
/// Events without an RRULE produce a single adapter. Events with an RRULE
/// are expanded into virtual instances inside the [before, after] visible
/// window, each sharing the same [drifId] but with shifted [DateTimeRange]s.
List<CalendaEventAdapter> expandRecurringEvents(
  List<Event> events, {
  required DateTime before,
  required DateTime after,
  Color? Function(int calendarId)? colorForCalendar,
}) {
  final result = <CalendaEventAdapter>[];

  for (final event in events) {
    final color = colorForCalendar?.call(event.calendarId);

    if (event.rrule == null || event.rrule!.isEmpty) {
      result.add(CalendaEventAdapter.fromDrift(event, calendarColor: color));
      continue;
    }

    final exdates = parseExdates(event.exdates);

    // Parse the RRULE and generate instances within the visible window only.
    try {
      final rrule = RecurrenceRule.fromString(event.rrule!);
      final duration = event.endDt.difference(event.startDt);
      final instances = rrule.getInstances(
        start: event.startDt.copyWith(isUtc: true),
      );

      final windowStartUtc = DateTime.utc(
        before.year,
        before.month,
        before.day,
      );
      final windowEndUtc = DateTime.utc(
        after.year,
        after.month,
        after.day,
        23,
        59,
        59,
      );

      for (final instance in instances) {
        if (instance.isAfter(windowEndUtc)) break;
        if (instance.isBefore(windowStartUtc)) continue;

        final occurrenceStart = instance.copyWith(isUtc: false);
        if (isExcludedOccurrence(exdates, occurrenceStart)) continue;
        result.add(
          CalendaEventAdapter(
            drifId: event.id,
            calendarId: event.calendarId,
            title: event.summary,
            start: occurrenceStart,
            end: instance.add(duration).copyWith(isUtc: false),
            // The series anchor travels with every occurrence: the tile draws
            // the occurrence, but a write has to land on the row's DTSTART.
            seriesStart: event.startDt,
            seriesEnd: event.endDt,
            occurrenceStart: occurrenceStart,
            description: event.description,
            location: event.location,
            color: color,
            isAllDay: event.isAllDay,
            rrule: event.rrule,
          ),
        );
      }
    } catch (e) {
      debugPrint('recurring_helper: RRULE error: $e');
      // If RRULE parsing fails, fall back to showing the original event.
      result.add(CalendaEventAdapter.fromDrift(event, calendarColor: color));
    }
  }

  return result;
}
