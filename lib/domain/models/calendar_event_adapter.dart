import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:calendar_todo_app/data/local/database/app_database.dart' as drift;

class CalendaEventAdapter extends CalendarEvent {
  final int drifId;
  final int calendarId;
  final String uid;
  final String title;
  final String? description;
  final String? location;
  final Color? color;
  final bool isAllDay;
  final String? rrule;
  final bool isDirty;

  CalendaEventAdapter({
    required this.drifId,
    required this.calendarId,
    required this.uid,
    required this.title,
    required DateTime start,
    required DateTime end,
    this.description,
    this.location,
    this.color,
    this.isAllDay = false,
    this.rrule,
    this.isDirty = false,
  }) : super(dateTimeRange: DateTimeRange(start: start, end: end));

  factory CalendaEventAdapter.fromDrift(drift.Event e, {Color? calendarColor}) {
    return CalendaEventAdapter(
      drifId: e.id,
      calendarId: e.calendarId,
      uid: e.uid,
      title: e.summary,
      start: e.startDt,
      end: e.endDt,
      description: e.description,
      location: e.location,
      color: calendarColor,
      isAllDay: e.isAllDay,
      rrule: e.rrule,
      isDirty: e.isDirty,
    );
  }

  /// Creates a copy of this adapter with custom fields replaced.
  ///
  /// This is separate from [CalendarEvent.copyWith] which only handles
  /// date-time range changes and is inherited from the base class.
  CalendaEventAdapter copyWithData({
    DateTimeRange? dateTimeRange,
    String? title,
    String? description,
    String? location,
    Color? color,
    bool? isAllDay,
    String? rrule,
    bool? isDirty,
  }) {
    final updated = CalendaEventAdapter(
      drifId: drifId,
      calendarId: calendarId,
      uid: uid,
      title: title ?? this.title,
      start: dateTimeRange?.start ?? this.dateTimeRange.start,
      end: dateTimeRange?.end ?? this.dateTimeRange.end,
      description: description ?? this.description,
      location: location ?? this.location,
      color: color ?? this.color,
      isAllDay: isAllDay ?? this.isAllDay,
      rrule: rrule ?? this.rrule,
      isDirty: isDirty ?? this.isDirty,
    );
    updated.id = id;
    return updated;
  }

  drift.EventsCompanion toCreateCompanion() {
    return drift.EventsCompanion.insert(
      calendarId: calendarId,
      uid: uid,
      summary: title,
      startDt: dateTimeRange.start,
      endDt: dateTimeRange.end,
      isAllDay: Value(isAllDay),
      description: Value(description),
      location: Value(location),
      rrule: Value(rrule),
    );
  }

  drift.EventsCompanion toUpdateCompanion() {
    return drift.EventsCompanion(
      id: Value(drifId),
      calendarId: Value(calendarId),
      uid: Value(uid),
      summary: Value(title),
      startDt: Value(dateTimeRange.start),
      endDt: Value(dateTimeRange.end),
      isAllDay: Value(isAllDay),
      description: Value(description),
      location: Value(location),
      rrule: Value(rrule),
      isDirty: Value(true),
      updatedAt: Value(DateTime.now()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (super == other &&
          other is CalendaEventAdapter &&
          other.drifId == drifId &&
          other.title == title &&
          other.description == description &&
          other.color == color &&
          other.isAllDay == isAllDay);

  @override
  int get hashCode =>
      Object.hash(super.hashCode, drifId, title, description, color, isAllDay);
}
