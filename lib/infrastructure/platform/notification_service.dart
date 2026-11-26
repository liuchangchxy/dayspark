import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/platform_target.dart';
import '../../data/local/database/app_database.dart';
import '../../domain/providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import 'alarm_service.dart';

/// Runtime state of the system notification permission.
enum NotificationPermissionStatus { granted, denied, unknown }

/// Action IDs for notification action buttons.
class NotificationActions {
  static const String markComplete = 'mark_complete';
  static const String snooze = 'snooze';

  /// Identifier of the iOS/macOS notification category that carries the
  /// actions. Attached to every reminder notification so the system renders
  /// the buttons.
  static const String category = 'calendar_todo_reminder';
}

/// Localized action titles used on Android and Windows, resolved without a
/// BuildContext because notifications are scheduled outside the widget tree.
class _NotificationActionLabels {
  const _NotificationActionLabels({
    required this.markComplete,
    required this.snooze,
  });

  final String markComplete;
  final String snooze;
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

    // The system UI shows these titles, so they have to match the language
    // the app is running in. Notifications are scheduled away from a
    // BuildContext, hence the locale is resolved from preferences/system.
    final actionLabels = await _loadActionLabels();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: _darwinCategories(actionLabels),
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

    if (isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
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

    // A tap that launched the app never reaches onDidReceiveNotificationResponse
    // on Android; the payload is only available through launch details. Read it
    // once after initialization and hand it to the same dispatcher.
    await _captureLaunchResponse();
  }

  void Function(int parentId, String parentType)? _notificationTappedHandler;
  void Function(
    String actionId,
    int parentId,
    String parentType,
    int? reminderId,
  )?
  _onNotificationAction;

  NotificationResponse? _pendingLaunchResponse;
  bool _launchResponseHandled = false;
  bool _launchDetailsRequested = false;

  void Function(int parentId, String parentType)? get onNotificationTapped =>
      _notificationTappedHandler;

  /// Kept for callers that own navigation. See [_flushPendingLaunchResponse]:
  /// a cold-start tap is held until this handler exists so it is not dropped.
  set onNotificationTapped(
    void Function(int parentId, String parentType)? handler,
  ) {
    _notificationTappedHandler = handler;
    _flushPendingLaunchResponse();
  }

  void Function(
    String actionId,
    int parentId,
    String parentType,
    int? reminderId,
  )?
  get onNotificationAction => _onNotificationAction;

  set onNotificationAction(
    void Function(
      String actionId,
      int parentId,
      String parentType,
      int? reminderId,
    )?
    handler,
  ) {
    _onNotificationAction = handler;
    _flushPendingLaunchResponse();
  }

  Future<_NotificationActionLabels> _loadActionLabels() async {
    try {
      final locale = await resolveAppLocale();
      final resolved = AppLocalizations.delegate.isSupported(locale)
          ? locale
          : const Locale('en');
      final l = await AppLocalizations.delegate.load(resolved);
      return _NotificationActionLabels(
        markComplete: l.markComplete,
        snooze: l.snooze,
      );
    } catch (error) {
      // English constants keep scheduling usable if l10n cannot be loaded
      // (e.g. no binding yet in a background isolate).
      debugPrint('notification: action labels unavailable: $error');
      return const _NotificationActionLabels(
        markComplete: 'Mark Complete',
        snooze: 'Snooze',
      );
    }
  }

  List<DarwinNotificationCategory> _darwinCategories(
    _NotificationActionLabels labels,
  ) {
    return [
      DarwinNotificationCategory(
        NotificationActions.category,
        actions: [
          DarwinNotificationAction.plain(
            NotificationActions.markComplete,
            labels.markComplete,
            // Foreground actions launch the app so the Dart handler can
            // update the database immediately.
            options: const {DarwinNotificationActionOption.foreground},
          ),
          DarwinNotificationAction.plain(
            NotificationActions.snooze,
            labels.snooze,
            options: const {DarwinNotificationActionOption.foreground},
          ),
        ],
      ),
    ];
  }

  Future<void> _captureLaunchResponse() async {
    if (_launchResponseHandled || _launchDetailsRequested) return;
    _launchDetailsRequested = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final response = details?.notificationResponse;
      if (response == null) return;
      _pendingLaunchResponse = response;
      _flushPendingLaunchResponse();
    } catch (error) {
      debugPrint('notification: launch details unavailable: $error');
    }
  }

  /// Dispatches the launch notification at most once. Action responses that
  /// need [onNotificationAction] are held until that handler is attached
  /// during app startup; taps and event actions can fall back to a deep link.
  void _flushPendingLaunchResponse() {
    if (_launchResponseHandled) return;
    final response = _pendingLaunchResponse;
    if (response == null) return;

    final payload = response.payload;
    final parsed = payload == null
        ? null
        : NotificationPayload.tryParse(payload);
    if (parsed == null) {
      _launchResponseHandled = true;
      _pendingLaunchResponse = null;
      return;
    }

    final actionId = response.actionId;
    final needsActionHandler = actionId != null && parsed.parentType != 'event';
    if (needsActionHandler && onNotificationAction == null) return;

    _launchResponseHandled = true;
    _pendingLaunchResponse = null;
    _handleNotificationResponse(response);
  }

  void _onNotificationTapped(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final parsed = NotificationPayload.tryParse(payload);
    if (parsed == null) return;

    switch (response.actionId) {
      case NotificationActions.markComplete:
        // Events have no completed state. Sending the action to the todo
        // handler would silently do nothing, so land on the event detail page
        // instead: through the navigation callback when one is attached, or
        // through the same deep link the widgets use.
        if (parsed.parentType == 'event') {
          if (onNotificationTapped != null) {
            onNotificationTapped!(parsed.parentId, parsed.parentType);
          } else {
            _openItemDetail(parsed.parentType, parsed.parentId);
          }
        } else if (onNotificationAction != null) {
          onNotificationAction!(
            NotificationActions.markComplete,
            parsed.parentId,
            parsed.parentType,
            parsed.reminderId,
          );
        } else {
          _openItemDetail(parsed.parentType, parsed.parentId);
        }
        break;
      case NotificationActions.snooze:
        if (onNotificationAction != null) {
          onNotificationAction!(
            NotificationActions.snooze,
            parsed.parentId,
            parsed.parentType,
            parsed.reminderId,
          );
        } else {
          _openItemDetail(parsed.parentType, parsed.parentId);
        }
        break;
      default:
        // Body taps (no actionId) are navigation, not mutations.
        if (response.actionId == null) {
          if (onNotificationTapped != null) {
            onNotificationTapped!(parsed.parentId, parsed.parentType);
          } else {
            _openItemDetail(parsed.parentType, parsed.parentId);
          }
        }
        break;
    }
  }

  /// Last-resort visible outcome when no navigation callback is attached:
  /// route into the item's detail page with the app's own deep-link scheme.
  void _openItemDetail(String parentType, int parentId) {
    if (parentId <= 0) return;
    if (parentType != 'event' && parentType != 'todo') return;
    final uri = Uri.parse('dayspark://open/$parentType?id=$parentId');
    unawaited(
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((
        Object error,
      ) {
        debugPrint('notification: open $parentType failed: $error');
        return false;
      }),
    );
  }

  /// Whether exact alarms may currently be scheduled (Android 12+ gate).
  Future<bool> canScheduleExactAlarms() async {
    if (!isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// Reads the current system permission without prompting. Desktop platforms
  /// that post notifications without a runtime grant report [granted].
  Future<NotificationPermissionStatus> permissionStatus() async {
    if (kIsWeb) return NotificationPermissionStatus.unknown;
    try {
      if (isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final enabled = await android?.areNotificationsEnabled();
        if (enabled == null) return NotificationPermissionStatus.unknown;
        return enabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      if (isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final options = await ios?.checkPermissions();
        if (options == null) return NotificationPermissionStatus.unknown;
        return options.isEnabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      if (isMacOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        final options = await macos?.checkPermissions();
        if (options == null) return NotificationPermissionStatus.unknown;
        return options.isEnabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
      return NotificationPermissionStatus.granted;
    } catch (error) {
      debugPrint('notification: permission status unavailable: $error');
      return NotificationPermissionStatus.unknown;
    }
  }

  /// Asks for notification permission. On macOS and iOS the ask is a single
  /// system prompt, and a user who dismissed it needs a way back to it.
  Future<void> requestPermission() async {
    if (!_initialized) await init();
    if (isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    } else if (isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Opens the system notification settings for this app. A denied permission
  /// cannot be re-prompted, so this is the only recovery path.
  Future<void> openSystemSettings() async {
    if (kIsWeb) return;
    final uri = switch (defaultTargetPlatform) {
      TargetPlatform.android => Uri.parse('package:com.dayspark.app'),
      TargetPlatform.iOS => Uri.parse('app-settings:'),
      TargetPlatform.macOS => Uri.parse(
        'x-apple.systempreferences:com.apple.preference.notifications',
      ),
      _ => null,
    };
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('notification: open settings failed: $error');
    }
  }

  /// Opens the system screen that grants the exact-alarm permission.
  Future<void> requestExactAlarmsPermission() async {
    if (!isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
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
    final labels = await _loadActionLabels();
    final androidDetails = AndroidNotificationDetails(
      'calendar_todo_reminders',
      'Reminders',
      channelDescription: 'Notifications for calendar events and todos',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationActions.markComplete,
          labels.markComplete,
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          NotificationActions.snooze,
          labels.snooze,
          showsUserInterface: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: NotificationActions.category,
    );
    final windowsDetails = WindowsNotificationDetails(
      actions: [
        WindowsAction(
          content: labels.markComplete,
          arguments: NotificationActions.markComplete,
        ),
        WindowsAction(
          content: labels.snooze,
          arguments: NotificationActions.snooze,
        ),
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
    final labels = await _loadActionLabels();
    final androidDetails = AndroidNotificationDetails(
      'calendar_todo_reminders',
      'Reminders',
      channelDescription: 'Notifications for calendar events and todos',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationActions.markComplete,
          labels.markComplete,
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          NotificationActions.snooze,
          labels.snooze,
          showsUserInterface: true,
        ),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: NotificationActions.category,
    );
    final windowsDetails = WindowsNotificationDetails(
      actions: [
        WindowsAction(
          content: labels.markComplete,
          arguments: NotificationActions.markComplete,
        ),
        WindowsAction(
          content: labels.snooze,
          arguments: NotificationActions.snooze,
        ),
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
