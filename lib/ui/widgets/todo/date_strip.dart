import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

/// The Todo destination's own controls. Today, Inbox and All are *views* of
/// Todo — they live here, inside the destination, rather than competing with
/// Action and Calendar as top-level destinations.
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.view,
    required this.onViewSelected,
    this.sixThingsMode = false,
    this.onSixThingsToggle,
  });

  final TodosView view;
  final ValueChanged<TodosView> onViewSelected;
  final bool sixThingsMode;
  final VoidCallback? onSixThingsToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final locale = Localizations.localeOf(context).toString();
    final selectedDate = view is TodosDayView ? (view as TodosDayView).day : null;

    final anchor = selectedDate ?? today;
    final weekStart = anchor.subtract(Duration(days: anchor.weekday - 1));

    final monthLabel = DateFormat.yM(locale).format(anchor);
    final showTodayButton = selectedDate != null && selectedDate != today;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title,
                ),
              ),
              if (showTodayButton)
                TextButton(
                  onPressed: () => onViewSelected(TodosDayView(today)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  child: Text(
                    l.today,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  context: context,
                  label: l.allTasks,
                  selected: view is TodosAllView,
                  accentColor: theme.colorScheme.primary,
                  onTap: () => onViewSelected(const TodosAllView()),
                ),
                const SizedBox(width: AppSpacing.xs),
                _filterChip(
                  context: context,
                  label: l.inbox,
                  selected: view is TodosInboxView,
                  accentColor: theme.colorScheme.tertiary,
                  onTap: () => onViewSelected(const TodosInboxView()),
                ),
                const SizedBox(width: AppSpacing.xs),
                _filterChip(
                  context: context,
                  label: l.sixThings,
                  selected: sixThingsMode,
                  accentColor: theme.colorScheme.secondary,
                  onTap: () => onSixThingsToggle?.call(),
                ),
              ],
            ),
          ),
          // The week strip only means something while a day is selected; All
          // and Inbox are not attached to a date, so they drop it rather than
          // leave a dead control on screen.
          if (selectedDate != null)
            Row(
              key: const ValueKey('date-strip-week'),
              children: [
                IconButton(
                  icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                  onPressed: () =>
                      onViewSelected(TodosDayView(_shiftWeek(anchor, weekStart, -7))),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(7, (i) {
                      final date = weekStart.add(Duration(days: i));
                      final isSelected = date == selectedDate;
                      final isToday = date == today;
                      final weekdayLabel = DateFormat.E(
                        locale,
                      ).format(date).characters.take(2).toString();

                      return Expanded(
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () => onViewSelected(TodosDayView(date)),
                            borderRadius: BorderRadius.circular(8),
                            child: Center(
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : isToday
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.3,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isToday && !isSelected
                                      ? Border.all(
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      weekdayLabel,
                                      style: TextStyle(
                                        fontSize:
                                            AppTypography.overline.fontSize,
                                        color: isSelected
                                            ? theme.colorScheme.onPrimary
                                            : context.semantic.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: AppTypography.body.fontSize,
                                        fontWeight: isToday
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? theme.colorScheme.onPrimary
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.chevron_right, size: 18),
                  onPressed: () =>
                      onViewSelected(TodosDayView(_shiftWeek(anchor, weekStart, 7))),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Keep the weekday the user was on when moving a week, clamped to the week
  /// that is actually on screen.
  static DateTime _shiftWeek(DateTime anchor, DateTime weekStart, int days) {
    final offset = anchor.difference(weekStart).inDays.clamp(0, 6);
    return weekStart.add(Duration(days: days + offset));
  }
}

/// The same controls as [DateStrip], laid out for the desktop content origin
/// rather than for a full-width phone row.
class TodoDesktopToolbar extends StatelessWidget {
  const TodoDesktopToolbar({
    super.key,
    required this.view,
    required this.onViewSelected,
    this.sixThingsMode = false,
    this.onSixThingsToggle,
    this.trailing = const [],
  });

  final TodosView view;
  final ValueChanged<TodosView> onViewSelected;
  final bool sixThingsMode;
  final VoidCallback? onSixThingsToggle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate = view is TodosDayView ? (view as TodosDayView).day : null;
    final anchor = selectedDate ?? today;
    final showTodayButton = selectedDate != null && selectedDate != today;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            DateFormat.yM(locale).format(anchor),
            style: AppTypography.title,
          ),
          const SizedBox(width: AppSpacing.sm),
          if (showTodayButton)
            TextButton(
              onPressed: () => onViewSelected(TodosDayView(today)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(
                l.today,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(
                    context: context,
                    label: l.allTasks,
                    selected: view is TodosAllView,
                    accentColor: theme.colorScheme.primary,
                    onTap: () => onViewSelected(const TodosAllView()),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _filterChip(
                    context: context,
                    label: l.inbox,
                    selected: view is TodosInboxView,
                    accentColor: theme.colorScheme.tertiary,
                    onTap: () => onViewSelected(const TodosInboxView()),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _filterChip(
                    context: context,
                    label: l.sixThings,
                    selected: sixThingsMode,
                    accentColor: theme.colorScheme.secondary,
                    onTap: () => onSixThingsToggle?.call(),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          ...trailing,
        ],
      ),
    );
  }
}

Widget _filterChip({
  required BuildContext context,
  required String label,
  required bool selected,
  required Color accentColor,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(context);
  return Semantics(
    button: true,
    label: label,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? accentColor : null,
            borderRadius: BorderRadius.circular(8),
            border: !selected
                ? Border.all(color: theme.dividerColor)
                : null,
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: selected
                  ? theme.colorScheme.onTertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );
}
