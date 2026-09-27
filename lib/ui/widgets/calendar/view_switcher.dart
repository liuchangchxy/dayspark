import 'package:flutter/material.dart';
import 'package:dayspark/l10n/app_localizations.dart';

enum CalendarViewMode { day, week, month }

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
    final scheme = Theme.of(context).colorScheme;
    // Compact control, not a full-bleed bar (mobile stays full width).
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<CalendarViewMode>(
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
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.labelLarge,
          ),
          // Surface track, accent pill for selected — no full-bleed bar.
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.surfaceContainerHighest.withValues(alpha: 0.5);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onPrimary;
            }
            return scheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
          ),
        ),
      ),
    );
  }
}
