import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/infrastructure/platform/alarm_service.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  static final systemAlarmProvider = StateProvider<bool>((ref) {
    return false;
  });

  // Android 12+ gate for exact alarms; hidden when granted (USE_EXACT_ALARM
  // in the manifest means it normally is, so this row is a fallback).
  static final canScheduleExactProvider = FutureProvider.autoDispose<bool>((
    ref,
  ) async {
    return NotificationService().canScheduleExactAlarms();
  });

  static Future<void> loadSystemAlarmSetting(WidgetRef ref) async {
    ref.read(systemAlarmProvider.notifier).state =
        await AlarmService.isEnabled();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    // Platform gates come from defaultTargetPlatform rather than dart:io so a
    // widget test can exercise each platform's set of rows.
    final platform = defaultTargetPlatform;
    final showsAlarm =
        !kIsWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    final showsMacPermission = !kIsWeb && platform == TargetPlatform.macOS;
    final showsExactAlarm = !kIsWeb && platform == TargetPlatform.android;
    return SettingsRows(
      children: [
        // The alarm plugin only ships Android and iOS implementations, so on
        // Windows the switch would flip a preference nothing reads.
        if (showsAlarm)
          SettingsRow(
            label: l.systemAlarm,
            subtitle: l.systemAlarmDesc,
            trailing: Switch(
              value: ref.watch(systemAlarmProvider),
              onChanged: (v) async {
                await AlarmService.setEnabled(v);
                ref.read(systemAlarmProvider.notifier).state = v;
              },
            ),
          ),
        if (showsMacPermission)
          SettingsRow(
            label: l.notificationPermission,
            subtitle: l.notificationPermissionDesc,
            chevron: SettingsChevron.right,
            onTap: () async {
              await NotificationService().requestPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.notificationPermissionAsked)),
              );
            },
          ),
        if (showsExactAlarm &&
            ref.watch(canScheduleExactProvider).valueOrNull == false)
          SettingsRow(
            label: l.exactAlarmTitle,
            subtitle: l.exactAlarmDesc,
            chevron: SettingsChevron.right,
            onTap: () async {
              await NotificationService().requestExactAlarmsPermission();
              ref.invalidate(canScheduleExactProvider);
            },
          ),
      ],
    );
  }
}
