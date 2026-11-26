import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/alarm_provider.dart';
import 'package:dayspark/infrastructure/platform/alarm_service.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_toast.dart';

import '../settings_ui.dart';

class NotificationsSection extends ConsumerStatefulWidget {
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
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Permission changes happen in the system app: the only reliable moment
    // to re-read them is when this app comes back to the foreground.
    _lifecycleListener = AppLifecycleListener(onResume: _refreshFromSystem);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _refreshFromSystem() {
    if (!mounted) return;
    ref.invalidate(NotificationsSection.permissionStatusProvider);
    ref.invalidate(NotificationsSection.canScheduleExactProvider);
    unawaited(NotificationsSection.loadSystemAlarmSetting(ref));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Platform gates come from defaultTargetPlatform rather than dart:io so a
    // widget test can exercise each platform's set of rows.
    final platform = defaultTargetPlatform;
    final showsAlarm =
        !kIsWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    final showsPermission = !kIsWeb;
    // SPEC: exact alarms are an Android-only requirement. Other platforms
    // must not render a row whose "allowed" value nothing enforces.
    final showsExactAlarm = !kIsWeb && platform == TargetPlatform.android;
    final status = ref
        .watch(NotificationsSection.permissionStatusProvider)
        .valueOrNull;
    final denied = status == NotificationPermissionStatus.denied;
    final exactAllowed = showsExactAlarm
        ? ref.watch(NotificationsSection.canScheduleExactProvider).valueOrNull
        : null;
    final alarmOn = ref.watch(NotificationsSection.systemAlarmProvider);
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
            // SPEC 2504-2507: three status rows. The alarm switch is the one
            // place the user can change a value rather than just read it, and
            // only where the alarm plugin really schedules (Android / iOS).
            if (showsAlarm)
              SettingsRow(
                label: l.systemAlarm,
                subtitle: l.systemAlarmDesc,
                value: alarmOn ? l.notificationAllowed : l.notificationOff,
                trailing: Switch(
                  value: alarmOn,
                  onChanged: (v) {
                    // Flip the visual state first: stopAll takes 190-335 ms with 12
                    // alarms and must not hold the switch hostage.
                    ref
                            .read(
                              NotificationsSection.systemAlarmProvider.notifier,
                            )
                            .state =
                        v;
                    unawaited(ref.read(alarmToggleProvider)(v));
                  },
                ),
              ),
            if (showsPermission)
              if (denied)
                SettingsRow(
                  label: l.systemNotification,
                  value: l.openSystemSettings,
                  chevron: SettingsChevron.right,
                  onTap: () => NotificationService().openSystemSettings(),
                )
              else
                SettingsRow(
                  label: l.notificationPermission,
                  subtitle: l.notificationPermissionDesc,
                  value: _statusLabel(l, status),
                  chevron: status == NotificationPermissionStatus.granted
                      ? SettingsChevron.none
                      : SettingsChevron.right,
                  onTap: status == NotificationPermissionStatus.granted
                      ? null
                      : () => _requestPermission(context, l, status),
                ),
            if (showsExactAlarm)
              SettingsRow(
                label: l.exactAlarmTitle,
                subtitle: l.exactAlarmDesc,
                value: denied || exactAllowed == false
                    ? l.exactAlarmNotActive
                    : exactAllowed == true
                    ? l.notificationAllowed
                    : l.notificationUnknown,
                chevron: exactAllowed == false && !denied
                    ? SettingsChevron.right
                    : SettingsChevron.none,
                onTap: exactAllowed == false && !denied
                    ? () async {
                        await NotificationService()
                            .requestExactAlarmsPermission();
                        ref.invalidate(
                          NotificationsSection.canScheduleExactProvider,
                        );
                      }
                    : null,
              ),
            if (denied)
              SettingsRow(
                label: l.inAppReminders,
                subtitle: l.inAppRemindersDesc,
                value: l.available,
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
    AppLocalizations l,
    NotificationPermissionStatus? status,
  ) async {
    if (status == NotificationPermissionStatus.denied) {
      await NotificationService().openSystemSettings();
      return;
    }
    await NotificationService().requestPermission();
    ref.invalidate(NotificationsSection.permissionStatusProvider);
    if (!context.mounted) return;
    showSpecToast(context, l.notificationPermissionAsked);
  }
}
