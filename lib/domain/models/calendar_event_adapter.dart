import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart' as drift;

/// Sentinel for [CalendaEventAdapter.copyWithData]'s nullable text fields.
///
/// `description ?? this.description` cannot tell "leave it alone" from "clear
/// it", so passing null used to silently keep the old value and clearing an
/// event's description or location was impossible.
const Object _unset = Object();

class CalendaEventAdapter {
  final int drifId;
  final int calendarId;
  final String title;
  final String? description;
  final String? location;
  final Color? color;
  final bool isAllDay;
  final String? rrule;

  /// The occurrence's own start as rendered by the calendar. Equal to
  /// [seriesStart] for the series row itself.
  final DateTime start;
  final DateTime end;

  /// The database row's DTSTART/DTEND. Writes always target these, so a
  /// virtual occurrence can never relocate its series by accident.
  final DateTime seriesStart;
  final DateTime seriesEnd;

  /// Non-null only when this adapter is a virtual occurrence produced by
  /// [expandRecurringEvents]; holds the occurrence's own start.
  final DateTime? occurrenceStart;

  CalendaEventAdapter({
    required this.drifId,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    DateTime? seriesStart,
    DateTime? seriesEnd,
    this.occurrenceStart,
    this.description,
    this.location,
    this.color,
    this.isAllDay = false,
    this.rrule,
  }) : seriesStart = seriesStart ?? start,
       seriesEnd = seriesEnd ?? end;

  /// True when this adapter is one expanded instance of a recurring series
  /// rather than the series row itself.
  bool get isRecurringOccurrence => occurrenceStart != null;

  factory CalendaEventAdapter.fromDrift(drift.Event e, {Color? calendarColor}) {
    return CalendaEventAdapter(
      drifId: e.id,
      calendarId: e.calendarId,
      title: e.summary,
      start: e.startDt,
      end: e.endDt,
      description: e.description,
      location: e.location,
      color: calendarColor,
      isAllDay: e.isAllDay,
      rrule: e.rrule,
    );
  }

  /// Copies with the given fields replaced.
  ///
  /// [seriesStart]/[seriesEnd] move the stored anchor. They default to the new
  /// display times for a plain event (so drag-to-reschedule keeps working
  /// unchanged) but are left untouched for a virtual occurrence — moving an
  /// occurrence's anchor has to be asked for by name.
  CalendaEventAdapter copyWithData({
    int? calendarId,
    DateTime? start,
    DateTime? end,
    DateTime? seriesStart,
    DateTime? seriesEnd,
    String? title,
    Object? description = _unset,
    Object? location = _unset,
    Object? color = _unset,
    bool? isAllDay,
    Object? rrule = _unset,
  }) {
    final nextStart = start ?? this.start;
    final nextEnd = end ?? this.end;
    final keepsAnchor = occurrenceStart != null;
    final nextSeriesStart =
        seriesStart ?? (keepsAnchor ? this.seriesStart : nextStart);
    final nextSeriesEnd = seriesEnd ?? (keepsAnchor ? this.seriesEnd : nextEnd);
    return CalendaEventAdapter(
      drifId: drifId,
      calendarId: calendarId ?? this.calendarId,
      title: title ?? this.title,
      // A plain adapter has no position of its own to keep: start/end and the
      // anchor are one value, so naming either moves both and the two can
      // never drift apart. An occurrence keeps them apart on purpose.
      start: keepsAnchor ? nextStart : nextSeriesStart,
      end: keepsAnchor ? nextEnd : nextSeriesEnd,
      seriesStart: nextSeriesStart,
      seriesEnd: nextSeriesEnd,
      occurrenceStart: occurrenceStart,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      location: identical(location, _unset)
          ? this.location
          : location as String?,
      color: identical(color, _unset) ? this.color : color as Color?,
      isAllDay: isAllDay ?? this.isAllDay,
      rrule: identical(rrule, _unset) ? this.rrule : rrule as String?,
    );
  }

  /// The update companion for the stored row. Times come from the series
  /// anchor, never from the rendered occurrence.
  drift.EventsCompanion toUpdateCompanion() {
    return drift.EventsCompanion(
      id: Value(drifId),
      calendarId: Value(calendarId),
      summary: Value(title),
      startDt: Value(seriesStart),
      endDt: Value(seriesEnd),
      isAllDay: Value(isAllDay),
      description: Value(description),
      location: Value(location),
      rrule: Value(rrule),
      updatedAt: Value(DateTime.now()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendaEventAdapter &&
          other.drifId == drifId &&
          other.calendarId == calendarId &&
          other.title == title &&
          other.description == description &&
          other.location == location &&
          other.color == color &&
          other.isAllDay == isAllDay &&
          other.rrule == rrule &&
          other.start == start &&
          other.end == end &&
          other.seriesStart == seriesStart &&
          other.seriesEnd == seriesEnd &&
          other.occurrenceStart == occurrenceStart);

  @override
  int get hashCode => Object.hash(
    drifId,
    calendarId,
    title,
    description,
    location,
    color,
    isAllDay,
    rrule,
    start,
    end,
    seriesStart,
    seriesEnd,
    occurrenceStart,
  );
}
