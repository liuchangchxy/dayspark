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
    var end = adapter.end;
    // kalender's visible-range query uses strict overlap (end.isAfter(start));
    // a 0h all-day event at the range's first instant would be dropped, so
    // give it an hour inside its own day (dates() still yields one day).
    if (adapter.isAllDay && !end.isAfter(adapter.start)) {
      end = adapter.start.add(const Duration(hours: 1));
    }
    return KalenderCalendarEvent(
      adapter: adapter,
      // Half-open [start, end): exclusive DTEND must not paint an extra day.
      dateTimeRange: DateTimeRange(start: adapter.start, end: end),
      interaction: canModify
          ? EventInteraction.allowAll()
          : EventInteraction.allowNone(),
      id: '${adapter.drifId}-${adapter.start.toUtc().millisecondsSinceEpoch}',
    );
  }

  // isAllDay (not elapsed duration) decides all-day-bar membership: same-day
  // midnight–midnight and no-DTEND (+1h) events are <24h, and a spring-forward
  // DST day is 23h, so duration alone would misfile them as timed tiles.
  @override
  bool get isMultiDayEvent => adapter.isAllDay || super.isMultiDayEvent;

  // kalender's event widgets skip their setState when layoutEquals passes
  // (default: id/range/interaction only), which would keep stale title/color
  // tiles until the next add/remove/move — content fields must participate.
  @override
  bool layoutEquals(CalendarEvent other) {
    if (other is! KalenderCalendarEvent) return false;
    return super.layoutEquals(other) &&
        other.adapter.title == adapter.title &&
        other.adapter.color == adapter.color &&
        other.adapter.isAllDay == adapter.isAllDay &&
        other.adapter.rrule == adapter.rrule;
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
