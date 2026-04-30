import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart' as drift;

class CalendaEventAdapter {
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
  final DateTime start;
  final DateTime end;

  CalendaEventAdapter({
    required this.drifId,
    required this.calendarId,
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.location,
    this.color,
    this.isAllDay = false,
    this.rrule,
    this.isDirty = false,
  });

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

  CalendaEventAdapter copyWithData({
    DateTime? start,
    DateTime? end,
    String? title,
    String? description,
    String? location,
    Color? color,
    bool? isAllDay,
    String? rrule,
    bool? isDirty,
  }) {
    return CalendaEventAdapter(
      drifId: drifId,
      calendarId: calendarId,
      uid: uid,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      description: description ?? this.description,
      location: location ?? this.location,
      color: color ?? this.color,
      isAllDay: isAllDay ?? this.isAllDay,
      rrule: rrule ?? this.rrule,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  drift.EventsCompanion toCreateCompanion() {
    return drift.EventsCompanion.insert(
      calendarId: calendarId,
      uid: uid,
      summary: title,
      startDt: start,
      endDt: end,
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
      startDt: Value(start),
      endDt: Value(end),
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
      (other is CalendaEventAdapter &&
          other.drifId == drifId &&
          other.title == title &&
          other.description == description &&
          other.color == color &&
          other.isAllDay == isAllDay);

  @override
  int get hashCode => Object.hash(drifId, title, description, color, isAllDay);
}
