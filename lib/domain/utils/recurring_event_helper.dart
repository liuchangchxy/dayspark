import 'package:flutter/material.dart';
import 'package:rrule/rrule.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

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

        result.add(
          CalendaEventAdapter(
            drifId: event.id,
            calendarId: event.calendarId,
            title: event.summary,
            start: instance.copyWith(isUtc: false),
            end: instance.add(duration).copyWith(isUtc: false),
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
