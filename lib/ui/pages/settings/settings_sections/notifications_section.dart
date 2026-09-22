import 'package:flutter/foundation.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/infrastructure/platform/alarm_service.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  static final systemAlarmProvider = StateProvider<bool>((ref) {
    return false;
  });

  // Android 12+ gate for exact alarms; hidden when granted (USE_EXACT_ALARM
  // in the manifest means it normally is, so this tile is a fallback).
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.windows) ...[
          const Divider(),
          SwitchListTile(
            secondary: const Icon(CupertinoIcons.alarm),
            title: Text(l.systemAlarm),
            subtitle: Text(l.systemAlarmDesc),
            value: ref.watch(systemAlarmProvider),
            onChanged: (v) async {
              await AlarmService.setEnabled(v);
              ref.read(systemAlarmProvider.notifier).state = v;
            },
          ),
          const Divider(),
        ],
        if (defaultTargetPlatform == TargetPlatform.android &&
            ref.watch(canScheduleExactProvider).valueOrNull == false) ...[
          const Divider(),
          ListTile(
            leading: const Icon(CupertinoIcons.timer),
            title: Text(l.exactAlarmTitle),
            subtitle: Text(l.exactAlarmDesc),
            onTap: () async {
              await NotificationService().requestExactAlarmsPermission();
              ref.invalidate(canScheduleExactProvider);
            },
          ),
          const Divider(),
        ],
      ],
    );
  }
}
