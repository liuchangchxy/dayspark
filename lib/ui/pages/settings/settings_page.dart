import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/general_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/widgets/settings_group.dart';

enum SettingsTab { general, appearance, calendars, data, account, ai, notifications, about }

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;
  SettingsTab _selectedTab = SettingsTab.general;

  @override
  void initState() {
    super.initState();
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
    final isWorkspace = isWorkspaceLayout(context);

    if (isWorkspace) {
      return WorkspacePage(
        title: l.settings,
        maxContentWidth: 960,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left pane: 188px navigation list
            SizedBox(
              width: 188,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                children: [
                  _navItem(SettingsTab.general, l.generalSettings, CupertinoIcons.gear),
                  _navItem(SettingsTab.appearance, l.appearance, CupertinoIcons.paintbrush),
                  _navItem(SettingsTab.calendars, l.manageCalendars, CupertinoIcons.calendar),
                  _navItem(SettingsTab.data, l.data, CupertinoIcons.arrow_2_squarepath),
                  _navItem(SettingsTab.account, l.account, CupertinoIcons.person),
                  _navItem(SettingsTab.ai, l.aiAssistant, CupertinoIcons.sparkles),
                  if (hasNotificationSettings)
                    _navItem(SettingsTab.notifications, l.notifications, CupertinoIcons.bell),
                  _navItem(SettingsTab.about, l.about, CupertinoIcons.info),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            // Right pane: max 680 content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: _buildTabContent(_selectedTab, l),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return WorkspacePage(
      title: l.settings,
      maxContentWidth: 720,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          SettingsGroup(title: l.generalSettings, child: const GeneralSettingsSection()),
          SettingsGroup(title: l.appearance, child: const AppearanceSection()),
          SettingsGroup(
            title: l.calendar,
            child: ListTile(
              leading: const Icon(CupertinoIcons.calendar, size: 20),
              title: Text(l.manageCalendars, style: AppTypography.body),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: () => context.push('/calendars'),
            ),
          ),
          SettingsGroup(title: l.data, child: const ImportExportSection()),
          SettingsGroup(title: l.account, child: const AccountSection()),
          SettingsGroup(title: l.aiAssistant, child: const AiSection()),
          if (hasNotificationSettings)
            SettingsGroup(
              title: l.notifications,
              child: const NotificationsSection(),
            ),
          SettingsGroup(
            title: l.about,
            child: AboutSection(version: _cachedVersion ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _navItem(SettingsTab tab, String title, IconData icon) {
    final isSelected = _selectedTab == tab;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rMd)),
        selected: isSelected,
        selectedTileColor: theme.colorScheme.surfaceContainerHighest,
        selectedColor: theme.colorScheme.onSurface,
        leading: Icon(icon, size: 18),
        title: Text(
          title,
          style: AppTypography.body.copyWith(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        onTap: () {
          if (tab == SettingsTab.calendars) {
            context.push('/calendars');
          } else {
            setState(() => _selectedTab = tab);
          }
        },
      ),
    );
  }

  Widget _buildTabContent(SettingsTab tab, AppLocalizations l) {
    return switch (tab) {
      SettingsTab.general => SettingsGroup(
          title: l.generalSettings,
          child: const GeneralSettingsSection(),
        ),
      SettingsTab.appearance => SettingsGroup(
          title: l.appearance,
          child: const AppearanceSection(),
        ),
      SettingsTab.calendars => const SizedBox.shrink(),
      SettingsTab.data => SettingsGroup(
          title: l.data,
          child: const ImportExportSection(),
        ),
      SettingsTab.account => SettingsGroup(
          title: l.account,
          child: const AccountSection(),
        ),
      SettingsTab.ai => SettingsGroup(
          title: l.aiAssistant,
          child: const AiSection(),
        ),
      SettingsTab.notifications => SettingsGroup(
          title: l.notifications,
          child: const NotificationsSection(),
        ),
      SettingsTab.about => SettingsGroup(
          title: l.about,
          child: AboutSection(version: _cachedVersion ?? ''),
        ),
    };
  }
}

bool get hasNotificationSettings =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);
