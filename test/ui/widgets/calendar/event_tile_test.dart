import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/event_tile.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

void main() {
  group('EventTile', () {
    testWidgets('renders event title', (tester) async {
      final event = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'test',
        title: 'Team Meeting',
        start: DateTime(2026, 4, 17, 10, 0),
        end: DateTime(2026, 4, 17, 11, 0),
        color: const Color(0xFF2563EB),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTile(event: event),
          ),
        ),
      );

      expect(find.text('Team Meeting'), findsOneWidget);
    });

    testWidgets('renders all-day event', (tester) async {
      final event = CalendaEventAdapter(
        drifId: 2,
        calendarId: 10,
        uid: 'allday',
        title: 'Birthday',
        start: DateTime(2026, 4, 17),
        end: DateTime(2026, 4, 18),
        color: const Color(0xFF16A34A),
        isAllDay: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTile(event: event),
          ),
        ),
      );

      expect(find.text('Birthday'), findsOneWidget);
    });

    testWidgets('shows time for non-all-day event', (tester) async {
      final start = DateTime.utc(2026, 4, 17, 9, 30);
      final event = CalendaEventAdapter(
        drifId: 3,
        calendarId: 10,
        uid: 'timed',
        title: 'Sync',
        start: start,
        end: DateTime.utc(2026, 4, 17, 10, 0),
        color: const Color(0xFF2563EB),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTile(event: event),
          ),
        ),
      );

      expect(find.text('Sync'), findsOneWidget);
      // CalendarEvent stores UTC; _formatTime reads dateTimeRange.start (UTC)
      final expected = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('hides time for all-day event', (tester) async {
      final event = CalendaEventAdapter(
        drifId: 4,
        calendarId: 10,
        uid: 'allday2',
        title: 'Holiday',
        start: DateTime(2026, 4, 17),
        end: DateTime(2026, 4, 18),
        color: const Color(0xFF16A34A),
        isAllDay: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTile(event: event),
          ),
        ),
      );

      expect(find.text('Holiday'), findsOneWidget);
      // No time text should be present for all-day events
      expect(find.text('00:00'), findsNothing);
    });
  });
}
