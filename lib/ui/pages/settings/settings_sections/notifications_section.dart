import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/alarm_provider.dart';
import 'package:dayspark/infrastructure/platform/alarm_service.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';

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

  static final permissionStatusProvider =
      FutureProvider.autoDispose<NotificationPermissionStatus>((ref) {
        return NotificationService().permissionStatus();
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
    final showsPermission = !kIsWeb;
    final showsExactAlarm = !kIsWeb && platform == TargetPlatform.android;
    final status = ref.watch(permissionStatusProvider).valueOrNull;
    final denied = status == NotificationPermissionStatus.denied;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (denied)
          InlineAlert(
            message: l.notifyDeniedBanner,
            isRed: true,
            action: Align(
              alignment: Alignment.centerLeft,
              child: DsButton(
                label: l.openSystemSettings,
                small: true,
                tone: DsButtonTone.secondary,
                onPressed: () => NotificationService().openSystemSettings(),
              ),
            ),
          ),
        SettingsRows(
          children: [
            // The alarm plugin only ships Android and iOS implementations, so on
            // Windows the switch would flip a preference nothing reads.
            if (showsAlarm)
              SettingsRow(
                label: l.systemAlarm,
                subtitle: l.systemAlarmDesc,
                trailing: Switch(
                  value: ref.watch(systemAlarmProvider),
                  onChanged: (v) {
                    // Flip the visual state first: stopAll takes 190-335 ms with 12
                    // alarms and must not hold the switch hostage.
                    ref.read(systemAlarmProvider.notifier).state = v;
                    unawaited(ref.read(alarmToggleProvider)(v));
                  },
                ),
              ),
            if (showsPermission)
              SettingsRow(
                label: l.notificationPermission,
                subtitle: l.notificationPermissionDesc,
                value: _statusLabel(l, status),
                chevron: status == NotificationPermissionStatus.granted
                    ? SettingsChevron.none
                    : SettingsChevron.right,
                onTap: status == NotificationPermissionStatus.granted
                    ? null
                    : () => _requestPermission(context, ref, l, status),
              ),
            if (denied)
              SettingsRow(
                label: l.inAppReminders,
                subtitle: l.inAppRemindersDesc,
                value: l.available,
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
        ),
      ],
    );
  }

  String _statusLabel(
    AppLocalizations l,
    NotificationPermissionStatus? status,
  ) {
    return switch (status) {
      NotificationPermissionStatus.granted => l.notificationAllowed,
      NotificationPermissionStatus.denied => l.notificationOff,
      NotificationPermissionStatus.unknown || null => l.notificationUnknown,
    };
  }

  Future<void> _requestPermission(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    NotificationPermissionStatus? status,
  ) async {
    if (status == NotificationPermissionStatus.denied) {
      await NotificationService().openSystemSettings();
      return;
    }
    await NotificationService().requestPermission();
    ref.invalidate(permissionStatusProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.notificationPermissionAsked)));
  }
}
