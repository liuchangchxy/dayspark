import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_day_header.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_hour_lines.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
  await tester.pump();
}

void main() {
  group('CalendarDayHeader', () {
    testWidgets('shows day number and weekday', (tester) async {
      final date = DateTime(2026, 9, 27);
      await _pump(
        tester,
        CalendarDayHeader(date: date, isToday: false),
      );

      expect(find.text('27'), findsOneWidget);
      // 2026-09-27 is a Sunday; default test locale is en_US.
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('today gets an accent pill, other days do not', (
      tester,
    ) async {
      final date = DateTime(2026, 9, 27);
      await _pump(tester, CalendarDayHeader(date: date, isToday: true));

      final pills = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .toList();
      expect(pills, isNotEmpty);

      await _pump(tester, CalendarDayHeader(date: date, isToday: false));

      final plain = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .toList();
      expect(plain, isEmpty);
    });
  });

  group('CalendarHourLines', () {
    testWidgets('draws full-hour lines only for a full day', (tester) async {
      await _pump(
        tester,
        CalendarHourLines(
          heightPerMinute: 1,
          timeOfDayRange: TimeOfDayRange(
            start: const TimeOfDay(hour: 0, minute: 0),
            end: const TimeOfDay(hour: 23, minute: 59),
          ),
          color: Colors.grey,
        ),
      );

      // 1:00..23:00, edges skipped.
      expect(find.byType(Positioned), findsNWidgets(23));
    });

    testWidgets('clips lines to the visible range', (tester) async {
      await _pump(
        tester,
        CalendarHourLines(
          heightPerMinute: 1,
          timeOfDayRange: TimeOfDayRange(
            start: const TimeOfDay(hour: 8, minute: 0),
            end: const TimeOfDay(hour: 18, minute: 0),
          ),
          color: Colors.grey,
        ),
      );

      // 9:00..17:00.
      expect(find.byType(Positioned), findsNWidgets(9));
    });
  });
}
