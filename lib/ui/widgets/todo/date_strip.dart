import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/widgets/schedule/day_strip.dart';
import 'package:dayspark/ui/widgets/schedule/month_year_picker.dart';

/// The Todo destination's own controls: which list, which day, what to hide.
///
/// The three views are peers in one segmented control, so switching from a day
/// to everything never feels like changing destination.
class DateStrip extends ConsumerWidget {
  const DateStrip({
    super.key,
    required this.view,
    required this.onViewSelected,
    this.trailing = const [],
    this.dueDays = const {},
  });

  final TodosView view;
  final ValueChanged<TodosView> onViewSelected;
  final List<Widget> trailing;
  final Set<DateTime> dueDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = view is TodosDayView ? ref.watch(browseDateProvider) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s2 + 2,
            AppSpacing.s3,
            AppSpacing.s2,
          ),
          child: Builder(
            builder: (context) {
              // One row: the three views share the width, the controls sit at
              // the end. A second line for a lone filter icon read as a stray
              // control rather than part of the same bar.
              final trailingRow = <Widget>[
                IconButton(
                  tooltip: l.calendar,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    CupertinoIcons.calendar,
                    size: 18,
                    color: context.ds.ink2,
                  ),
                  onPressed: () async {
                    final picked = await showMonthYearPicker(
                      context,
                      initial: ref.read(browseDateProvider),
                      today: ref.read(clockNowProvider)(),
                    );
                    if (picked == null) return;
                    _selectDay(ref, picked);
                  },
                ),
                if (day == null)
                  TextButton(
                    onPressed: () => _selectDay(ref, today),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: context.ds.ink2,
                      textStyle: AppTypography.small.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: Text(l.today),
                  ),
                ...trailing,
              ];
              return Row(
                children: [
                  Expanded(child: _views(context, l, today, day, expand: true)),
                  if (trailingRow.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.s2),
                    ...trailingRow,
                  ],
                ],
              );
            },
          ),
        ),
        if (day != null)
          DayStrip(
            selected: day,
            onPick: (next) {
              ref.read(browseDateProvider.notifier).state = dayOf(next);
              if (view is! TodosDayView) onViewSelected(const TodosDayView());
            },
            hasItems: (date) => dueDays.any((due) => _sameDay(due, date)),
          ),
      ],
    );
  }

  Widget _views(
    BuildContext context,
    AppLocalizations l,
    DateTime today,
    DateTime? day, {
    bool expand = false,
  }) {
    return DsSegmented<String>(
      key: const ValueKey('todos-view-switch'),
      height: 30,
      expand: expand,
      selected: view is TodosInboxView
          ? 'unplanned'
          : view is TodosAllView
          ? 'all'
          : 'date',
      options: [
        DsSegmentOption('unplanned', l.inbox),
        DsSegmentOption('all', l.allTasks),
        DsSegmentOption('date', l.byDate),
      ],
      onSelected: (next) {
        switch (next) {
          case 'unplanned':
            if (view is! TodosInboxView) {
              onViewSelected(const TodosInboxView());
            }
            break;
          case 'all':
            if (view is! TodosAllView) {
              onViewSelected(const TodosAllView());
            }
            break;
          case 'date':
            if (view is! TodosDayView) {
              onViewSelected(const TodosDayView());
            }
            break;
        }
      },
    );
  }

  void _selectDay(WidgetRef ref, DateTime day) {
    ref.read(browseDateProvider.notifier).state = dayOf(day);
    if (view is! TodosDayView) onViewSelected(const TodosDayView());
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The backlog card's own header: which list, how much is waiting, and the
/// day strip for the by-date list.
///
/// This is the two-column layout's header. The view names carry the title, so
/// the card needs no separate heading line above them.
class TodoBacklogHead extends ConsumerWidget {
  const TodoBacklogHead({
    super.key,
    required this.view,
    required this.onViewSelected,
    required this.count,
    required this.overdue,
    this.trailing = const [],
    this.dueDays = const {},
  });

  final TodosView view;
  final ValueChanged<TodosView> onViewSelected;
  final int count;
  final int overdue;
  final List<Widget> trailing;
  final Set<DateTime> dueDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final day = view is TodosDayView ? ref.watch(browseDateProvider) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4 + 2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.line)),
          ),
          child: Row(
            children: [
              DsSegmented<String>(
                key: const ValueKey('todos-view-switch'),
                height: 30,
                selected: view is TodosInboxView
                    ? 'unplanned'
                    : view is TodosAllView
                    ? 'all'
                    : 'date',
                options: [
                  DsSegmentOption('unplanned', l.inbox),
                  DsSegmentOption('all', l.allTasks),
                  DsSegmentOption('date', l.byDate),
                ],
                onSelected: (next) {
                  switch (next) {
                    case 'unplanned':
                      if (view is! TodosInboxView) {
                        onViewSelected(const TodosInboxView());
                      }
                      break;
                    case 'all':
                      if (view is! TodosAllView) {
                        onViewSelected(const TodosAllView());
                      }
                      break;
                    case 'date':
                      if (view is! TodosDayView) {
                        onViewSelected(const TodosDayView());
                      }
                      break;
                  }
                },
              ),
              const SizedBox(width: AppSpacing.s3),
              Flexible(
                child: Text(
                  overdue > 0
                      ? '${l.dayItemCount(count)} · ${l.overdue} $overdue'
                      : l.dayItemCount(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.small.copyWith(
                    color: overdue > 0 ? ds.danger : ds.ink3,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                key: const ValueKey('todo-month-picker'),
                tooltip: l.calendar,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  CupertinoIcons.calendar,
                  size: 18,
                  color: ds.ink2,
                ),
                onPressed: () async {
                  final picked = await showMonthYearPicker(
                    context,
                    initial: ref.read(browseDateProvider),
                    today: ref.read(clockNowProvider)(),
                  );
                  if (picked == null) return;
                  ref.read(browseDateProvider.notifier).state = dayOf(picked);
                  if (view is! TodosDayView) {
                    onViewSelected(const TodosDayView());
                  }
                },
              ),
              ...trailing,
            ],
          ),
        ),
        if (day != null)
          DayStrip(
            selected: day,
            onPick: (next) {
              ref.read(browseDateProvider.notifier).state = dayOf(next);
              if (view is! TodosDayView) onViewSelected(const TodosDayView());
            },
            hasItems: (date) => dueDays.any((due) => _sameDay(due, date)),
          ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The same controls laid out for the desktop list pane: the segmented control
/// stays, the week strip loses its outer margins.
class TodoDesktopToolbar extends StatelessWidget {
  const TodoDesktopToolbar({
    super.key,
    required this.view,
    required this.onViewSelected,
    this.trailing = const [],
    this.dueDays = const {},
  });

  final TodosView view;
  final ValueChanged<TodosView> onViewSelected;
  final List<Widget> trailing;
  final Set<DateTime> dueDays;

  @override
  Widget build(BuildContext context) {
    return DateStrip(
      view: view,
      onViewSelected: onViewSelected,
      trailing: trailing,
      dueDays: dueDays,
    );
  }
}
