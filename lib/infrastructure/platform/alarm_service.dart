import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/platform_target.dart';

/// The alarm-plugin surface DaySpark depends on. Swappable in tests so the
/// ordering rules (deferred init, background stopAll, restored-alarm reuse)
/// are observable without a platform.
abstract interface class AlarmBackend {
  Future<void> init();
  Future<List<AlarmSettings>> alarms();
  Future<bool> set(AlarmSettings settings);
  Future<bool> stop(int id);
  Future<void> stopAll();
}

final class PluginAlarmBackend implements AlarmBackend {
  const PluginAlarmBackend();

  @override
  Future<void> init() => Alarm.init();

  @override
  Future<List<AlarmSettings>> alarms() => Alarm.getAlarms();

  @override
  Future<bool> set(AlarmSettings settings) =>
      Alarm.set(alarmSettings: settings);

  @override
  Future<bool> stop(int id) => Alarm.stop(id);

  @override
  Future<void> stopAll() => Alarm.stopAll();
}

class AlarmService {
  static const _prefKey = 'system_alarm_enabled';

  @visibleForTesting
  static AlarmBackend backend = const PluginAlarmBackend();

  /// Host tests run on macOS, where [isNativeMobile] is false.
  @visibleForTesting
  static bool debugForceNative = false;

  static bool get _supported => isNativeMobile || debugForceNative;

  static bool _initialized = false;
  static Future<void>? _initFuture;

  // Alarms the plugin currently owns. init() populates this from the restore
  // pass, so a cold-start reconcile can reuse restored alarms instead of
  // setting them a second time.
  static final Map<int, DateTime> _known = <int, DateTime>{};

  // stopAll takes 190-335 ms with 12 alarms. OFF must not wait for it, but a
  // subsequent ON must not race ahead of a still-running stopAll.
  static Future<void> _toggleTail = Future<void>.value();

  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    if (!_supported) {
      _initialized = true;
      return;
    }
    try {
      await backend.init();
      _known.clear();
      for (final alarm in await backend.alarms()) {
        _known[alarm.id] = alarm.dateTime;
      }
      _initialized = true;
      // A previous session may have died between "preference = false" and the
      // native clear; never let the plugin's restore pass re-arm alarms the
      // user switched off.
      if (!await isEnabled()) {
        await backend.stopAll();
        _known.clear();
      }
    } catch (error) {
      // A failed init must not be final: leave no cached future so a later
      // schedule retries instead of dropping every alarm for the session.
      debugPrint('alarm: init failed: $error');
      _initFuture = null;
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Persists the preference immediately. Turning alarms OFF clears the native
  /// copies on a background continuation so the switch never waits on
  /// [AlarmBackend.stopAll]; turning them ON waits out any pending clear so the
  /// caller's reconcile cannot be erased by a late stopAll.
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    final previous = _toggleTail;
    final operation = previous.then((_) => _applyEnabled(value));
    _toggleTail = operation.catchError((Object error) {
      debugPrint('alarm: apply enabled=$value failed: $error');
    });
    if (value) {
      await _toggleTail;
    }
  }

  static Future<void> _applyEnabled(bool value) async {
    await init();
    if (!_initialized || value) return;
    await backend.stopAll();
    _known.clear();
  }

  static Future<void> scheduleAlarm({
    required int id,
    required String type,
    required DateTime dateTime,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    if (dateTime.isBefore(DateTime.now())) return;
    await init();
    if (!_initialized) {
      debugPrint('alarm: schedule skipped before init: $id');
      return;
    }
    // A pending OFF wins over work that was queued before it.
    await _toggleTail;
    if (!await isEnabled()) return;

    final alarmId = type == 'event' ? id + 500000 : id + 600000;
    final known = _known[alarmId];
    if (known != null && known.isAtSameMomentAs(dateTime)) return;

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
      warningNotificationOnKill: isIOS,
    );
    if (await backend.set(alarmSettings)) {
      _known[alarmId] = dateTime;
    }
  }

  static Future<void> cancelAlarm(int id, {String? type}) async {
    if (!_supported) return;
    await init();
    if (!_initialized) return;
    await _toggleTail;
    if (type != null) {
      final alarmId = type == 'event' ? id + 500000 : id + 600000;
      await backend.stop(alarmId);
      _known.remove(alarmId);
    } else {
      await backend.stop(id + 500000);
      await backend.stop(id + 600000);
      _known
        ..remove(id + 500000)
        ..remove(id + 600000);
    }
  }

  @visibleForTesting
  static String get debugPrefKey => _prefKey;

  @visibleForTesting
  static Future<void> debugSettled() => _toggleTail;

  @visibleForTesting
  static void debugReset() {
    backend = const PluginAlarmBackend();
    debugForceNative = false;
    _initialized = false;
    _initFuture = null;
    _known.clear();
    _toggleTail = Future<void>.value();
  }
}
