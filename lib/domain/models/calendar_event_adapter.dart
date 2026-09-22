import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart' as drift;

class CalendaEventAdapter {
  final int drifId;
  final int calendarId;
  final String title;
  final String? description;
  final String? location;
  final Color? color;
  final bool isAllDay;
  final String? rrule;
  final DateTime start;
  final DateTime end;

  CalendaEventAdapter({
    required this.drifId,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.location,
    this.color,
    this.isAllDay = false,
    this.rrule,
  });

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

  CalendaEventAdapter copyWithData({
    DateTime? start,
    DateTime? end,
    String? title,
    String? description,
    String? location,
    Color? color,
    bool? isAllDay,
    String? rrule,
  }) {
    return CalendaEventAdapter(
      drifId: drifId,
      calendarId: calendarId,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      description: description ?? this.description,
      location: location ?? this.location,
      color: color ?? this.color,
      isAllDay: isAllDay ?? this.isAllDay,
      rrule: rrule ?? this.rrule,
    );
  }

  drift.EventsCompanion toUpdateCompanion() {
    return drift.EventsCompanion(
      id: Value(drifId),
      calendarId: Value(calendarId),
      summary: Value(title),
      startDt: Value(start),
      endDt: Value(end),
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
          other.end == end);

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
      );
}
