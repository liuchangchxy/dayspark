import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/event_writer.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';

// Static range key ("startMs-endMs") is part of the provider contract
// (docs/CONSTRAINTS.md); autoDispose only releases unused instances.
final eventsInDateRangeProvider = StreamProvider.autoDispose
    .family<List<Event>, String>((ref, rangeKey) {
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

final eventCandidatesInDateRangeProvider = StreamProvider.autoDispose
    .family<List<Event>, String>((ref, rangeKey) {
      final db = ref.watch(databaseProvider);
      final parts = rangeKey.split('-');
      final startMs = int.tryParse(parts[0]);
      final endMs = int.tryParse(parts.length > 1 ? parts[1] : '');
      if (startMs == null || endMs == null) {
        return Stream.value([]);
      }
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final end = DateTime.fromMillisecondsSinceEpoch(endMs);
      return db.eventsDao.watchEventCandidates(start, end);
    });

final calendarsProvider = StreamProvider<List<Calendar>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.calendarsDao.watchAll();
});

/// One event row, kept live for the detail page so it never renders a stale
/// snapshot after an edit or a delete from another surface.
final liveEventProvider = StreamProvider.autoDispose
    .family<CalendaEventAdapter?, int>((ref, id) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.events,
      )..where((row) => row.id.equals(id))).watchSingleOrNull().map((row) {
        if (row == null) return null;
        return CalendaEventAdapter.fromDrift(row);
      });
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

/// Excludes a single occurrence from a recurring series (RFC 5545 EXDATE).
final excludeEventOccurrenceProvider =
    Provider<
      Future<void> Function({
        required int id,
        required DateTime occurrenceStart,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({required int id, required DateTime occurrenceStart}) =>
          RecordScope.run(
            db,
            (tx) => EventWriter.excludeOccurrence(db, tx, id, occurrenceStart),
          );
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

final createCalendarProvider =
    Provider<Future<int> Function({required String name, String? color})>((
      ref,
    ) {
      final db = ref.read(databaseProvider);
      return ({required name, color}) async {
        return db.calendarsDao.insertCalendar(
          CalendarsCompanion.insert(
            name: name,
            color: color != null ? Value(color) : const Value('#2563EB'),
          ),
        );
      };
    });

final updateCalendarProvider =
    Provider<
      Future<void> Function({
        required int id,
        required String name,
        String? color,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({required id, required name, color}) async {
        await db.calendarsDao.updateCalendar(
          id,
          CalendarsCompanion(
            name: Value(name),
            color: color != null ? Value(color) : const Value.absent(),
          ),
        );
      };
    });

/// Deletes a calendar and decides what happens to the rows that referenced it.
///
/// The column is a hard reference, so leaving rows behind would either fail the
/// delete or strand records in a calendar nobody can see. [moveContentsTo]
/// re-homes them; [deleteContents] moves them to the trash with the calendar.
final deleteCalendarProvider =
    Provider<
      Future<void> Function(int id, {int? moveContentsTo, bool deleteContents})
    >((ref) {
      final db = ref.read(databaseProvider);
      return (
        int id, {
        int? moveContentsTo,
        bool deleteContents = false,
      }) async {
        final all = await (db.select(db.calendars)).get();
        if (all.length <= 1) {
          throw StateError('Cannot delete the only remaining calendar.');
        }
        final events = await (db.select(
          db.events,
        )..where((row) => row.calendarId.equals(id))).get();
        final todos = await (db.select(
          db.todos,
        )..where((row) => row.calendarId.equals(id))).get();

        if (moveContentsTo != null) {
          await (db.update(db.events)
                ..where((row) => row.calendarId.equals(id)))
              .write(EventsCompanion(calendarId: Value(moveContentsTo)));
          await (db.update(db.todos)..where((row) => row.calendarId.equals(id)))
              .write(TodosCompanion(calendarId: Value(moveContentsTo)));
        } else if (deleteContents) {
          for (final row in events) {
            await RecordScope.run(
              db,
              (tx) => EventWriter.softDelete(db, tx, row.id),
            );
          }
          for (final row in todos) {
            await RecordScope.run(
              db,
              (tx) => TodoWriter.softDelete(db, tx, row.id),
            );
          }
        } else if (events.isNotEmpty || todos.isNotEmpty) {
          throw StateError('Calendar still holds records.');
        }

        await db.calendarsDao.deleteCalendar(id);
      };
    });
