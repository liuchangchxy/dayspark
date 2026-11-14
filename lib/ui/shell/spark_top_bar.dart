import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/widgets/schedule/month_year_picker.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

/// The Direction C desktop shell: one 56px bar, always present.
///
/// It carries the product mark, the viewed day, the live clock, the next thing
/// on the calendar, the day/week/month switch, quick add, sync state and the
/// account. Every destination sits under it, so the app never grows a second
/// navigation concept per page.
class SparkTopBar extends ConsumerStatefulWidget {
  const SparkTopBar({super.key, this.clock});

  static const double height = 56;

  /// Overrides the wall clock. The bar reads the same clock as the page under
  /// it so the two never print different times.
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
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tab = ref.watch(workspaceTabProvider);
    final browsing = tab != AppTab.action;
    final clock = widget.clock;
    final now = clock != null ? clock() : ref.read(clockNowProvider)();
    final viewed = browsing ? ref.watch(browseDateProvider) : dayOf(now);
    final calendarMode = ref.watch(calendarViewModeProvider);
    final isToday = _sameDay(viewed, now);

    final segment = tab == AppTab.action
        ? _Segment.day
        : calendarMode == CalendarViewMode.month
        ? _Segment.month
        : _Segment.week;

    return Container(
      height: SparkTopBar.height,
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A narrow desktop window keeps the controls that change where you
          // are and drops the read-outs that only inform.
          final roomy = constraints.maxWidth >= 1180;
          final showSync = constraints.maxWidth >= 1120;
          final narrow = constraints.maxWidth < 940;
          final tight = constraints.maxWidth < 860;
          return Row(
            children: [
              // The mark and the full weekday date are the two pieces whose
              // width is set by the locale and the font, not by this file: a
              // wide face at the 1000px breakpoint pushes the row past the
              // edge. Both are flexible so the date ellipsizes instead of
              // overflowing, whichever face the host happens to have.
              const Flexible(child: _Brand()),
              const SizedBox(width: AppSpacing.s4),
              Container(width: 1, height: 20, color: ds.line),
              const SizedBox(width: AppSpacing.s3),
              Flexible(
                child: _DateNav(
                  date: viewed,
                  locale: locale,
                  isToday: isToday,
                  compact: narrow,
                  onPrevious: browsing ? () => _shift(viewed, -1) : null,
                  onNext: browsing ? () => _shift(viewed, 1) : null,
                  onToday: browsing ? () => _goToday(now) : _pickBrowsedDay,
                ),
              ),
              if (roomy && isToday) ...[
                const SizedBox(width: AppSpacing.s4),
                _NowClock(now: now),
                const SizedBox(width: AppSpacing.s3),
                Container(width: 1, height: 12, color: ds.line),
                const SizedBox(width: AppSpacing.s3),
                Flexible(child: _NextUp(now: now)),
              ],
              const Spacer(),
              // Search had no drawn entry on desktop: only Ctrl K opened it,
              // which is a shortcut you have to already know. The phone bar
              // has carried this icon all along.
              DsIconButton(
                key: const ValueKey('nav-search'),
                icon: CupertinoIcons.search,
                tooltip: l.search,
                size: 17,
                compact: true,
                onPressed: () => context.push('/search'),
              ),
              const SizedBox(width: AppSpacing.s2),
              _NavItem(
                key: const ValueKey('nav-todos'),
                label: l.todos,
                icon: CupertinoIcons.checkmark_circle,
                selected: tab == AppTab.todos,
                iconOnly: narrow,
                onTap: () => _selectTodos(),
              ),
              const SizedBox(width: AppSpacing.s3),
              _SegmentControl(
                current: segment,
                onChanged: (s) => _selectSegment(s),
              ),
              const SizedBox(width: AppSpacing.s3),
              _QuickAddButton(
                iconOnly: tight,
                onPressed: () => context.push('/quick-add'),
              ),
              if (showSync) ...[
                const SizedBox(width: AppSpacing.s4),
                const _SyncBadge(),
              ],
              const SizedBox(width: AppSpacing.s3),
              Tooltip(
                message: l.settings,
                child: _Avatar(
                  label: l.meLabel,
                  onTap: () => context.push('/settings'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickBrowsedDay() async {
    final picked = await showMonthYearPicker(
      context,
      initial: dayOf(
        widget.clock?.call() ?? ref.read(clockNowProvider)(),
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(browseDateProvider.notifier).state = dayOf(picked);
    ref.read(todosViewProvider.notifier).state = const TodosDayView();
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.todos);
    _goTab(2);
  }

  void _shift(DateTime viewed, int days) {
    ref.read(browseDateProvider.notifier).state = DateTime(
      viewed.year,
      viewed.month,
      viewed.day + days,
    );
  }

  void _goToday(DateTime now) {
    ref.read(browseDateProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
    );
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.action);
    if (GoRouter.maybeOf(context)?.canPop() ?? false) context.pop();
  }

  void _selectTodos() {
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.todos);
    _goTab(2);
  }

  /// Navigation carries the destination in the URL, so arriving at the app from
  /// another page lands on the tab the bar says is selected instead of falling
  /// back to the startup default.
  void _goTab(int index) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final uri = router.routerDelegate.currentConfiguration.uri;
    final target = uri.queryParameters['tab'] ?? '0';
    if (uri.path == '/' && target == '$index') return;
    router.go(index == 0 ? '/' : '/?tab=$index');
  }

  void _selectSegment(_Segment segment) {
    switch (segment) {
      case _Segment.day:
        ref.read(workspaceTabProvider.notifier).setTab(AppTab.action);
        _goTab(0);
      case _Segment.week:
        ref.read(workspaceTabProvider.notifier).setTab(AppTab.calendar);
        ref
            .read(calendarViewModeProvider.notifier)
            .setViewMode(CalendarViewMode.week);
        _goTab(1);
      case _Segment.month:
        ref.read(workspaceTabProvider.notifier).setTab(AppTab.calendar);
        ref
            .read(calendarViewModeProvider.notifier)
            .setViewMode(CalendarViewMode.month);
        _goTab(1);
    }
  }
}

enum _Segment { day, week, month }

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: ds.primary,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            l.appName.characters.first,
            style: AppTypography.small.copyWith(
              color: ds.onPrimary,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Flexible(
          child: Text(
            l.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyStrong.copyWith(
              color: ds.ink,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _DateNav extends StatelessWidget {
  const _DateNav({
    required this.date,
    required this.locale,
    required this.isToday,
    this.onPrevious,
    this.onNext,
    required this.onToday,
    this.compact = false,
  });

  final DateTime date;
  final String locale;
  final bool isToday;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onToday;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    // ICU patterns carry each locale's own date punctuation and word order;
    // assembling "年/月/日" here would hardcode Chinese and drift from every
    // other locale the app ships.
    final label = compact
        ? DateFormat.MMMd(locale).format(date)
        : DateFormat.yMMMMEEEEd(locale).format(date);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onPrevious != null)
          _StepButton(
            icon: CupertinoIcons.chevron_back,
            onPressed: onPrevious!,
          )
        else
          const SizedBox(width: 28),
        Flexible(
          child: Tooltip(
            message: AppLocalizations.of(context)!.today,
            child: InkWell(
              onTap: onToday,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: 4,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: isToday ? ds.ink : ds.ink2,
                    fontWeight: FontWeight.w500,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onNext != null)
          _StepButton(
            icon: CupertinoIcons.chevron_forward,
            onPressed: onNext!,
          )
        else
          const SizedBox(width: 28),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 14, color: ds.ink3),
        ),
      ),
    );
  }
}

class _NowClock extends StatelessWidget {
  const _NowClock({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: ds.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '${l.actionNow} ${DateFormatters.formatTime(now)}',
          style: AppTypography.small.copyWith(
            color: ds.primary,
            fontWeight: FontWeight.w600,
            fontFeatures: AppTypography.tabular,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _NextUp extends ConsumerWidget {
  const _NextUp({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final events =
        ref.watch(actionProjectionProvider).valueOrNull?.events ?? const [];
    final upcoming =
        events.where((e) => !e.isAllDay && e.start.isAfter(now)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.nextUp, style: AppTypography.small.copyWith(color: ds.ink3)),
        const SizedBox(width: 6),
        Text(
          DateFormatters.formatTime(next.start.toLocal()),
          style: AppTypography.small.copyWith(
            color: ds.ink2,
            fontFeatures: AppTypography.tabular,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            next.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.small.copyWith(
              color: ds.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? ds.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? ds.primary : ds.ink3),
              if (!iconOnly) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AppTypography.small.copyWith(
                    color: selected ? ds.primary : ds.ink2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentControl extends StatelessWidget {
  const _SegmentControl({required this.current, required this.onChanged});

  final _Segment current;
  final ValueChanged<_Segment> onChanged;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final items = <(_Segment, String)>[
      (_Segment.day, l.day),
      (_Segment.week, l.week),
      (_Segment.month, l.month),
    ];
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: ds.free,
        border: Border.all(color: ds.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            MouseRegion(
              key: ValueKey('nav-${items[i].$1.name}'),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(items[i].$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 44,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: items[i].$1 == current
                        ? ds.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: items[i].$1 == current
                          ? ds.line
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    items[i].$2,
                    style: AppTypography.small.copyWith(
                      color: items[i].$1 == current ? ds.ink : ds.ink3,
                      fontWeight: items[i].$1 == current
                          ? FontWeight.w600
                          : FontWeight.w400,
                      height: 1,
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

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.onPressed, this.iconOnly = false});

  final VoidCallback onPressed;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: ds.surface,
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.add, size: 12, color: ds.primary),
              if (!iconOnly) ...[
                const SizedBox(width: 5),
                Text(
                  l.quickAdd,
                  style: AppTypography.small.copyWith(
                    color: ds.ink,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncBadge extends ConsumerWidget {
  const _SyncBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final status = ref.watch(syncStatusProvider);
    final failed = status.lastError != null;
    final at = status.lastSyncAt;
    final label = failed
        ? l.syncPhaseError
        : at == null
        ? l.notSynced
        : l.syncedAt(DateFormatters.formatTime(at.toLocal()));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: failed ? ds.danger : ds.doneInk,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTypography.small.copyWith(
            color: failed ? ds.danger : ds.ink3,
            fontFeatures: AppTypography.tabular,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.onTap});

  final String label;
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
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: ds.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: ds.line),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.small.copyWith(
              color: ds.ink2,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
