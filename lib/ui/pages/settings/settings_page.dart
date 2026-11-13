import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/calendar_settings_section.dart';
import 'settings_sections/import_export_section.dart';
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
    (l.account, const AccountSection()),
    (l.appearance, const AppearanceSection()),
    (l.calendar, const CalendarSettingsSection()),
    if (hasNotificationSettings) (l.reminders, const NotificationsSection()),
    (l.aiAssistant, const AiSection()),
    (l.data, const ImportExportSection()),
    (l.about, AboutSection(version: _cachedVersion ?? '')),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final sections = _sections(l);

    if (!desktop) {
      return Scaffold(
        backgroundColor: context.ds.bg,
        appBar: DsTopBar(
          title: l.settings,
          leading: DsIconButton(
            icon: CupertinoIcons.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => _leave(context),
          ),
        ),
        body: ListView(
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
    return WorkspacePage(
      // The title belongs to the nav it names, not to the top bar: the bar is
      // pinned to the window edge, so on a wide screen it sat half a window
      // away from the column it introduced and the page read as two.
      title: '',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
        child: Center(
          child: ConstrainedBox(
            // The nav and the column are one object: sizing the pair (not the
            // page) keeps the empty space even on both sides instead of
            // stacking it all to the right of the form.
            constraints: const BoxConstraints(maxWidth: 900),
            child: SizedBox(
              height: double.infinity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      AppSpacing.s1,
                      AppSpacing.s1,
                      AppSpacing.s6,
                    ),
                    child: SizedBox(
                      width: 200,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              // 2 + 12 puts the title on the same left edge as
                              // the nav labels under it.
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.s3 + 2,
                                0,
                                0,
                                AppSpacing.s4,
                              ),
                              child: Text(
                                l.settings,
                                style: AppTypography.title.copyWith(
                                  color: context.ds.ink,
                                ),
                              ),
                            ),
                            for (var i = 0; i < sections.length; i++)
                              _NavItem(
                                label: sections[i].$1,
                                selected: selected == i,
                                onTap: () => _goTo(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, color: context.ds.line),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s6 + AppSpacing.s3,
                        AppSpacing.s1,
                        AppSpacing.s6,
                        AppSpacing.s8,
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
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
        ),
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
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: ds.surface2,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 16,
                    color: selected ? ds.primary : Colors.transparent,
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        fontSize: 13,
                        color: selected ? ds.ink : ds.ink3,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
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
