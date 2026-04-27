import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

void main() {
  group('CalendaEventAdapter', () {
    test('creates from manual fields', () {
      final adapter = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'test-uid',
        title: 'Team Meeting',
        description: 'Weekly sync',
        color: const Color(0xFF2563EB),
        start: DateTime(2026, 4, 17, 10),
        end: DateTime(2026, 4, 17, 11),
      );

      // CalendarEvent converts dates to UTC internally
      expect(adapter.drifId, 1);
      expect(adapter.title, 'Team Meeting');
      expect(adapter.start, DateTime(2026, 4, 17, 10).toUtc());
      expect(adapter.end, DateTime(2026, 4, 17, 11).toUtc());
      expect(adapter.description, 'Weekly sync');
      expect(adapter.color, const Color(0xFF2563EB));
    });

    test('copyWithData preserves id', () {
      final original = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'uid',
        title: 'Old Title',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );

      final copied = original.copyWithData(title: 'New Title');
      expect(copied.title, 'New Title');
      expect(copied.id, original.id);
      expect(copied.drifId, 1);
    });

    test('equality works for same-id events', () {
      final a = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'uid',
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );
      final b = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'uid',
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );
      // Give b the same id so base-class equality sees them as identical layout
      b.id = a.id;

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toCreateCompanion converts to Drift EventsCompanion', () {
      final start = DateTime(2026, 4, 17, 10);
      final end = DateTime(2026, 4, 17, 11);
      final adapter = CalendaEventAdapter(
        drifId: 0,
        calendarId: 5,
        uid: 'new-uid',
        title: 'New Event',
        description: 'Desc',
        start: start,
        end: end,
        isAllDay: false,
      );

      final companion = adapter.toCreateCompanion();
      expect(companion.calendarId.value, 5);
      expect(companion.summary.value, 'New Event');
      // CalendarEvent stores UTC; companion should carry the original (non-UTC) values
      // because toCreateCompanion reads dateTimeRange.start which is UTC-converted
      expect(companion.startDt.value, start.toUtc());
      expect(companion.endDt.value, end.toUtc());
      expect(companion.isAllDay.value, false);
    });
  });
}
