import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/event_writer.dart';

// Static range key ("startMs-endMs") is part of the provider contract
// (docs/CONSTRAINTS.md); autoDispose only releases unused instances.
final eventsInDateRangeProvider =
    StreamProvider.autoDispose.family<List<Event>, String>((ref, rangeKey) {
      final db = ref.watch(databaseProvider);
      // Parse range key: "startMs-endMs"
      final parts = rangeKey.split('-');
      final startMs = int.tryParse(parts[0]);
      final endMs = int.tryParse(parts.length > 1 ? parts[1] : '');
      if (startMs == null || endMs == null) {
        return Stream.value([]);
      }
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final end = DateTime.fromMillisecondsSinceEpoch(endMs);
      final stream = db.eventsDao.watchByDateRange(start, end);
      return stream;
    });

final calendarsProvider = StreamProvider<List<Calendar>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.calendarsDao.watchAll();
});

final createEventProvider =
    Provider<
      Future<int> Function({
        required int calendarId,
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
        required summary,
        required startDt,
        required endDt,
        required isAllDay,
        description,
        location,
        rrule,
      }) {
        // Row insert and outbox op share one transaction: either both
        // commit or neither does (SyncOutbox.enqueue seam).
        return RecordScope.run(
          db,
          (tx) => EventWriter.create(
            db,
            tx,
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: summary,
              startDt: startDt,
              endDt: endDt,
              isAllDay: Value(isAllDay),
              description: Value(description),
              location: Value(location),
              rrule: Value(rrule),
            ),
          ),
        );
      };
    });

final updateEventProvider =
    Provider<Future<void> Function(int id, EventsCompanion data)>((ref) {
      final db = ref.read(databaseProvider);
      return (int id, EventsCompanion data) =>
          RecordScope.run(db, (tx) => EventWriter.update(db, tx, id, data));
    });

final deleteEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) =>
      RecordScope.run(db, (tx) => EventWriter.softDelete(db, tx, id));
});

final deletedEventsProvider = StreamProvider<List<Event>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.eventsDao.watchDeletedEvents();
});

final restoreEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) =>
      RecordScope.run(db, (tx) => EventWriter.restore(db, tx, id));
});

final hardDeleteEventWithChildrenProvider =
    Provider<Future<void> Function(int)>((ref) {
      final db = ref.read(databaseProvider);
      return (int id) => RecordScope.run(
        db,
        (tx) => EventWriter.hardDeleteWithChildren(db, tx, id),
      );
    });

final emptyEventTrashProvider = Provider<Future<void> Function()>((ref) {
  final db = ref.read(databaseProvider);
  return () => RecordScope.run(db, (tx) => EventWriter.emptyTrash(db, tx));
});
