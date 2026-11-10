import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/widgets/schedule/day_strip.dart';

/// The Todo destination's own controls: which list, which day, what to hide.
///
/// The three views are peers in one segmented control, so switching from a day
/// to everything never feels like changing destination.
class DateStrip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = view is TodosDayView ? (view as TodosDayView).day : null;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Below the prototype's wrap point the three views take the whole
              // row and the trailing controls drop to a second line, so a long
              // label can never push the filter control off screen.
              final wrap = constraints.maxWidth < 430;
              final trailingRow = <Widget>[
                if (day == null)
                  TextButton(
                    onPressed: () => onViewSelected(TodosDayView(today)),
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
              if (!wrap) {
                return Row(
                  children: [
                    _views(context, l, today, day),
                    const Spacer(),
                    ...trailingRow,
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _views(context, l, today, day, expand: true),
                  if (trailingRow.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: trailingRow,
                    ),
                ],
              );
            },
          ),
        ),
        if (day != null)
          DayStrip(
            selected: day,
            onPick: (next) => onViewSelected(TodosDayView(next)),
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
              onViewSelected(TodosDayView(day ?? today));
            }
            break;
        }
      },
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
