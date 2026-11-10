import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// Horizontal day browser: three days back, six forward.
///
/// The selected day is a filled circle, everything else stays quiet; a dot
/// marks days that carry something, so the strip doubles as a density hint.
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.selected,
    required this.onPick,
    this.hasItems,
    this.before = 3,
    this.after = 6,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s4,
      2,
      AppSpacing.s4,
      AppSpacing.s3,
    ),
  });

  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final bool Function(DateTime day)? hasItems;
  final int before;
  final int after;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final days = [
      for (var i = -before; i <= after; i++)
        DateTime(selected.year, selected.month, selected.day + i),
    ];
    return SizedBox(
      height: 68,
      child: ListView.separated(
        key: const ValueKey('date-strip-week'),
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final day = days[index];
          return _DayCell(
            key: ValueKey(DayStrip.dayKey(day)),
            date: day,
            selected: _sameDay(day, selected),
            today: _sameDay(day, DateTime.now()),
            hasItems: hasItems?.call(day) ?? false,
            weekday: _weekdayLabel(locale, day),
            onTap: () => onPick(day),
          );
        },
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.date,
    required this.selected,
    required this.today,
    required this.hasItems,
    required this.weekday,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool hasItems;
  final String weekday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: SizedBox(
            width: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekday,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: selected ? ds.primary : ds.ink3,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? ds.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? ds.onPrimary
                          : today
                          ? ds.primary
                          : ds.ink,
                      fontFeatures: AppTypography.tabular,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: hasItems
                        ? (selected
                              ? ds.primary
                              : ds.primary.withValues(alpha: .55))
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _weekdayLabel(String locale, DateTime date) {
  final full = DateFormat.E(locale).format(date);
  if (locale.startsWith('zh') && full.isNotEmpty) {
    return full.endsWith('周') ? full : full.substring(full.length - 1);
  }
  return full;
}
