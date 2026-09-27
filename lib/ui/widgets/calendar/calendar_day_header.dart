import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// Day-column header for kalender day/week views.
///
/// Replaces kalender's default DayHeader (grey two-liner with an IconButton
/// circle): big date number + weekday, today picked out in accent.
@immutable
class CalendarDayHeader extends StatelessWidget {
  final DateTime date;
  final bool isToday;

  const CalendarDayHeader({
    super.key,
    required this.date,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final weekday = DateFormat.E(
      Localizations.localeOf(context).toString(),
    ).format(date);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: isToday
              ? BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Text(
            date.day.toString(),
            style: AppTypography.headline.copyWith(
              color: isToday ? accent : theme.colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          weekday,
          style: AppTypography.caption.copyWith(
            color: isToday ? accent : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
