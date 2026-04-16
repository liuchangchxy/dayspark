import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/domain/providers/database_provider.dart';

final eventsInDateRangeProvider =
    StreamProvider.family<List<Event>, DateTimeRange>(
  (ref, range) {
    final db = ref.watch(databaseProvider);
    return db.eventsDao.watchByDateRange(range.start, range.end);
  },
);

final calendarsProvider = StreamProvider<List<Calendar>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.calendarsDao.watchAll();
});

final createEventProvider = Provider<Future<int> Function({
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime startDt,
  required DateTime endDt,
  required bool isAllDay,
  String? description,
  String? location,
})>((ref) {
  final db = ref.watch(databaseProvider);
  return ({
    required calendarId,
    required uid,
    required summary,
    required startDt,
    required endDt,
    required isAllDay,
    description,
    location,
  }) async {
    return db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            uid: uid,
            summary: summary,
            startDt: startDt,
            endDt: endDt,
            isAllDay: Value(isAllDay),
            description: Value(description),
            location: Value(location),
          ),
        );
  };
});

final deleteEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  return (int id) async {
    await (db.delete(db.events)..where((t) => t.id.equals(id))).go();
  };
});
