import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmService {
  static const _prefKey = 'system_alarm_enabled';

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Alarm.init();
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (!value) {
      await Alarm.stopAll();
    }
  }

  static Future<void> scheduleAlarm({
    required int id,
    required String type,
    required DateTime dateTime,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (dateTime.isBefore(DateTime.now())) return;

    final alarmId = type == 'event' ? id + 500000 : id + 600000;
    final alarmSettings = AlarmSettings(
      id: alarmId,
      dateTime: dateTime,
      assetAudioPath: null,
      loopAudio: true,
      vibrate: true,
      volumeSettings: VolumeSettings.fixed(),
      notificationSettings: NotificationSettings(
        title: title,
        body: body,
        stopButton: 'Stop',
      ),
      warningNotificationOnKill: Platform.isIOS,
    );
    await Alarm.set(alarmSettings: alarmSettings);
  }

  static Future<void> cancelAlarm(int id, {String? type}) async {
    if (type != null) {
      final alarmId = type == 'event' ? id + 500000 : id + 600000;
      await Alarm.stop(alarmId);
    } else {
      await Alarm.stop(id + 500000);
      await Alarm.stop(id + 600000);
    }
  }
}
