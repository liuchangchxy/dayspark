import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/l10n/app_localizations.dart';

enum CalendarViewMode { day, week, month }

/// Compact day/week/month switcher.
///
/// Sits inline in the calendar toolbar rather than spanning the width — a
/// full-bleed bar reads as the page's primary control, which it is not
/// (DESIGN 页面主标题).
class ViewSwitcher extends StatelessWidget {
  final CalendarViewMode currentMode;
  final ValueChanged<CalendarViewMode> onModeChanged;

  const ViewSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SegmentedButton<CalendarViewMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: CalendarViewMode.day, label: Text(l.day)),
        ButtonSegment(value: CalendarViewMode.week, label: Text(l.week)),
        ButtonSegment(value: CalendarViewMode.month, label: Text(l.month)),
      ],
      selected: {currentMode},
      onSelectionChanged: (s) => onModeChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.surfaceContainerHighest.withValues(alpha: 0.6);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.onSurfaceVariant;
        }),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
