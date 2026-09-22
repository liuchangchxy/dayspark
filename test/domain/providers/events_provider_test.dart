import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  late ProviderContainer container;
  late AppDatabase testDb;
  late _MockNotificationService notifMock;

  setUp(() {
    notifMock = _MockNotificationService();
    when(() => notifMock.cancel(any())).thenAnswer((_) async {});
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(testDb),
        notificationServiceProvider.overrideWithValue(notifMock),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await testDb.close();
  });

  group('eventsProvider', () {
    test('eventsInDateRangeProvider returns events in range', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'April Event',
              startDt: DateTime(2026, 4, 15, 10),
              endDt: DateTime(2026, 4, 15, 11),
            ),
          );
      await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'May Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 1, 1),
            ),
          );

      final events = await container.read(
        eventsInDateRangeProvider(
          '${DateTime(2026, 4, 1).millisecondsSinceEpoch}-${DateTime(2026, 4, 30).millisecondsSinceEpoch}',
        ).future,
      );

      expect(events.length, 1);
      expect(events.first.summary, 'April Event');
    });

    test('createEvent inserts event', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final id = await container
          .read(createEventProvider)
          .call(
            calendarId: calId,
            summary: 'New Event',
            startDt: DateTime(2026, 6, 1),
            endDt: DateTime(2026, 6, 1, 1),
            isAllDay: false,
          );

      expect(id, greaterThan(0));

      final event = await (testDb.select(
        testDb.events,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(event.summary, 'New Event');
    });

    test('deleteEventProvider cancels reminder notifications on soft delete',
        () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final eventId = await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'To trash',
              startDt: DateTime(2026, 6, 1),
              endDt: DateTime(2026, 6, 1, 1),
            ),
          );
      final reminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      await container.read(deleteEventProvider).call(eventId);

      verify(() => notifMock.cancel(reminderId)).called(1);
      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders, isEmpty);
      final event = await (testDb.select(
        testDb.events,
      )..where((t) => t.id.equals(eventId))).getSingle();
      expect(event.deletedAt, isNotNull);
    });

    test('hardDeleteEventWithChildrenProvider cancels notifications',
        () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final eventId = await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Permanent',
              startDt: DateTime(2026, 6, 1),
              endDt: DateTime(2026, 6, 1, 1),
            ),
          );
      final reminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      await container.read(hardDeleteEventWithChildrenProvider).call(eventId);

      verify(() => notifMock.cancel(reminderId)).called(1);
      final events = await testDb.select(testDb.events).get();
      expect(events, isEmpty);
    });

    test('emptyEventTrashProvider cancels notifications of trashed events',
        () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      Future<int> addTrashedEvent(String summary) => testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: summary,
              startDt: DateTime(2026, 6, 1),
              endDt: DateTime(2026, 6, 1, 1),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final trashedId = await addTrashedEvent('Trashed');
      final activeId = await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Active',
              startDt: DateTime(2026, 6, 2),
              endDt: DateTime(2026, 6, 2, 1),
            ),
          );
      final trashedReminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: trashedId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );
      final activeReminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: activeId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      await container.read(emptyEventTrashProvider).call();

      verify(() => notifMock.cancel(trashedReminderId)).called(1);
      verifyNever(() => notifMock.cancel(activeReminderId));
      final events = await testDb.select(testDb.events).get();
      expect(events.map((e) => e.id), [activeId]);
    });
  });
}
