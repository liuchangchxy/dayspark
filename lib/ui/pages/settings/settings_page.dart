import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/settings_group.dart';
import 'package:go_router/go_router.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';

enum _SettingsTab {
  appearance,
  calendars,
  data,
  account,
  ai,
  notifications,
  about,
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;
  _SettingsTab _activeTab = _SettingsTab.appearance;

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
    final isDesktop = isWorkspaceLayout(context);

    if (isDesktop) {
      return _buildDesktopLayout(context, l);
    }
    return _buildMobileLayout(context, l);
  }

  Widget _buildMobileLayout(BuildContext context, AppLocalizations l) {
    return WorkspacePage(
      title: l.settings,
      maxContentWidth: 720,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
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
          if (NotificationsSection.hasNotificationSettings)
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

  Widget _buildDesktopLayout(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final navItems = [
      (_SettingsTab.appearance, l.appearance, CupertinoIcons.paintbrush),
      (_SettingsTab.calendars, l.calendar, CupertinoIcons.calendar),
      (_SettingsTab.data, l.data, CupertinoIcons.arrow_down_doc),
      (_SettingsTab.account, l.account, CupertinoIcons.person),
      (_SettingsTab.ai, l.aiAssistant, CupertinoIcons.sparkles),
      if (NotificationsSection.hasNotificationSettings)
        (_SettingsTab.notifications, l.notifications, CupertinoIcons.bell),
      (_SettingsTab.about, l.about, CupertinoIcons.info),
    ];

    Widget content;
    switch (_activeTab) {
      case _SettingsTab.appearance:
        content = SettingsGroup(title: l.appearance, child: const AppearanceSection());
        break;
      case _SettingsTab.calendars:
        content = SettingsGroup(
          title: l.calendar,
          child: ListTile(
            leading: const Icon(CupertinoIcons.calendar, size: 20),
            title: Text(l.manageCalendars, style: AppTypography.body),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => context.push('/calendars'),
          ),
        );
        break;
      case _SettingsTab.data:
        content = SettingsGroup(title: l.data, child: const ImportExportSection());
        break;
      case _SettingsTab.account:
        content = SettingsGroup(title: l.account, child: const AccountSection());
        break;
      case _SettingsTab.ai:
        content = SettingsGroup(title: l.aiAssistant, child: const AiSection());
        break;
      case _SettingsTab.notifications:
        content = SettingsGroup(title: l.notifications, child: const NotificationsSection());
        break;
      case _SettingsTab.about:
        content = SettingsGroup(title: l.about, child: AboutSection(version: _cachedVersion ?? ''));
        break;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left navigation pane (188px per VISUAL_POLISH.md)
            SizedBox(
              width: 188,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: context.semanticColors.separatorSoft, width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      child: Text(
                        l.settings,
                        style: AppTypography.headline.copyWith(fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ...navItems.map((item) {
                      final isSelected = _activeTab == item.$1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: isSelected ? context.semanticColors.surfaceSecondary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () {
                              if (item.$1 == _SettingsTab.calendars) {
                                context.push('/calendars');
                              } else {
                                setState(() => _activeTab = item.$1);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    item.$3,
                                    size: 16,
                                    color: isSelected ? theme.colorScheme.primary : context.semanticColors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.caption.copyWith(
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                        color: isSelected ? theme.colorScheme.onSurface : context.semanticColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            // Right detail pane
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [content],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
