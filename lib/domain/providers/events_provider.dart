import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

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
        return db.transaction(() async {
          final id = await db
              .into(db.events)
              .insert(
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
              );
          await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
          return id;
        });
      };
    });

final updateEventProvider =
    Provider<Future<void> Function(int id, EventsCompanion data)>((ref) {
      final db = ref.read(databaseProvider);
      return (int id, EventsCompanion data) => db.transaction(() async {
        await (db.update(db.events)..where((t) => t.id.equals(id))).write(data);
        await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
      });
    });

final deleteEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  final notifService = ref.read(notificationServiceProvider);
  return (int id) async {
    // Cancel scheduled notifications
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
    await db.transaction(() async {
      // Soft delete
      await (db.update(db.events)..where((t) => t.id.equals(id))).write(
        EventsCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await SyncOutbox.enqueueDelete(db, RecordType.event, id);
    });
  };
});

final deletedEventsProvider = StreamProvider<List<Event>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.eventsDao.watchDeletedEvents();
});

final restoreEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) => db.transaction(() async {
    await db.eventsDao.restoreEvent(id);
    // Resurrect intent: replaces a pending tombstone in the outbox.
    await SyncOutbox.enqueueUpsert(db, RecordType.event, id);
  });
});

final hardDeleteEventWithChildrenProvider =
    Provider<Future<void> Function(int)>((ref) {
      final db = ref.read(databaseProvider);
      final notifService = ref.read(notificationServiceProvider);
      return (int id) async {
        // DAO deletes reminder rows only; cancel OS notifications first so
        // nothing fires after the rows are gone.
        final reminders =
            await (db.select(db.reminders)..where(
                  (t) =>
                      t.parentType.equals('event') & t.parentId.equals(id),
                ))
                .get();
        for (final r in reminders) {
          await notifService.cancel(r.id);
        }
        await db.transaction(() async {
          final targets =
              await SyncOutbox.captureDeletes(db, RecordType.event, [id]);
          await db.eventsDao.hardDeleteEventWithChildren(id);
          await SyncOutbox.enqueueDeletes(db, targets);
        });
      };
    });

final emptyEventTrashProvider = Provider<Future<void> Function()>((ref) {
  final db = ref.read(databaseProvider);
  final notifService = ref.read(notificationServiceProvider);
  return () async {
    final deleted =
        await (db.select(db.events)..where((t) => t.deletedAt.isNotNull()))
            .get();
    final ids = deleted.map((e) => e.id).toList();
    if (ids.isNotEmpty) {
      final reminders =
          await (db.select(db.reminders)..where(
                (t) => t.parentType.equals('event') & t.parentId.isIn(ids),
              ))
              .get();
      for (final r in reminders) {
        await notifService.cancel(r.id);
      }
    }
    await db.transaction(() async {
      final targets =
          await SyncOutbox.captureDeletes(db, RecordType.event, ids);
      await db.eventsDao.emptyEventTrash();
      await SyncOutbox.enqueueDeletes(db, targets);
    });
  };
});
