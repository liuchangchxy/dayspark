import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'default_calendar_view.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/calendar_settings_section.dart';
import 'settings_sections/data_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';
import 'settings_sections/sync_section.dart';
import 'settings_ui.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsSectionItem {
  const _SettingsSectionItem({
    required this.key,
    required this.label,
    this.subtitle,
    required this.widget,
  });

  final String key;
  final String label;
  final String? subtitle;
  final Widget widget;
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;
  int _section = 0;
  String? _mobileSection;
  String? _customSectionKey;
  final ScrollController _contentScroll = ScrollController();
  final FocusNode _navFocusNode = FocusNode();
  bool _showingDefaultCalendar = false;

  @override
  void initState() {
    super.initState();
    if (!_loaded) {
      _loaded = true;
      Future.microtask(() => NotificationsSection.loadSystemAlarmSetting(ref));
      PackageInfo.fromPlatform()
          .then((i) {
            _cachedVersion = 'DaySpark v${i.version}';
            if (mounted) setState(() {});
          })
          .catchError((Object error) {
            debugPrint('settings: package info unavailable: $error');
          });
    }
  }

  @override
  void dispose() {
    _contentScroll.dispose();
    _navFocusNode.dispose();
    super.dispose();
  }

  void _selectSection(int index) {
    if (_section == index && _customSectionKey == null && !_showingDefaultCalendar) return;
    setState(() {
      _section = index;
      _customSectionKey = null;
      _showingDefaultCalendar = false;
    });
    if (_contentScroll.hasClients) {
      _contentScroll.jumpTo(0);
    }
  }

  void _goToSectionKey(String key) {
    final sections = _desktopSections(AppLocalizations.of(context)!);
    final index = sections.indexWhere((s) => s.key == key);
    if (index >= 0) {
      _selectSection(index);
    } else if (key == 'account' || key == 'ai') {
      setState(() {
        _customSectionKey = key;
        _showingDefaultCalendar = false;
      });
      if (_contentScroll.hasClients) {
        _contentScroll.jumpTo(0);
      }
    }
  }

  _SettingsSectionItem? _customSection(AppLocalizations l, String key) {
    if (key == 'account') {
      return _SettingsSectionItem(
        key: 'account',
        label: l.userAccount,
        subtitle: l.accountSectionDesc,
        widget: const AccountSection(),
      );
    }
    if (key == 'ai') {
      return _SettingsSectionItem(
        key: 'ai',
        label: l.aiAssistant,
        subtitle: l.aiSectionDesc,
        widget: const AiSection(),
      );
    }
    return null;
  }

  List<_SettingsSectionItem> _desktopSections(AppLocalizations l) => [
    _SettingsSectionItem(
      key: 'general',
      label: l.general,
      subtitle: l.generalDesc,
      widget: AppearanceSection(
        onOpenDefaultCalendar: () {
          setState(() => _showingDefaultCalendar = true);
        },
      ),
    ),
    _SettingsSectionItem(
      key: 'calendars',
      label: l.manageCalendars,
      subtitle: l.calendarManagementDesc,
      widget: CalendarSettingsSection(
        onOpenDefaultCalendar: () {
          setState(() => _showingDefaultCalendar = true);
        },
      ),
    ),
    _SettingsSectionItem(
      key: 'data',
      label: l.data,
      subtitle: l.dataSectionDesc,
      widget: DataSection(onSelectSection: _goToSectionKey),
    ),
    _SettingsSectionItem(
      key: 'tags',
      label: l.tags,
      subtitle: l.tagManagementDesc,
      widget: const TagsPage(embedded: true),
    ),
    _SettingsSectionItem(
      key: 'trash',
      label: l.trash,
      subtitle: l.trashDesc,
      widget: const TrashPage(embedded: true),
    ),
    _SettingsSectionItem(
      key: 'io',
      label: l.importAndBackup,
      subtitle: l.ioSectionDesc,
      widget: const ImportExportSection(),
    ),
    if (hasNotificationSettings)
      _SettingsSectionItem(
        key: 'notify',
        label: l.notify,
        subtitle: l.notifySectionDesc,
        widget: const NotificationsSection(),
      ),
    _SettingsSectionItem(
      key: 'sync',
      label: l.sync,
      subtitle: l.syncSectionDesc,
      widget: SyncSection(onGoToAccount: () => _goToSectionKey('account')),
    ),
    _SettingsSectionItem(
      key: 'about',
      label: l.about,
      subtitle: l.aboutDesc,
      widget: AboutSection(version: _cachedVersion ?? ''),
    ),
  ];

  String _mobileTitle(AppLocalizations l, String section) => switch (section) {
    'general' => l.general,
    'calendars' => l.manageCalendars,
    'data' => l.data,
    'tags' => l.tags,
    'trash' => l.trash,
    'io' => l.importAndBackup,
    'notify' => l.notify,
    'sync' => l.sync,
    'account' => l.userAccount,
    'ai' => l.aiAssistant,
    'about' => l.about,
    _ => l.settings,
  };

  String? _mobileSubtitle(AppLocalizations l, String section) => switch (section) {
    'general' => l.generalDesc,
    'calendars' => l.calendarManagementDesc,
    'data' => l.dataSectionDesc,
    'tags' => l.tagManagementDesc,
    'trash' => l.trashDesc,
    'io' => l.ioSectionDesc,
    'notify' => l.notifySectionDesc,
    'sync' => l.syncSectionDesc,
    'account' => l.accountSectionDesc,
    'ai' => l.aiSectionDesc,
    'about' => l.aboutDesc,
    _ => null,
  };

  Widget _mobileSectionWidget(AppLocalizations l, String section) => switch (section) {
    'general' => AppearanceSection(
      onOpenDefaultCalendar: () {
        setState(() => _showingDefaultCalendar = true);
      },
    ),
    'calendars' => CalendarSettingsSection(
      onOpenDefaultCalendar: () {
        setState(() => _showingDefaultCalendar = true);
      },
    ),
    'data' => DataSection(
      onSelectSection: (key) => setState(() => _mobileSection = key),
    ),
    'tags' => const TagsPage(embedded: true),
    'trash' => const TrashPage(embedded: true),
    'io' => const ImportExportSection(),
    'notify' => const NotificationsSection(),
    'sync' => SyncSection(
      onGoToAccount: () => setState(() => _mobileSection = 'account'),
    ),
    'account' => const AccountSection(),
    'ai' => const AiSection(),
    'about' => AboutSection(version: _cachedVersion ?? ''),
    _ => const SizedBox.shrink(),
  };

  Widget _settingsHead(AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 13),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            l.settings,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              height: 1.22,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              l.settingsSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);

    if (!desktop) {
      final calCount = ref.watch(calendarsProvider).valueOrNull?.length ?? 1;

      if (_mobileSection == null) {
        return Scaffold(
          backgroundColor: SpecTokens.wash,
          appBar: DsTopBar(
            title: l.settings,
            subtitle: l.settingsSubtitle,
            leading: DsIconButton(
              icon: CupertinoIcons.back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => _leave(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            children: [
              Container(
                color: SpecTokens.paper,
                child: SettingsRows(
                  children: [
                    SettingsRow(
                      label: l.general,
                      subtitle: l.mobileGeneralDesc,
                      chevron: SettingsChevron.right,
                      onTap: () => setState(() => _mobileSection = 'general'),
                    ),
                    SettingsRow(
                      label: l.manageCalendars,
                      subtitle: l.mobileCalendarsDesc(calCount),
                      chevron: SettingsChevron.right,
                      onTap: () => setState(() => _mobileSection = 'calendars'),
                    ),
                    SettingsRow(
                      label: l.data,
                      subtitle: l.mobileDataDesc,
                      chevron: SettingsChevron.right,
                      onTap: () => setState(() => _mobileSection = 'data'),
                    ),
                    if (hasNotificationSettings)
                      SettingsRow(
                        label: l.notify,
                        subtitle: l.mobileNotifyDesc,
                        chevron: SettingsChevron.right,
                        onTap: () => setState(() => _mobileSection = 'notify'),
                      ),
                    SettingsRow(
                      label: l.sync,
                      subtitle: l.mobileSyncDesc,
                      chevron: SettingsChevron.right,
                      onTap: () => setState(() => _mobileSection = 'sync'),
                    ),
                    SettingsRow(
                      label: l.about,
                      subtitle: l.mobileAboutDesc,
                      chevron: SettingsChevron.right,
                      onTap: () => setState(() => _mobileSection = 'about'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      return Scaffold(
        backgroundColor: SpecTokens.wash,
        appBar: DsTopBar(
          title: _mobileTitle(l, _mobileSection!),
          subtitle: _mobileSubtitle(l, _mobileSection!),
          leading: DsIconButton(
            icon: CupertinoIcons.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () {
              if (_showingDefaultCalendar) {
                setState(() => _showingDefaultCalendar = false);
                return;
              }
              if (_mobileSection == 'tags' ||
                  _mobileSection == 'trash' ||
                  _mobileSection == 'io') {
                setState(() => _mobileSection = 'data');
                return;
              }
              setState(() => _mobileSection = null);
            },
          ),
        ),
        body: _showingDefaultCalendar
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: DefaultCalendarView(
                  onBack: () => setState(() => _showingDefaultCalendar = false),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: SettingsGroupBlock(
                  title: _mobileTitle(l, _mobileSection!),
                  subtitle: _mobileSubtitle(l, _mobileSection!),
                  mobile: true,
                  child: _mobileSectionWidget(l, _mobileSection!),
                ),
              ),
      );
    }

    final sections = _desktopSections(l);
    final selected = _section.clamp(0, sections.length - 1);
    final currentSection = _customSectionKey != null
        ? _customSection(l, _customSectionKey!)!
        : sections[selected];

    return Scaffold(
      backgroundColor: SpecTokens.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _settingsHead(l),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 24, 30, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 176,
                    child: Focus(
                      focusNode: _navFocusNode,
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            if (_section < sections.length - 1) {
                              _selectSection(_section + 1);
                              return KeyEventResult.handled;
                            }
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            if (_section > 0) {
                              _selectSection(_section - 1);
                              return KeyEventResult.handled;
                            }
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < sections.length; i++)
                              SettingsNavItem(
                                label: sections[i].label,
                                selected: _customSectionKey == null &&
                                    !_showingDefaultCalendar &&
                                    selected == i,
                                onTap: () => _selectSection(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 46),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: _showingDefaultCalendar
                            ? SingleChildScrollView(
                                controller: _contentScroll,
                                padding: const EdgeInsets.only(bottom: 80),
                                child: DefaultCalendarView(
                                  onBack: () => setState(
                                    () => _showingDefaultCalendar = false,
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                key: ValueKey(currentSection.key),
                                controller: _contentScroll,
                                padding: const EdgeInsets.only(bottom: 80),
                                child: SettingsGroupBlock(
                                  title: currentSection.label,
                                  subtitle: currentSection.subtitle,
                                  child: currentSection.widget,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _leave(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
    return;
  }
  router?.go('/');
}

class SettingsNavItem extends StatefulWidget {
  const SettingsNavItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<SettingsNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? SpecTokens.wash
        : _hovered
            ? SpecTokens.wash
            : Colors.transparent;

    final fg = widget.selected
        ? SpecTokens.ink
        : _hovered
            ? SpecTokens.ink2
            : SpecTokens.muted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              color: fg,
              fontFamilyFallback: AppTypography.fallback,
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
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);
