import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

class KalenderCalendarEvent extends CalendarEvent {
  final CalendaEventAdapter adapter;

  KalenderCalendarEvent({
    required this.adapter,
    required super.dateTimeRange,
    required super.interaction,
    required super.id,
  });

  factory KalenderCalendarEvent.fromAdapter(CalendaEventAdapter adapter) {
    // S1 guard: dragging/resizing a recurring or all-day instance would write
    // back to the shared drift row and corrupt the whole series.
    final canModify = adapter.rrule == null && !adapter.isAllDay;
    return KalenderCalendarEvent(
      adapter: adapter,
      // Half-open [start, end): exclusive DTEND must not paint an extra day.
      dateTimeRange: DateTimeRange(start: adapter.start, end: adapter.end),
      interaction: canModify
          ? EventInteraction.allowAll()
          : EventInteraction.allowNone(),
      id: '${adapter.drifId}-${adapter.start.toUtc().millisecondsSinceEpoch}',
    );
  }

  @override
  KalenderCalendarEvent copyWith({
    DateTimeRange? dateTimeRange,
    EventInteraction? interaction,
  }) {
    return KalenderCalendarEvent(
      adapter: adapter,
      dateTimeRange: dateTimeRange ?? this.dateTimeRange,
      interaction: interaction ?? this.interaction,
      id: id,
    );
  }
}
