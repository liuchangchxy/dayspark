import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

/// The Direction C desktop shell: one 52px bar, always present.
class SparkTopBar extends ConsumerStatefulWidget {
  const SparkTopBar({super.key, this.clock, this.onSelect});

  static const double height = 52;

  final DateTime Function()? clock;
  final ValueChanged<int>? onSelect;

  @override
  ConsumerState<SparkTopBar> createState() => _SparkTopBarState();
}

class _SparkTopBarState extends ConsumerState<SparkTopBar> {
  Timer? _ticker;
  bool _searchHovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.clock != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tab = ref.watch(workspaceTabProvider);
    final now = (widget.clock ?? DateTime.now)();
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final shortcutText = isMac ? '\u2318 K' : 'Ctrl K';

    final topPadding = MediaQuery.of(context).padding.top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Container(
          height: SparkTopBar.height + topPadding,
          padding: EdgeInsets.fromLTRB(24, topPadding, 24, 0),
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1.0)),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SpecTokens.ink,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'D',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: Colors.white,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'DaySpark',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.13,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              const SizedBox(width: 26),
              Row(
                children: [
                  _DesktopNavButton(
                    key: const ValueKey('nav-today'),
                    label: l.today,
                    selected: tab == AppTab.action,
                    onTap: () => _goToday(now),
                  ),
                  const SizedBox(width: 4),
                  _DesktopNavButton(
                    key: const ValueKey('nav-todos'),
                    label: l.todos,
                    selected: tab == AppTab.todos,
                    onTap: () => _selectTodos(),
                  ),
                  const SizedBox(width: 4),
                  _DesktopNavButton(
                    key: const ValueKey('nav-calendar'),
                    label: l.calendar,
                    selected: tab == AppTab.calendar,
                    onTap: () => _selectCalendar(),
                  ),
                ],
              ),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _searchHovered = true),
                onExit: (_) => setState(() => _searchHovered = false),
                child: GestureDetector(
                  key: const ValueKey('nav-search'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push('/search'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Align(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Container(
                        key: const ValueKey('nav-search-visual'),
                        height: 29,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: _searchHovered
                              ? SpecTokens.wash
                              : Colors.transparent,
                          border: Border.all(
                            color: SpecTokens.hair2,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.search,
                              size: 12,
                              color: SpecTokens.muted,
                            ),
                            if (isWide) ...[
                              const SizedBox(width: 6),
                              Text(
                                l.search,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: SpecTokens.muted,
                                  fontFamilyFallback: AppTypography.fallback,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: SpecTokens.hair2,
                                    width: 1.0,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  shortcutText,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: SpecTokens.faint,
                                    fontFamilyFallback: AppTypography.fallback,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: 13),
                Text(
                  DateFormatters.formatTime(now),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpecTokens.ink2,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
              const SizedBox(width: 13),
              Tooltip(
                message: l.settings,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/settings'),
                    child: Container(
                      width: 27,
                      height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBFBF8),
                        shape: BoxShape.circle,
                        border: Border.all(color: SpecTokens.hair2, width: 1.0),
                      ),
                      child: Text(
                        l.meLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: SpecTokens.muted,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _selectCalendar() {
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.calendar);
    widget.onSelect?.call(1);
    _goTab(1);
  }

  void _goToday(DateTime now) {
    ref.read(viewedDateProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
    );
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.action);
    widget.onSelect?.call(0);
    _goTab(0);
  }

  void _selectTodos() {
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.todos);
    widget.onSelect?.call(2);
    _goTab(2);
  }

  void _goTab(int index) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final uri = router.routerDelegate.currentConfiguration.uri;
    final target = uri.queryParameters['tab'] ?? '0';
    if (uri.path == '/' && target == '$index') return;
    router.go(index == 0 ? '/' : '/?tab=$index');
  }
}

class _DesktopNavButton extends StatefulWidget {
  const _DesktopNavButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DesktopNavButton> createState() => _DesktopNavButtonState();
}

class _DesktopNavButtonState extends State<_DesktopNavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected
        ? SpecTokens.ink
        : _hovered
            ? SpecTokens.ink
            : SpecTokens.muted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered && !widget.selected ? SpecTokens.wash : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? SpecTokens.ink : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
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
