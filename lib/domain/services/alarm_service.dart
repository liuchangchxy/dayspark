import 'package:alarm/alarm.dart';
import 'package:alarm/model/alarm_settings.dart';

/// Service for scheduling system-level alarm reminders.
///
/// Uses the `alarm` package to fire audible alarms at scheduled times.
/// On Android, alarms fire even when the app is killed (foreground service).
/// On iOS, the alarm only fires if the app is in the foreground or background
/// (not when force-killed by the user).
class AlarmService {
  bool _initialized = false;

  /// Initialize the alarm service. Must be called before scheduling alarms.
  Future<void> init() async {
    if (_initialized) return;
    await Alarm.init();
    _initialized = true;
  }

  /// Schedule a system alarm at [dateTime] with the given [label].
  ///
  /// Uses the device default alarm sound (assetAudioPath is null).
  /// Returns the alarm ID for later cancellation.
  Future<int> scheduleAlarm({
    required DateTime dateTime,
    required String label,
  }) async {
    if (!_initialized) await init();

    final alarmSettings = AlarmSettings(
      id: dateTime.millisecondsSinceEpoch % 100000,
      dateTime: dateTime,
      assetAudioPath: null,
      loopAudio: false,
      vibrate: true,
      volumeSettings: VolumeSettings.fixed(),
      notificationSettings: NotificationSettings(
        title: 'Calendar Todo',
        body: label,
      ),
    );
    await Alarm.set(alarmSettings: alarmSettings);
    return alarmSettings.id;
  }

  /// Cancel a previously scheduled alarm by its [id].
  Future<void> cancelAlarm(int id) async {
    await Alarm.stop(id);
  }

  /// Cancel all scheduled alarms.
  Future<void> cancelAll() async {
    await Alarm.stopAll();
  }
}
