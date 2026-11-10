import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/settings_group.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;
  int _section = 0;

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

  List<(String, Widget)> _sections(AppLocalizations l) => [
    (
      l.appearance,
      SettingsGroup(title: l.appearance, child: const AppearanceSection()),
    ),
    (l.calendarTags, _calendarAndTags(l)),
    if (hasNotificationSettings)
      (
        l.notifications,
        SettingsGroup(
          title: l.notifications,
          child: const NotificationsSection(),
        ),
      ),
    (l.data, SettingsGroup(title: l.data, child: const ImportExportSection())),
    (l.account, SettingsGroup(title: l.account, child: const AccountSection())),
    (l.aiAssistant, SettingsGroup(title: l.aiAssistant, child: const AiSection())),
    (l.about, SettingsGroup(title: l.about, child: AboutSection(version: _cachedVersion ?? ''))),
  ];

  Widget _calendarAndTags(AppLocalizations l) {
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? const [];
    final trashed = ref.watch(deletedTodosProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: l.calendar,
          child: Column(
            children: [
              DsSettingRow(
                label: l.manageCalendars,
                value: l.categoryCount(calendars.length),
                leading: Icon(
                  CupertinoIcons.calendar,
                  size: 18,
                  color: context.ds.ink2,
                ),
                onTap: () => context.push('/calendars'),
              ),
              DsSettingRow(
                label: l.tags,
                value: l.categoryCount(tags.length),
                leading: Icon(
                  CupertinoIcons.tag,
                  size: 18,
                  color: context.ds.ink2,
                ),
                onTap: () => context.push('/tags'),
              ),
            ],
          ),
        ),
        SettingsGroup(
          title: l.other,
          child: Column(
            children: [
              DsSettingRow(
                label: l.trash,
                value: l.dayItemCount(trashed.length),
                leading: Icon(
                  CupertinoIcons.trash,
                  size: 18,
                  color: context.ds.ink2,
                ),
                onTap: () => context.push('/trash'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final sections = _sections(l);

    if (!desktop) {
      return WorkspacePage(
        title: l.settings,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s2,
            AppSpacing.s4,
            AppSpacing.s8,
          ),
          children: [for (final section in sections) section.$2],
        ),
      );
    }

    final body = sections[_section.clamp(0, sections.length - 1)].$2;
    return WorkspacePage(
      title: l.settings,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 188,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s2,
                AppSpacing.s6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++)
                    _NavItem(
                      label: sections[i].$1,
                      selected: _section == i,
                      onTap: () => setState(() => _section = i),
                    ),
                ],
              ),
            ),
          ),
          Container(width: 1, color: context.ds.line),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s6,
                AppSpacing.s3,
                AppSpacing.s6,
                AppSpacing.s8,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: KeyedSubtree(
                    key: ValueKey('settings-$_section'),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s2 + 2,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected ? ds.navActive : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: selected ? ds.primary : ds.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
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
