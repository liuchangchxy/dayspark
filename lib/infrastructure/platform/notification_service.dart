import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database/app_database.dart';
import 'alarm_service.dart';

/// Action IDs for notification action buttons.
class NotificationActions {
  static const String markComplete = 'mark_complete';
  static const String snooze = 'snooze';
}

/// Notification payload: 'parentType:parentId[:reminderId]'.
/// reminderId lets snooze/cancel address the flutter_local_notifications id
/// space without colliding with parent row ids.
class NotificationPayload {
  const NotificationPayload({
    required this.parentType,
    required this.parentId,
    this.reminderId,
  });

  final String parentType;
  final int parentId;
  final int? reminderId;

  static NotificationPayload? tryParse(String payload) {
    final parts = payload.split(':');
    if (parts.length < 2) return null;
    final parentId = int.tryParse(parts[1]);
    if (parentId == null) return null;
    final reminderId = parts.length > 2 ? int.tryParse(parts[2]) : null;
    return NotificationPayload(
      parentType: parts[0],
      parentId: parentId,
      reminderId: reminderId,
    );
  }

  String encode() {
    if (reminderId == null) return '$parentType:$parentId';
    return '$parentType:$parentId:$reminderId';
  }
}

/// Schedules local notifications for event/todo reminders.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static bool _tzReady = false;

  /// Initializes the timezone database and pins tz.local to the device
  /// location. initializeDatabase resets local to UTC, so this must run once
  /// after database load and before any zonedSchedule call.
  static Future<void> ensureTimeZoneInitialized() async {
    if (_tzReady) return;
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Missing/unknown IANA id: UTC still keeps absolute instants correct.
      debugPrint('notification: timezone resolve failed: $e');
    }
    _tzReady = true;
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    await ensureTimeZoneInitialized();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );

    const windowsSettings = WindowsInitializationSettings(
      appName: 'DaySpark',
      appUserModelId: '',
      guid: '{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}',
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
      await android?.requestNotificationsPermission();
      // Create notification channel with action support
      await android?.createNotificationChannel(
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
  void Function(String actionId, int parentId, String parentType, int? reminderId)?
  onNotificationAction;

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final parsed = NotificationPayload.tryParse(payload);
    if (parsed == null) return;

    if (response.actionId == NotificationActions.markComplete) {
      onNotificationAction?.call(
        NotificationActions.markComplete,
        parsed.parentId,
        parsed.parentType,
        parsed.reminderId,
      );
    } else if (response.actionId == NotificationActions.snooze) {
      onNotificationAction?.call(
        NotificationActions.snooze,
        parsed.parentId,
        parsed.parentType,
        parsed.reminderId,
      );
    } else {
      onNotificationTapped?.call(parsed.parentId, parsed.parentType);
    }
  }

  /// Whether exact alarms may currently be scheduled (Android 12+ gate).
  Future<bool> canScheduleExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// Opens the system screen that grants the exact-alarm permission.
  Future<void> requestExactAlarmsPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();
    await android?.requestExactAlarmsPermission();
  }

  /// Schedule a reminder from the Reminders table.
  Future<void> scheduleFromReminder(
    Reminder reminder, {
    required String eventReminderTitle,
    required String todoReminderTitle,
    required String eventReminderBody,
    required String todoReminderBody,
  }) async {
    if (!_initialized) await init();

    final isEvent = reminder.parentType == 'event';

    await _scheduleNotification(
      id: reminder.id,
      title: isEvent ? eventReminderTitle : todoReminderTitle,
      body: isEvent ? eventReminderBody : todoReminderBody,
      scheduledTime: reminder.triggerTime,
      payload: NotificationPayload(
        parentType: reminder.parentType,
        parentId: reminder.parentId,
        reminderId: reminder.id,
      ).encode(),
    );

    if (await AlarmService.isEnabled()) {
      await AlarmService.scheduleAlarm(
        id: reminder.id,
        type: reminder.parentType,
        dateTime: reminder.triggerTime,
        title: isEvent ? eventReminderTitle : todoReminderTitle,
        body: isEvent ? eventReminderBody : todoReminderBody,
      );
    }
  }

  /// Cancel a scheduled notification by id.
  Future<void> cancel(int id) async {
    await _plugin.cancel(id: id);
    await AlarmService.cancelAlarm(id);
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
    const windowsDetails = WindowsNotificationDetails(
      actions: [
        WindowsAction(content: 'Mark Complete', arguments: 'mark_complete'),
        WindowsAction(content: 'Snooze 1h', arguments: 'snooze'),
      ],
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      windows: windowsDetails,
    );

    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
    if (tzDateTime.isBefore(tz.TZDateTime.now(tz.local))) return;
    // Schedules at the reminder's own id (not an offset): the original
    // notification already fired, and reusing the id keeps cancel(id) able
    // to reach the snoozed copy.
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tzDateTime,
      notificationDetails: details,
      androidScheduleMode: await _scheduleMode(),
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final canExact = await canScheduleExactAlarms();
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
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
    const windowsDetails = WindowsNotificationDetails(
      actions: [
        WindowsAction(content: 'Mark Complete', arguments: 'mark_complete'),
        WindowsAction(content: 'Snooze 1h', arguments: 'snooze'),
      ],
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      windows: windowsDetails,
    );

    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
    if (tzDateTime.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tzDateTime,
      notificationDetails: details,
      androidScheduleMode: await _scheduleMode(),
      title: title,
      body: body,
      payload: payload,
    );
  }
}
