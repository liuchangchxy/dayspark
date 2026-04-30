import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database/app_database.dart';

/// Action IDs for notification action buttons.
class NotificationActions {
  static const String markComplete = 'mark_complete';
  static const String snooze = 'snooze';
}

/// Schedules local notifications for event/todo reminders.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      // Create notification channel with action support
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'calendar_todo_reminders',
              'Reminders',
              description: 'Notifications for calendar events and todos',
              importance: Importance.high,
            ),
          );
    }

    _initialized = true;
  }

  void Function(int parentId, String parentType)? onNotificationTapped;
  void Function(String actionId, int parentId, String parentType)?
  onNotificationAction;

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final parts = payload.split(':');
    if (parts.length < 2) return;

    final parentType = parts[0];
    final parentId = int.tryParse(parts[1]);
    if (parentId == null) return;

    if (response.actionId == NotificationActions.markComplete) {
      onNotificationAction?.call(
        NotificationActions.markComplete,
        parentId,
        parentType,
      );
    } else if (response.actionId == NotificationActions.snooze) {
      onNotificationAction?.call(
        NotificationActions.snooze,
        parentId,
        parentType,
      );
    } else {
      onNotificationTapped?.call(parentId, parentType);
    }
  }

  /// Schedule a reminder from the Reminders table.
  Future<void> scheduleFromReminder(Reminder reminder) async {
    if (!_initialized) await init();

    final title = reminder.parentType == 'event'
        ? 'Event Reminder'
        : 'Todo Reminder';

    await _scheduleNotification(
      id: reminder.id,
      title: title,
      body: reminder.parentType == 'event'
          ? 'Event starting soon'
          : 'Task due soon',
      scheduledTime: reminder.triggerTime,
      payload: '${reminder.parentType}:${reminder.parentId}',
    );
  }

  /// Cancel a scheduled notification by id.
  Future<void> cancel(int id) async {
    await _plugin.cancel(id: id);
  }

  /// Reschedule a simple reminder notification at a future time.
  Future<void> snooze({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (!_initialized) await init();
    const androidDetails = AndroidNotificationDetails(
      'calendar_todo_reminders',
      'Reminders',
      channelDescription: 'Notifications for calendar events and todos',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
    await _plugin.zonedSchedule(
      id: id + 100000, // Offset to avoid conflicts with original
      scheduledDate: tzDateTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'calendar_todo_reminders',
      'Reminders',
      channelDescription: 'Notifications for calendar events and todos',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          NotificationActions.markComplete,
          'Mark Complete',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          NotificationActions.snooze,
          'Snooze 1h',
          showsUserInterface: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tzDateTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: payload,
    );
  }
}
