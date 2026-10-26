import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';
import 'settings_sections/todos_section.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/widgets/settings_group.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;

  @override
  void initState() {
    super.initState();
    // Load persisted settings once on first build
    if (!_loaded) {
      _loaded = true;
      Future.microtask(() => NotificationsSection.loadSystemAlarmSetting(ref));
      PackageInfo.fromPlatform().then((i) {
        _cachedVersion = 'DaySpark v${i.version}';
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final isDesktop = isWorkspaceLayout(context);

    return WorkspacePage(
      title: l.settings,
      maxContentWidth: 720,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          SettingsGroup(title: l.appearance, child: const AppearanceSection()),
          if (!isDesktop)
            SettingsGroup(
              child: ListTile(
                leading: const Icon(CupertinoIcons.calendar),
                title: Text(l.manageCalendars),
                trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                onTap: () => context.push('/calendars'),
              ),
            ),
          SettingsGroup(title: l.todos, child: const TodosSection()),
          SettingsGroup(title: l.data, child: const ImportExportSection()),
          SettingsGroup(title: l.account, child: const AccountSection()),
          SettingsGroup(title: l.advancedFeatures, child: const AiSection()),
          if (hasNotificationSettings)
            SettingsGroup(title: l.notifications, child: const NotificationsSection()),
          SettingsGroup(
            title: l.about,
            child: AboutSection(version: _cachedVersion ?? ''),
          ),
        ],
      ),
    );
  }
}

/// Notification rows exist only where the platform can actually schedule
/// them (web cannot).
bool get hasNotificationSettings =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);
