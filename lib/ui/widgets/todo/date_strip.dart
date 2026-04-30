import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class DateStrip extends StatelessWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onDateSelected;
  final VoidCallback? onCalendarTap;
  final bool showAllMode;
  final VoidCallback? onShowAll;

  const DateStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.onCalendarTap,
    this.showAllMode = false,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final locale = Localizations.localeOf(context).toString();

    // Anchor to selected date or today; align to start of week (Monday)
    final anchor = selectedDate ?? today;
    final weekday = anchor.weekday; // 1=Mon .. 7=Sun
    final weekStart = anchor.subtract(Duration(days: weekday - 1));

    final monthLabel = DateFormat.yM(locale).format(anchor);
    final showTodayButton =
        selectedDate != null &&
        (selectedDate!.year != today.year ||
            selectedDate!.month != today.month ||
            selectedDate!.day != today.day);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: month label + today + calendar + todo box
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showTodayButton)
                TextButton(
                  onPressed: () => onDateSelected(today),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l.today,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(CupertinoIcons.calendar, size: 18),
                onPressed: onCalendarTap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              _chip(
                context: context,
                label: l.allTasks,
                selected: showAllMode,
                accentColor: theme.colorScheme.primary,
                onTap: () => onShowAll?.call(),
              ),
              const SizedBox(width: 4),
              _chip(
                context: context,
                label: l.inbox,
                selected: selectedDate == null && !showAllMode,
                accentColor: theme.colorScheme.tertiary,
                onTap: () => onDateSelected(null),
              ),
            ],
          ),
          // Date row: left arrow + 7 days + right arrow
          Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                onPressed: () {
                  final newWeekStart = weekStart.subtract(
                    const Duration(days: 7),
                  );
                  // Use weekday offset within the displayed week (0-6)
                  final offset = (selectedDate ?? today)
                      .difference(weekStart)
                      .inDays
                      .clamp(0, 6);
                  onDateSelected(newWeekStart.add(Duration(days: offset)));
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(7, (i) {
                    final date = weekStart.add(Duration(days: i));
                    final isSelected =
                        selectedDate != null &&
                        selectedDate!.year == date.year &&
                        selectedDate!.month == date.month &&
                        selectedDate!.day == date.day;
                    final isToday =
                        date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    final weekdayLabel = DateFormat.E(
                      locale,
                    ).format(date).characters.take(2).toString();

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onDateSelected(
                          DateTime(date.year, date.month, date.day),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : isToday
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            border: isToday && !isSelected
                                ? Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                weekdayLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.textTheme.bodySmall?.color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_right, size: 18),
                onPressed: () {
                  final newWeekStart = weekStart.add(const Duration(days: 7));
                  final offset = (selectedDate ?? today)
                      .difference(weekStart)
                      .inDays
                      .clamp(0, 6);
                  onDateSelected(newWeekStart.add(Duration(days: offset)));
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required BuildContext context,
    required String label,
    required bool selected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accentColor : null,
          borderRadius: BorderRadius.circular(16),
          border: !selected
              ? Border.all(color: theme.dividerColor, width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.onTertiary
                : theme.textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }
}
