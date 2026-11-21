import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'default_calendar_view.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/calendar_settings_section.dart';
import 'settings_sections/data_section.dart';
import 'settings_sections/notifications_section.dart';
import 'settings_ui.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;
  int _section = 0;
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _groupKeys = [];
  bool _jumping = false;
  bool _showingDefaultCalendar = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncSectionToScroll);
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
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) {
    while (_groupKeys.length <= index) {
      _groupKeys.add(GlobalKey());
    }
    return _groupKeys[index];
  }

  void _syncSectionToScroll() {
    if (_jumping || !_scroll.hasClients) return;
    var current = 0;
    for (var i = 0; i < _groupKeys.length; i++) {
      final render = _groupKeys[i].currentContext?.findRenderObject();
      if (render is! RenderBox) continue;
      final target = RenderAbstractViewport.of(
        render,
      ).getOffsetToReveal(render, 0).offset;
      if (target <= _scroll.offset + 32) current = i;
    }
    if (current != _section) setState(() => _section = current);
  }

  void _goTo(int index) {
    if (_showingDefaultCalendar) {
      setState(() => _showingDefaultCalendar = false);
    }
    setState(() => _section = index);
    final target = _keyFor(index).currentContext;
    if (target == null) return;
    _jumping = true;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0,
    ).whenComplete(() => _jumping = false);
  }

  List<(String, Widget)> _sections(AppLocalizations l) => [
    (
      l.general,
      AppearanceSection(
        onOpenDefaultCalendar: () {
          setState(() => _showingDefaultCalendar = true);
        },
      ),
    ),
    (
      l.calendar,
      CalendarSettingsSection(
        onOpenDefaultCalendar: () {
          setState(() => _showingDefaultCalendar = true);
        },
      ),
    ),
    (l.account, const AccountSection()),
    (l.data, const DataSection()),
    (l.aiAssistant, const AiSection()),
    if (hasNotificationSettings) (l.notifications, const NotificationsSection()),
    (l.about, AboutSection(version: _cachedVersion ?? '')),
  ];

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
    final sections = _sections(l);

    if (!desktop) {
      return Scaffold(
        backgroundColor: SpecTokens.wash,
        appBar: DsTopBar(
          title: l.settings,
          subtitle: l.settingsSubtitle,
          leading: DsIconButton(
            icon: CupertinoIcons.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () {
              if (_showingDefaultCalendar) {
                setState(() => _showingDefaultCalendar = false);
                return;
              }
              _leave(context);
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
            : ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                children: [
                  for (final section in sections)
                    SettingsGroupBlock(
                      title: section.$1,
                      mobile: true,
                      child: section.$2,
                    ),
                ],
              ),
      );
    }

    final selected = _section.clamp(0, sections.length - 1);
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
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < sections.length; i++)
                            _NavItem(
                              label: sections[i].$1,
                              selected:
                                  !_showingDefaultCalendar && selected == i,
                              onTap: () => _goTo(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 46),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 80),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 700),
                          child: _showingDefaultCalendar
                              ? DefaultCalendarView(
                                  onBack: () => setState(
                                    () => _showingDefaultCalendar = false,
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0; i < sections.length; i++)
                                      KeyedSubtree(
                                        key: _keyFor(i),
                                        child: SettingsGroupBlock(
                                          title: sections[i].$1,
                                          child: sections[i].$2,
                                        ),
                                      ),
                                  ],
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

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
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
        defaultTargetPlatform == TargetPlatform.macOS);
