import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/calendar/kalender_calendar_event.dart';

CalendaEventAdapter _adapter({
  bool isAllDay = false,
  String? rrule,
}) {
  return CalendaEventAdapter(
    drifId: 1,
    calendarId: 10,
    title: 'Event',
    start: DateTime(2026, 5, 1, 10),
    end: DateTime(2026, 5, 1, 11),
    isAllDay: isAllDay,
    rrule: rrule,
  );
}

void main() {
  group('KalenderCalendarEvent.fromAdapter', () {
    test('plain event is fully interactive', () {
      final event = KalenderCalendarEvent.fromAdapter(_adapter());
      expect(event.interaction.allowRescheduling, isTrue);
      expect(event.interaction.allowStartResize, isTrue);
      expect(event.interaction.allowEndResize, isTrue);
    });

    test('recurring event cannot be dragged or resized (S1 guard)', () {
      final event = KalenderCalendarEvent.fromAdapter(
        _adapter(rrule: 'RRULE:FREQ=DAILY;COUNT=3'),
      );
      expect(event.interaction.allowRescheduling, isFalse);
      expect(event.interaction.allowStartResize, isFalse);
      expect(event.interaction.allowEndResize, isFalse);
    });

    test('all-day event cannot be dragged or resized (S1 guard)', () {
      final event = KalenderCalendarEvent.fromAdapter(
        _adapter(isAllDay: true),
      );
      expect(event.interaction.allowRescheduling, isFalse);
      expect(event.interaction.allowStartResize, isFalse);
      expect(event.interaction.allowEndResize, isFalse);
    });

    test('isAllDay drives multi-day classification regardless of duration',
        () {
      final zeroHour = KalenderCalendarEvent.fromAdapter(
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 10,
          title: 'Zero',
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 5, 1),
          isAllDay: true,
        ),
      );
      expect(zeroHour.isMultiDayEvent, isTrue);

      final oneHourNoDtend = KalenderCalendarEvent.fromAdapter(
        CalendaEventAdapter(
          drifId: 2,
          calendarId: 10,
          title: 'No DTEND',
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 5, 1, 1),
          isAllDay: true,
        ),
      );
      expect(oneHourNoDtend.isMultiDayEvent, isTrue);

      final timed = KalenderCalendarEvent.fromAdapter(_adapter());
      expect(timed.isMultiDayEvent, isFalse);
    });

    test('copyWith preserves adapter and id', () {
      final original = KalenderCalendarEvent.fromAdapter(_adapter());
      final updated = original.copyWith(
        dateTimeRange: DateTimeRange(
          start: DateTime(2026, 5, 2, 10),
          end: DateTime(2026, 5, 2, 11),
        ),
      );
      expect(updated.adapter, same(original.adapter));
      expect(updated.id, original.id);
      expect(updated.start.toLocal(), DateTime(2026, 5, 2, 10));
    });

    test('id is stable for the same adapter instance start', () {
      final a = KalenderCalendarEvent.fromAdapter(_adapter());
      final b = KalenderCalendarEvent.fromAdapter(_adapter());
      expect(a.id, b.id);
    });
  });
}
