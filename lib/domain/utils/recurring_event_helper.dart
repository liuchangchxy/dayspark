import 'package:flutter/material.dart';
import 'package:rrule/rrule.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

/// Expands a list of Drift [Event] records into [CalendaEventAdapter] instances.
///
/// Events without an RRULE produce a single adapter. Events with an RRULE
/// are expanded into virtual instances within [range], each sharing the
/// same [drifId] but with shifted [DateTimeRange]s.
List<CalendaEventAdapter> expandRecurringEvents(
  List<Event> events,
  DateTimeRange range, {
  Color? Function(int calendarId)? colorForCalendar,
}) {
  final result = <CalendaEventAdapter>[];

  for (final event in events) {
    final color = colorForCalendar?.call(event.calendarId);

    if (event.rrule == null || event.rrule!.isEmpty) {
      result.add(CalendaEventAdapter.fromDrift(event, calendarColor: color));
      continue;
    }

    // Parse the RRULE and generate instances within range.
    try {
      final rrule = RecurrenceRule.fromString(event.rrule!);
      final duration = event.endDt.difference(event.startDt);
      final instances = rrule.getInstances(
        start: event.startDt.copyWith(isUtc: true),
      );

      final rangeStartUtc = DateTime.utc(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final rangeEndUtc = DateTime.utc(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );

      for (final instance in instances) {
        if (instance.isAfter(rangeEndUtc)) break;
        if (instance.isBefore(rangeStartUtc)) continue;

        result.add(CalendaEventAdapter(
          drifId: event.id,
          calendarId: event.calendarId,
          uid: event.uid,
          title: event.summary,
          start: instance.copyWith(isUtc: false),
          end: instance.add(duration).copyWith(isUtc: false),
          description: event.description,
          location: event.location,
          color: color,
          isAllDay: event.isAllDay,
          rrule: event.rrule,
          isDirty: event.isDirty,
        ));
      }
    } catch (_) {
      // If RRULE parsing fails, fall back to showing the original event.
      result.add(CalendaEventAdapter.fromDrift(event, calendarColor: color));
    }
  }

  return result;
}
