import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';

final eventsInDateRangeProvider = StreamProvider.family<List<Event>, String>((
  ref,
  rangeKey,
) {
  final db = ref.watch(databaseProvider);
  // Parse range key: "startMs-endMs"
  final parts = rangeKey.split('-');
  final start = DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0]));
  final end = DateTime.fromMillisecondsSinceEpoch(int.parse(parts[1]));
  final stream = db.eventsDao.watchByDateRange(start, end);
  return stream.timeout(
    const Duration(seconds: 10),
    onTimeout: (sink) => sink.add([]),
  );
});

final calendarsProvider = StreamProvider<List<Calendar>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.calendarsDao.watchAll();
});

final createEventProvider =
    Provider<
      Future<int> Function({
        required int calendarId,
        required String uid,
        required String summary,
        required DateTime startDt,
        required DateTime endDt,
        required bool isAllDay,
        String? description,
        String? location,
        String? rrule,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({
        required calendarId,
        required uid,
        required summary,
        required startDt,
        required endDt,
        required isAllDay,
        description,
        location,
        rrule,
      }) async {
        return db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                calendarId: calendarId,
                uid: uid,
                summary: summary,
                startDt: startDt,
                endDt: endDt,
                isAllDay: Value(isAllDay),
                description: Value(description),
                location: Value(location),
                rrule: Value(rrule),
              ),
            );
      };
    });

final deleteEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  final notifService = ref.read(notificationServiceProvider);
  return (int id) async {
    // Cancel and delete reminders
    final reminders =
        await (db.select(db.reminders)..where(
              (t) => t.parentType.equals('event') & t.parentId.equals(id),
            ))
            .get();
    for (final r in reminders) {
      await notifService.cancel(r.id);
    }
    await (db.delete(
      db.reminders,
    )..where((t) => t.parentType.equals('event') & t.parentId.equals(id))).go();
    // Delete junction table rows
    await (db.delete(db.eventTags)..where((t) => t.eventId.equals(id))).go();
    // Delete attachments
    await (db.delete(
      db.attachments,
    )..where((t) => t.parentType.equals('event') & t.parentId.equals(id))).go();
    // Delete the event itself
    await (db.delete(db.events)..where((t) => t.id.equals(id))).go();
  };
});
