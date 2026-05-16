/// Stub Windows implementation — no FFI, avoids gen_snapshot AOT crash.
library;

export 'src/details.dart';

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:timezone/timezone.dart';

export 'src/details.dart';

/// Stub Windows implementation — no FFI, avoids gen_snapshot AOT crash.
class FlutterLocalNotificationsWindows extends FlutterLocalNotificationsPlatform {
  static void registerWith() {
    FlutterLocalNotificationsPlatform.instance = FlutterLocalNotificationsWindows();
  }

  @override
  Future<bool> initialize({
    dynamic settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async => false;

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => [];

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async => [];

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => null;

  @override
  Future<void> periodicallyShow({
    required int id,
    String? title,
    String? body,
    required RepeatInterval repeatInterval,
  }) async {}

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    String? title,
    String? body,
    required Duration repeatDurationInterval,
  }) async {}

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    dynamic notificationDetails,
  }) async {}

  @override
  Future<void> showRawXml({
    required int id,
    required String xml,
    Map<String, String> bindings = const <String, String>{},
  }) async {}

  @override
  bool isValidXml(String xml) => false;

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required TZDateTime scheduledDate,
    dynamic notificationDetails,
    String? payload,
  }) async {}

  @override
  Future<void> zonedScheduleRawXml({
    required int id,
    required String xml,
    required TZDateTime scheduledDate,
  }) async {}

  @override
  Future<void> update({
    required int id,
    String? title,
    String? body,
    dynamic notificationDetails,
  }) async {}
}
