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
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}
