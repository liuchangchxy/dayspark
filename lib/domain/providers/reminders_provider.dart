import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// NotificationService singleton provider.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  service.init().catchError((_) {});
  return service;
});

/// Title/body strings for scheduled notifications, resolved without a
/// BuildContext (scheduling runs outside the widget tree).
class NotificationStrings {
  const NotificationStrings({
    required this.eventReminderTitle,
    required this.todoReminderTitle,
    required this.eventReminderBody,
    required this.todoReminderBody,
  });

  final String eventReminderTitle;
  final String todoReminderTitle;
  final String eventReminderBody;
  final String todoReminderBody;
}

/// Resolves notification strings for [locale], or the persisted app locale,
/// or the platform locale — in that order.
Future<NotificationStrings> loadNotificationStrings({Locale? locale}) async {
  var resolved = locale ?? const Locale('en');
  if (locale == null) {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(appLocalePrefKey);
    resolved = code != null
        ? Locale(code)
        : WidgetsBinding.instance.platformDispatcher.locale;
  }
  final l = await AppLocalizations.delegate.load(resolved);
  return NotificationStrings(
    eventReminderTitle: l.eventReminder,
    todoReminderTitle: l.todoReminder,
    eventReminderBody: l.eventStartingSoon,
    todoReminderBody: l.taskDueSoon,
  );
}

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
      final db = ref.read(databaseProvider);
      return ({
        required parentType,
        required parentId,
        required triggerTime,
      }) => RecordScope.run(
        db,
        (tx) => ReminderWriter.add(
          db,
          tx,
          parentType: parentType,
          parentId: parentId,
          triggerTime: triggerTime,
        ),
      );
    });

/// Schedules an existing reminder row with locale-resolved strings.
final scheduleReminderProvider =
    Provider<Future<void> Function(Reminder)>((ref) {
      final notifService = ref.read(notificationServiceProvider);
      return (Reminder reminder) async {
        final strings = await loadNotificationStrings();
        await notifService.scheduleFromReminder(
          reminder,
          eventReminderTitle: strings.eventReminderTitle,
          todoReminderTitle: strings.todoReminderTitle,
          eventReminderBody: strings.eventReminderBody,
          todoReminderBody: strings.todoReminderBody,
        );
      };
    });

/// Cancels notifications and deletes reminder rows for a parent.
final clearRemindersProvider =
    Provider<Future<void> Function(String, int)>((ref) {
      final db = ref.read(databaseProvider);
      return (String parentType, int parentId) => RecordScope.run(
        db,
        (tx) => ReminderWriter.clear(db, tx, parentType, parentId),
      );
    });

/// Delete a reminder and cancel its notification.
final deleteReminderProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) =>
      RecordScope.run(db, (tx) => ReminderWriter.delete(db, tx, id));
});

/// Quick-add default reminders when creating an event (5min, 15min before).
final addDefaultEventRemindersProvider =
    Provider<
      Future<void> Function({required int eventId, required DateTime startDt})
    >((ref) {
      final createReminder = ref.read(createReminderProvider);
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
      final createReminder = ref.read(createReminderProvider);
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

