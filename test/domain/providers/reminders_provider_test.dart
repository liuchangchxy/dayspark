import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase testDb;
  late ProviderContainer container;
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

  // 先播一个"哨兵"待办 + 未来提醒，等到它被排就说明本会话的冷启动全量重算
  // 已落地；随后删掉哨兵行、清空 mock 历史，让 fixture 的事件批成为唯一被测批。
  Future<void> wireReconciler() async {
    final calId = await testDb
        .into(testDb.calendars)
        .insert(CalendarsCompanion.insert(name: 'Decoy'));
    final decoyId = await testDb
        .into(testDb.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Decoy',
            dueDate: Value(DateTime(2027, 1, 4, 9)),
          ),
        );
    await testDb
        .into(testDb.reminders)
        .insert(
          RemindersCompanion.insert(
            parentType: 'todo',
            parentId: decoyId,
            triggerTime: DateTime(2027, 1, 4, 8),
          ),
        );
    container.read(reminderReconcilerProvider);
    await waitUntil(() => scheduleCalls > 0);
    await (testDb.delete(testDb.reminders)..where((t) => t.parentId.equals(decoyId))).go();
    await (testDb.delete(testDb.todos)..where((t) => t.id.equals(decoyId))).go();
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

  group('Reminders', () {
    test('insert and read reminder', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final eventId = await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 2),
            ),
          );

      final triggerTime = DateTime(2026, 4, 30, 23, 55);
      await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: triggerTime,
            ),
          );

      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders.length, 1);
      expect(reminders.first.parentType, 'event');
      expect(reminders.first.parentId, eventId);
      expect(reminders.first.isTriggered, false);
    });

    test('query reminders by parent', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final eventId = await testDb
          .into(testDb.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calId,
              summary: 'Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 2),
            ),
          );
      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Task',
            ),
          );

      await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime(2026, 4, 30, 23, 55),
            ),
          );
      await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: eventId,
              triggerTime: DateTime(2026, 4, 30, 23, 45),
            ),
          );
      await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: DateTime(2026, 4, 29),
            ),
          );

      final eventReminders =
          await (testDb.select(testDb.reminders)..where(
                (t) =>
                    t.parentType.equals('event') & t.parentId.equals(eventId),
              ))
              .get();
      expect(eventReminders.length, 2);

      final todoReminders =
          await (testDb.select(testDb.reminders)..where(
                (t) => t.parentType.equals('todo') & t.parentId.equals(todoId),
              ))
              .get();
      expect(todoReminders.length, 1);
    });

    test('delete reminder', () async {
      final id = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'event',
              parentId: 1,
              triggerTime: DateTime(2026, 5, 1),
            ),
          );

      await (testDb.delete(
        testDb.reminders,
      )..where((t) => t.id.equals(id))).go();
      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders.length, 0);
    });
  });

  group('loadNotificationStrings', () {
    test('returns zh strings for zh locale', () async {
      final strings = await loadNotificationStrings(
        locale: const Locale('zh'),
      );
      expect(strings.eventReminderTitle, '日程提醒');
      expect(strings.todoReminderTitle, '待办提醒');
      expect(strings.eventReminderBody, '日程即将开始');
      expect(strings.todoReminderBody, '待办即将到期');
    });

    test('returns en strings for en locale', () async {
      final strings = await loadNotificationStrings(
        locale: const Locale('en'),
      );
      expect(strings.eventReminderTitle, 'Event Reminder');
      expect(strings.todoReminderTitle, 'Todo Reminder');
      expect(strings.eventReminderBody, 'Event starting soon');
      expect(strings.todoReminderBody, 'Task due soon');
    });

    test('reads persisted locale from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({appLocalePrefKey: 'zh'});
      final strings = await loadNotificationStrings();
      expect(strings.eventReminderTitle, '日程提醒');
    });
  });

  group('clearRemindersProvider', () {
    test('cancels and deletes only the target parent reminders', () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      Future<int> addTodo(String summary) => testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: summary,
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      Future<int> addReminder(int todoId) => testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: DateTime.now().add(const Duration(hours: 2)),
            ),
          );
      final todoA = await addTodo('Target');
      final todoB = await addTodo('Other');
      final reminderA1 = await addReminder(todoA);
      final reminderA2 = await addReminder(todoA);
      final reminderB = await addReminder(todoB);

      await container.read(clearRemindersProvider).call('todo', todoA);

      await waitForNotifCalls(cancels: 2);

      verify(() => notifMock.cancel(reminderA1)).called(1);
      verify(() => notifMock.cancel(reminderA2)).called(1);
      verifyNever(() => notifMock.cancel(reminderB));
      final remaining = await testDb.select(testDb.reminders).get();
      expect(remaining.map((r) => r.id), [reminderB]);
    });
  });
}
