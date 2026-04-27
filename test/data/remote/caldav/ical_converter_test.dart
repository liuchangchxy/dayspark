import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/data/remote/caldav/ical_converter.dart';

void main() {
  late AppDatabase testDb;
  late IcalConverter converter;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    converter = IcalConverter();
  });

  tearDown(() async {
    await testDb.close();
  });

  group('eventToIcal', () {
    test('converts a simple event to iCalendar string', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'test-uid-1',
              summary: 'Team Meeting',
              startDt: DateTime(2026, 5, 1, 10, 0),
              endDt: DateTime(2026, 5, 1, 11, 0),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final ical = converter.eventToIcal(events.first);

      expect(ical, contains('BEGIN:VCALENDAR'));
      expect(ical, contains('BEGIN:VEVENT'));
      expect(ical, contains('SUMMARY:Team Meeting'));
      expect(ical, contains('UID:test-uid-1'));
      expect(ical, contains('END:VEVENT'));
      expect(ical, contains('END:VCALENDAR'));
    });

    test('includes optional fields when present', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'test-uid-2',
              summary: 'Conference',
              startDt: DateTime(2026, 6, 15, 9, 0),
              endDt: DateTime(2026, 6, 15, 17, 0),
              description: const Value('Annual conference'),
              location: const Value('Convention Center'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final ical = converter.eventToIcal(events.first);

      expect(ical, contains('DESCRIPTION:Annual conference'));
      expect(ical, contains('LOCATION:Convention Center'));
    });
  });

  group('todoToIcal', () {
    test('converts a simple todo to iCalendar string', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 'todo-uid-1',
              summary: 'Buy groceries',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      final todos = await testDb.select(testDb.todos).get();
      final ical = converter.todoToIcal(todos.first);

      expect(ical, contains('BEGIN:VCALENDAR'));
      expect(ical, contains('BEGIN:VTODO'));
      expect(ical, contains('SUMMARY:Buy groceries'));
      expect(ical, contains('UID:todo-uid-1'));
      expect(ical, contains('END:VTODO'));
    });

    test('includes due date and completed status', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 'todo-uid-2',
              summary: 'Submit report',
              priority: const Value(1),
              status: const Value('IN-PROCESS'),
              dueDate: Value(DateTime(2026, 5, 15)),
            ),
          );

      final todos = await testDb.select(testDb.todos).get();
      final ical = converter.todoToIcal(todos.first);

      expect(ical, contains('DUE:'));
    });
  });

  group('icalToEventCompanion', () {
    test('parses a VEVENT string into EventsCompanion', () {
      const icalData =
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'PRODID:-//Test//EN\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:parsed-uid-1\r\n'
          'DTSTAMP:20260501T000000Z\r\n'
          'DTSTART:20260501T100000Z\r\n'
          'DTEND:20260501T110000Z\r\n'
          'SUMMARY:Parsed Event\r\n'
          'DESCRIPTION:Test description\r\n'
          'LOCATION:Office\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR';

      final companion = converter.icalToEventCompanion(
        icalData,
        1,
        '/cal/parsed-uid-1.ics',
        'etag-123',
      );

      expect(companion.uid.value, 'parsed-uid-1');
      expect(companion.summary.value, 'Parsed Event');
      expect(companion.calendarId.value, 1);
      expect(companion.etag.value, 'etag-123');
      expect(companion.description.value, 'Test description');
      expect(companion.location.value, 'Office');
    });

    test('throws when no VEVENT found', () {
      const icalData =
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:x\r\n'
          'DTSTAMP:20260501T000000Z\r\n'
          'SUMMARY:Task\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR';

      expect(
        () => converter.icalToEventCompanion(icalData, 1, null, null),
        throwsFormatException,
      );
    });
  });

  group('icalToTodoCompanion', () {
    test('parses a VTODO string into TodosCompanion', () {
      const icalData =
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'PRODID:-//Test//EN\r\n'
          'BEGIN:VTODO\r\n'
          'UID:todo-parsed-1\r\n'
          'DTSTAMP:20260501T000000Z\r\n'
          'SUMMARY:Parsed Todo\r\n'
          'PRIORITY:5\r\n'
          'STATUS:IN-PROCESS\r\n'
          'DUE:20260515T000000Z\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR';

      final companion = converter.icalToTodoCompanion(
        icalData,
        1,
        '/cal/todo-parsed-1.ics',
        'etag-456',
      );

      expect(companion.uid.value, 'todo-parsed-1');
      expect(companion.summary.value, 'Parsed Todo');
      expect(companion.priority.value, 5);
      expect(companion.status.value, 'IN-PROCESS');
      expect(companion.etag.value, 'etag-456');
    });
  });

  group('detectComponentType', () {
    test('detects VEVENT', () {
      const icalData =
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:x\r\n'
          'DTSTAMP:20260501T000000Z\r\n'
          'SUMMARY:Event\r\n'
          'DTSTART:20260501T100000Z\r\n'
          'DTEND:20260501T110000Z\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR';

      expect(converter.detectComponentType(icalData), 'VEVENT');
    });

    test('detects VTODO', () {
      const icalData =
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'BEGIN:VTODO\r\n'
          'UID:x\r\n'
          'DTSTAMP:20260501T000000Z\r\n'
          'SUMMARY:Task\r\n'
          'END:VTODO\r\n'
          'END:VCALENDAR';

      expect(converter.detectComponentType(icalData), 'VTODO');
    });

    test('returns null for non-calendar data', () {
      expect(converter.detectComponentType('not ical data'), isNull);
    });
  });

  group('roundtrip', () {
    test('event → ical → event preserves core data', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'roundtrip-1',
              summary: 'Roundtrip Event',
              startDt: DateTime(2026, 7, 1, 14, 0),
              endDt: DateTime(2026, 7, 1, 15, 30),
              description: const Value('Test roundtrip'),
            ),
          );

      final events = await testDb.select(testDb.events).get();
      final ical = converter.eventToIcal(events.first);
      final companion = converter.icalToEventCompanion(ical, calId, null, null);

      expect(companion.uid.value, 'roundtrip-1');
      expect(companion.summary.value, 'Roundtrip Event');
      expect(companion.description.value, 'Test roundtrip');
    });

    test('todo → ical → todo preserves core data', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(caldavHref: '/cal/', name: 'Test'),
          );
      await testDb.into(testDb.todos).insert(
            TodosCompanion.insert(
              calendarId: calId,
              uid: 'roundtrip-todo-1',
              summary: 'Roundtrip Todo',
              priority: const Value(3),
              status: const Value('NEEDS-ACTION'),
              dueDate: Value(DateTime(2026, 8, 1)),
            ),
          );

      final todos = await testDb.select(testDb.todos).get();
      final ical = converter.todoToIcal(todos.first);
      final companion = converter.icalToTodoCompanion(ical, calId, null, null);

      expect(companion.uid.value, 'roundtrip-todo-1');
      expect(companion.summary.value, 'Roundtrip Todo');
      expect(companion.priority.value, 3);
    });
  });
}
