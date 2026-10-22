import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/ui/widgets/calendar/task_allocation_tile.dart';
import 'package:flutter/cupertino.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'deadline lane filters visible civil date and opens todo details',
    (tester) async {
      CalendarDeadline? selected;
      final deadline = CalendarDeadline(
        todoId: 8,
        title: 'Submit report',
        due: DateTime(2026, 10, 23, 18),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CalendarDeadlineLane(
              dates: [DateTime(2026, 10, 23)],
              deadlines: [
                deadline,
                CalendarDeadline(
                  todoId: 9,
                  title: 'Outside visible range',
                  due: DateTime(2026, 10, 24),
                ),
              ],
              onTapped: (value) => selected = value,
            ),
          ),
        ),
      );
      expect(find.textContaining('Submit report'), findsOneWidget);
      expect(find.textContaining('Outside visible range'), findsNothing);
      await tester.tap(find.textContaining('Submit report'));
      expect(selected, same(deadline));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scheduled work has a non-color checkbox cue and handles narrow tiles',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 90,
              height: 44,
              child: TaskAllocationTile(
                allocation: TaskAllocationCalendarAdapter(
                  id: 1,
                  todoId: 2,
                  todoTitle: '很长的任务标题 A long scheduled task title',
                  start: DateTime(2026, 10, 23, 9),
                  end: DateTime(2026, 10, 23, 10),
                ),
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(CupertinoIcons.square), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(TaskAllocationTile));
      expect(tapped, isTrue);
    },
  );
}
