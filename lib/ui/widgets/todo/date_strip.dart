import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class DateStrip extends StatelessWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onDateSelected;
  final VoidCallback? onCalendarTap;

  const DateStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.onCalendarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final locale = Localizations.localeOf(context).toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Inbox chip
          _chip(
            context: context,
            label: l.inbox,
            selected: selectedDate == null,
            accentColor: theme.colorScheme.tertiary,
            onTap: () => onDateSelected(null),
          ),
          const SizedBox(width: 4),
          // Left arrow
          IconButton(
            icon: const Icon(CupertinoIcons.chevron_left, size: 16),
            onPressed: () {
              final base = selectedDate ?? today;
              onDateSelected(base.subtract(const Duration(days: 7)));
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Date chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(15, (i) {
                  final date = today
                      .subtract(const Duration(days: 7))
                      .add(Duration(days: i));
                  final isSelected =
                      selectedDate != null &&
                      selectedDate!.year == date.year &&
                      selectedDate!.month == date.month &&
                      selectedDate!.day == date.day;
                  final isCurrentDay =
                      date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final weekday = DateFormat.E(
                    locale,
                  ).format(date).substring(0, 2);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () => onDateSelected(date),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : isCurrentDay
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          border: isCurrentDay && !isSelected
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
                              weekday,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.textTheme.bodySmall?.color,
                              ),
                            ),
                            Text(
                              '${date.day}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCurrentDay
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
          ),
          // Right arrow
          IconButton(
            icon: const Icon(CupertinoIcons.chevron_right, size: 16),
            onPressed: () {
              final base = selectedDate ?? today;
              onDateSelected(base.add(const Duration(days: 7)));
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Calendar button
          if (onCalendarTap != null)
            IconButton(
              icon: const Icon(CupertinoIcons.calendar, size: 18),
              onPressed: onCalendarTap,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }
}
