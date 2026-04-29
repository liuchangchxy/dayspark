import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Callback dispatcher for workmanager — must be top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // We can't use Riverpod here, so we do a minimal sync directly.
    // For now, just return true. The actual sync happens in foreground.
    debugPrint('Background sync task: $task');
    return true;
  });
}

/// Manages foreground periodic sync and background workmanager registration.
class BackgroundSyncService {
  Timer? _timer;
  final Future<void> Function() _syncFn;
  final Duration _interval;

  BackgroundSyncService({
    required Future<void> Function() syncFn,
    Duration interval = const Duration(seconds: 30),
  }) : _syncFn = syncFn,
       _interval = interval;

  /// Initialize workmanager for background sync.
  Future<void> init() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );
      await Workmanager().registerPeriodicTask(
        'calendar-sync',
        'calendarPeriodicSync',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Workmanager not supported on this platform (e.g. macOS, Linux, Windows)
    }
  }

  /// Start foreground periodic sync.
  void startForeground() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) async {
      try {
        await _syncFn();
      } catch (_) {}
    });
  }

  /// Stop foreground periodic sync.
  void stopForeground() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stopForeground();
  }
}
