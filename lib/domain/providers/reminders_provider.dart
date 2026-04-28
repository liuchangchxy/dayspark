import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/notification_service.dart';

/// NotificationService singleton provider.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  service.init().catchError((_) {});
  return service;
});

/// Reminders for a specific event.
final eventRemindersProvider = StreamProvider.family<List<Reminder>, int>((
  ref,
  eventId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.reminders)..where(
        (t) => t.parentType.equals('event') & t.parentId.equals(eventId),
      ))
      .watch();
});

/// Reminders for a specific todo.
final todoRemindersProvider = StreamProvider.family<List<Reminder>, int>((
  ref,
  todoId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.reminders)
        ..where((t) => t.parentType.equals('todo') & t.parentId.equals(todoId)))
      .watch();
});

/// Create a reminder and schedule a notification.
final createReminderProvider =
    Provider<
      Future<int> Function({
        required String parentType,
        required int parentId,
        required DateTime triggerTime,
      })
    >((ref) {
      final db = ref.watch(databaseProvider);
      final notifService = ref.watch(notificationServiceProvider);
      return ({
        required parentType,
        required parentId,
        required triggerTime,
      }) async {
        final id = await db
            .into(db.reminders)
            .insert(
              RemindersCompanion.insert(
                parentType: parentType,
                parentId: parentId,
                triggerTime: triggerTime,
              ),
            );

        final reminder = await (db.select(
          db.reminders,
        )..where((t) => t.id.equals(id))).getSingle();
        await notifService.scheduleFromReminder(reminder);

        return id;
      };
    });

/// Delete a reminder and cancel its notification.
final deleteReminderProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  final notifService = ref.watch(notificationServiceProvider);
  return (int id) async {
    await notifService.cancel(id);
    await (db.delete(db.reminders)..where((t) => t.id.equals(id))).go();
  };
});

/// Quick-add default reminders when creating an event (5min, 15min before).
final addDefaultEventRemindersProvider =
    Provider<
      Future<void> Function({required int eventId, required DateTime startDt})
    >((ref) {
      final createReminder = ref.watch(createReminderProvider);
      return ({required eventId, required startDt}) async {
        const offsets = [Duration(minutes: 5), Duration(minutes: 15)];
        for (final offset in offsets) {
          final triggerTime = startDt.subtract(offset);
          if (triggerTime.isAfter(DateTime.now())) {
            await createReminder(
              parentType: 'event',
              parentId: eventId,
              triggerTime: triggerTime,
            );
          }
        }
      };
    });

/// Quick-add default reminders when creating a todo (1 day, 1 hour before due).
final addDefaultTodoRemindersProvider =
    Provider<
      Future<void> Function({required int todoId, required DateTime? dueDate})
    >((ref) {
      final createReminder = ref.watch(createReminderProvider);
      return ({required todoId, required dueDate}) async {
        if (dueDate == null) return;

        final offsets = [const Duration(hours: 1), const Duration(days: 1)];
        for (final offset in offsets) {
          final triggerTime = dueDate.subtract(offset);
          if (triggerTime.isAfter(DateTime.now())) {
            await createReminder(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: triggerTime,
            );
          }
        }
      };
    });

/// Reschedule reminders when the reference time changes (e.g. event start or todo due date).
/// Deletes old reminders and creates new ones with the same offsets relative to the new time.
final rescheduleRemindersProvider =
    Provider<
      Future<void> Function({
        required String parentType,
        required int parentId,
        required DateTime oldReferenceTime,
        required DateTime newReferenceTime,
      })
    >((ref) {
      final db = ref.watch(databaseProvider);
      final notifService = ref.watch(notificationServiceProvider);
      final createReminder = ref.watch(createReminderProvider);
      return ({
        required parentType,
        required parentId,
        required oldReferenceTime,
        required newReferenceTime,
      }) async {
        // Get existing reminders
        final reminders =
            await (db.select(db.reminders)..where(
                  (t) =>
                      t.parentType.equals(parentType) &
                      t.parentId.equals(parentId),
                ))
                .get();

        // Calculate offsets from old reference time
        final offsets = reminders
            .map((r) => oldReferenceTime.difference(r.triggerTime))
            .toList();

        // Cancel and delete old reminders
        for (final r in reminders) {
          await notifService.cancel(r.id);
        }
        await (db.delete(db.reminders)..where(
              (t) =>
                  t.parentType.equals(parentType) & t.parentId.equals(parentId),
            ))
            .go();

        // Create new reminders with same offsets from new reference time
        for (final offset in offsets) {
          final triggerTime = newReferenceTime.subtract(offset);
          if (triggerTime.isAfter(DateTime.now())) {
            await createReminder(
              parentType: parentType,
              parentId: parentId,
              triggerTime: triggerTime,
            );
          }
        }
      };
    });
