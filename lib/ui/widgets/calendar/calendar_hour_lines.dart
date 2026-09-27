import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';

/// Hour grid for kalender day/week bodies: full-hour lines only.
///
/// Replaces kalender's default HourLines (adaptive half-hour segments read
/// as prison bars on dark backgrounds). Placed with Positioned.fill by
/// kalender, same contract as the default: a Stack of full-width lines.
@immutable
class CalendarHourLines extends StatelessWidget {
  final double heightPerMinute;
  final TimeOfDayRange timeOfDayRange;
  final Color color;

  const CalendarHourLines({
    super.key,
    required this.heightPerMinute,
    required this.timeOfDayRange,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final startMinutes =
        timeOfDayRange.start.hour * 60 + timeOfDayRange.start.minute;
    final endMinutes =
        timeOfDayRange.end.hour * 60 + timeOfDayRange.end.minute;
    final totalHeight = (endMinutes - startMinutes) * heightPerMinute;
    // First full hour strictly inside the range; skip both edges so lines
    // never double up with the header/day separators.
    final firstHour = startMinutes ~/ 60 + 1;
    final lastHour = (endMinutes - 1) ~/ 60;
    final lines = <Widget>[];
    for (var h = firstHour; h <= lastHour; h++) {
      final y = (h * 60 - startMinutes) * heightPerMinute;
      if (y <= 0.5 || y >= totalHeight - 0.5) continue;
      lines.add(
        Positioned(
          top: y,
          left: 0,
          right: 0,
          child: Container(height: 1, color: color),
        ),
      );
    }
    return Stack(children: lines);
  }
}
