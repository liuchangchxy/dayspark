import 'dart:async';

import 'package:flutter/cupertino.dart';
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
  const SparkTopBar({super.key, this.clock});

  static const double height = 52;

  final DateTime Function()? clock;

  @override
  ConsumerState<SparkTopBar> createState() => _SparkTopBarState();
}

class _SparkTopBarState extends ConsumerState<SparkTopBar> {
  Timer? _ticker;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Container(
          height: SparkTopBar.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1.0)),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SpecTokens.ink,
                  borderRadius: BorderRadius.circular(4),
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
              const SizedBox(width: 14),
              Row(
                children: [
                  _DesktopNavButton(
                    label: l.today,
                    selected: tab == AppTab.action,
                    onTap: () => _goToday(now),
                  ),
                  _DesktopNavButton(
                    key: const ValueKey('nav-todos'),
                    label: l.todos,
                    selected: tab == AppTab.todos,
                    onTap: () => _selectTodos(),
                  ),
                  _DesktopNavButton(
                    label: l.calendar,
                    selected: tab == AppTab.calendar,
                    onTap: () => _selectCalendar(),
                  ),
                ],
              ),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: const ValueKey('nav-search'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push('/search'),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: SpecTokens.wash,
                      border: Border.all(color: SpecTokens.hair2, width: 1.0),
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
                          const SizedBox(width: 5),
                          Text(
                            l.search,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: SpecTokens.muted,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                        ],
                        if (isWide) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: SpecTokens.hair2, width: 1.0),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              '⌘ K',
                              style: TextStyle(
                                fontSize: 9.5,
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
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push('/quick-add'),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: SpecTokens.ink,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.plus,
                          size: 12,
                          color: SpecTokens.paper,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l.captureQuickAddLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SpecTokens.paper,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: 10),
                Text(
                  DateFormatters.formatTime(now),
                  style: const TextStyle(
                    fontSize: 12,
                    color: SpecTokens.faint,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Tooltip(
                message: l.settings,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/settings'),
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: SpecTokens.hair,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        l.meLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: SpecTokens.ink2,
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
    _goTab(1);
  }

  void _goToday(DateTime now) {
    ref.read(viewedDateProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
    );
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.action);
    _goTab(0);
  }

  void _selectTodos() {
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.todos);
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
    final bg = widget.selected
        ? SpecTokens.hair
        : _hovered
            ? SpecTokens.wash
            : Colors.transparent;
    final fg = widget.selected
        ? SpecTokens.ink
        : _hovered
            ? SpecTokens.ink
            : SpecTokens.muted;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
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
      ),
    );
  }
}
