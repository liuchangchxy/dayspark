import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  late ProviderContainer container;
  late AppDatabase testDb;
  late _MockNotificationService notifMock;
  late int cancelCalls;
  late int scheduleCalls;

  void stubNotificationService() {
    when(() => notifMock.cancel(any())).thenAnswer((_) async {
      cancelCalls++;
    });
    when(
      () => notifMock.scheduleFromReminder(
        any(),
        eventReminderTitle: any(named: 'eventReminderTitle'),
        todoReminderTitle: any(named: 'todoReminderTitle'),
        eventReminderBody: any(named: 'eventReminderBody'),
        todoReminderBody: any(named: 'todoReminderBody'),
      ),
    ).thenAnswer((_) async {
      scheduleCalls++;
    });
  }

  Future<void> waitUntil(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await pumpEventQueue(times: 5);
    }
  }

  // 等到消费端真把这次变更交给 OS（条件等待），再多让几轮以捕捉"多余的一次"
  // ——通道① 与重排器并存时这里会数到 2。
  Future<void> waitForNotifCalls({int cancels = 0, int schedules = 0}) async {
    for (var i = 0;
        i < 200 && (cancelCalls < cancels || scheduleCalls < schedules);
        i++) {
      await pumpEventQueue(times: 5);
    }
    await pumpEventQueue(times: 50);
  }

  // 先播一个"哨兵"事件 + 未来提醒，等到它被排就说明本会话的冷启动全量重算
  // 已落地；随后删掉哨兵行、清空 mock 历史，让 fixture 的事件批成为唯一被测批。
  Future<void> wireReconciler() async {
    final calId = await testDb
        .into(testDb.calendars)
        .insert(CalendarsCompanion.insert(name: 'Decoy'));
    final decoyId = await testDb
        .into(testDb.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calId,
            summary: 'Decoy',
            startDt: DateTime(2027, 1, 4, 10),
            endDt: DateTime(2027, 1, 4, 11),
          ),
        );
    await testDb
        .into(testDb.reminders)
        .insert(
          RemindersCompanion.insert(
            parentType: 'event',
            parentId: decoyId,
            triggerTime: DateTime(2027, 1, 4, 9),
          ),
        );
    container.read(reminderReconcilerProvider);
    await waitUntil(() => scheduleCalls > 0);
    await (testDb.delete(testDb.reminders)..where((t) => t.parentId.equals(decoyId))).go();
    await (testDb.delete(testDb.events)..where((t) => t.id.equals(decoyId))).go();
    reset(notifMock);
    cancelCalls = 0;
    scheduleCalls = 0;
    stubNotificationService();
  }

  setUpAll(() {
    registerFallbackValue(
      Reminder(
        id: 0,
        parentType: 'todo',
        parentId: 0,
        triggerTime: DateTime(2020),
        isTriggered: false,
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    notifMock = _MockNotificationService();
    cancelCalls = 0;
    scheduleCalls = 0;
    stubNotificationService();
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
      await wireReconciler();
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

      await waitForNotifCalls(cancels: 1);
      verify(() => notifMock.cancel(reminderId)).called(1);
      final reminders = await testDb.select(testDb.reminders).get();
      expect(
        reminders.map((r) => r.id),
        [reminderId],
        reason: '软删保留提醒行（与待办侧对称），恢复才能重挂',
      );
      final event = await (testDb.select(
        testDb.events,
      )..where((t) => t.id.equals(eventId))).getSingle();
      expect(event.deletedAt, isNotNull);
    });

    test('hardDeleteEventWithChildrenProvider cancels notifications',
        () async {
      await wireReconciler();
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

      await waitForNotifCalls(cancels: 1);
      verify(() => notifMock.cancel(reminderId)).called(1);
      final events = await testDb.select(testDb.events).get();
      expect(events, isEmpty);
    });

    test('emptyEventTrashProvider cancels notifications of trashed events',
        () async {
      await wireReconciler();
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

      await waitForNotifCalls(cancels: 1);
      verify(() => notifMock.cancel(trashedReminderId)).called(1);
      verifyNever(() => notifMock.cancel(activeReminderId));
      final events = await testDb.select(testDb.events).get();
      expect(events.map((e) => e.id), [activeId]);
    });
  });
}
