import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

void main() {
  group('CalendaEventAdapter', () {
    test('creates from manual fields', () {
      final adapter = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Team Meeting',
        description: 'Weekly sync',
        color: const Color(0xFF2563EB),
        start: DateTime(2026, 4, 17, 10),
        end: DateTime(2026, 4, 17, 11),
      );

      expect(adapter.drifId, 1);
      expect(adapter.title, 'Team Meeting');
      expect(adapter.start, DateTime(2026, 4, 17, 10));
      expect(adapter.end, DateTime(2026, 4, 17, 11));
      expect(adapter.description, 'Weekly sync');
      expect(adapter.color, const Color(0xFF2563EB));
    });

    test('copyWithData preserves drifId', () {
      final original = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Old Title',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );

      final copied = original.copyWithData(title: 'New Title');
      expect(copied.title, 'New Title');
      expect(copied.drifId, original.drifId);
    });

    test('a plain adapter keeps its series anchor glued to its own times', () {
      final adapter = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Event',
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );

      expect(adapter.seriesStart, adapter.start);
      expect(adapter.seriesEnd, adapter.end);
      expect(adapter.isRecurringOccurrence, isFalse);

      // The drag path reschedules by moving start/end; the anchor must follow
      // or the write would land on the stale time.
      final moved = adapter.copyWithData(
        start: DateTime(2026, 1, 2, 9),
        end: DateTime(2026, 1, 2, 10),
      );
      expect(moved.seriesStart, DateTime(2026, 1, 2, 9));
      expect(moved.seriesEnd, DateTime(2026, 1, 2, 10));
    });

    test('an occurrence never moves its series anchor by accident', () {
      final seriesStart = DateTime(2026, 10, 1, 9);
      final seriesEnd = DateTime(2026, 10, 1, 9, 30);
      final occurrenceStart = DateTime(2026, 10, 3, 9);
      final occurrence = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Daily standup',
        start: occurrenceStart,
        end: DateTime(2026, 10, 3, 9, 30),
        seriesStart: seriesStart,
        seriesEnd: seriesEnd,
        occurrenceStart: occurrenceStart,
        rrule: 'FREQ=DAILY;COUNT=5',
      );

      expect(occurrence.isRecurringOccurrence, isTrue);
      expect(occurrence.seriesStart, seriesStart);

      final renamed = occurrence.copyWithData(title: 'Renamed');
      expect(renamed.seriesStart, seriesStart);
      expect(renamed.seriesEnd, seriesEnd);

      // Even moving the rendered times leaves the anchor alone: the caller has
      // to name the anchor to move it.
      final nudged = occurrence.copyWithData(
        start: DateTime(2026, 10, 3, 11),
        end: DateTime(2026, 10, 3, 11, 30),
      );
      expect(nudged.start, DateTime(2026, 10, 3, 11));
      expect(nudged.seriesStart, seriesStart);
      expect(nudged.seriesEnd, seriesEnd);

      final moved = occurrence.copyWithData(
        seriesStart: DateTime(2026, 10, 1, 11),
        seriesEnd: DateTime(2026, 10, 1, 11, 30),
      );
      expect(moved.seriesStart, DateTime(2026, 10, 1, 11));
      expect(moved.seriesEnd, DateTime(2026, 10, 1, 11, 30));
    });

    test('toUpdateCompanion writes the series anchor, not the occurrence', () {
      final seriesStart = DateTime(2026, 10, 1, 9);
      final seriesEnd = DateTime(2026, 10, 1, 9, 30);
      final occurrence = CalendaEventAdapter(
        drifId: 7,
        calendarId: 10,
        title: 'Daily standup',
        start: DateTime(2026, 10, 3, 9),
        end: DateTime(2026, 10, 3, 9, 30),
        seriesStart: seriesStart,
        seriesEnd: seriesEnd,
        occurrenceStart: DateTime(2026, 10, 3, 9),
        rrule: 'FREQ=DAILY;COUNT=5',
      );

      final companion = occurrence
          .copyWithData(title: 'Renamed')
          .toUpdateCompanion();

      expect(companion.startDt.value, seriesStart);
      expect(companion.endDt.value, seriesEnd);
      expect(companion.summary.value, 'Renamed');
      expect(companion.rrule.value, 'FREQ=DAILY;COUNT=5');
    });

    test('copyWithData can clear description and location', () {
      final adapter = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
        description: 'old description',
        location: 'old location',
      );

      // Omitting them leaves them alone...
      expect(adapter.copyWithData(title: 'X').description, 'old description');

      // ...and passing null clears them instead of silently keeping the old
      // text, which is what made "delete the description" impossible.
      final cleared = adapter.copyWithData(description: null, location: null);
      expect(cleared.description, isNull);
      expect(cleared.location, isNull);
      expect(cleared.toUpdateCompanion().description.value, isNull);
      expect(cleared.toUpdateCompanion().location.value, isNull);
    });

    test('copyWithData can clear rrule and color', () {
      final adapter = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
        color: const Color(0xFF123456),
        rrule: 'RRULE:FREQ=DAILY;COUNT=5',
      );

      // Omitting them leaves them alone...
      final untouched = adapter.copyWithData(title: 'X');
      expect(untouched.color, const Color(0xFF123456));
      expect(untouched.rrule, 'RRULE:FREQ=DAILY;COUNT=5');

      // Passing null clears them instead of keeping the old value.
      final cleared = adapter.copyWithData(color: null, rrule: null);
      expect(cleared.color, isNull);
      expect(cleared.rrule, isNull);
      expect(cleared.toUpdateCompanion().rrule.value, isNull);
    });

    test('equality covers the series anchor and occurrence marker', () {
      CalendaEventAdapter build({
        DateTime? seriesStart,
        DateTime? occurrence,
      }) => CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Event',
        start: DateTime(2026, 1, 3, 9),
        end: DateTime(2026, 1, 3, 10),
        seriesStart: seriesStart,
        occurrenceStart: occurrence,
      );

      final plain = build();
      expect(plain, equals(build()));
      expect(plain.hashCode, equals(build().hashCode));
      expect(
        plain,
        isNot(equals(build(seriesStart: DateTime(2026, 1, 1, 9)))),
        reason: 'a different anchor is a different adapter',
      );
      expect(
        plain,
        isNot(equals(build(occurrence: DateTime(2026, 1, 3, 9)))),
        reason: 'occurrence and series row must not compare equal',
      );
    });

    test('equality works for same-id events', () {
      final a = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );
      final b = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
