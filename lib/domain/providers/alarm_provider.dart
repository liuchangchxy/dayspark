import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/infrastructure/platform/alarm_service.dart';

typedef AlarmToggle = Future<void> Function(bool enabled);

/// Single entry point for the system-alarm switch.
///
/// OFF returns as soon as the preference is saved; the native clear continues
/// behind the UI. ON waits out any pending clear and then asks the reconciler
/// to re-arm existing reminders, so users do not have to edit a Todo first.
final alarmToggleProvider = Provider<AlarmToggle>((ref) {
  return (enabled) async {
    await AlarmService.setEnabled(enabled);
    if (enabled) {
      await ref.read(reminderReconcilerProvider).onAlarmEnabled();
    }
  };
});
