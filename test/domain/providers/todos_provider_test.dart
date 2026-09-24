import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late AppDatabase testDb;
  late _MockNotificationService notifMock;

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

  group('todosProvider', () {
    test('allTodosProvider returns non-deleted todos', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Pending task',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Done task',
              priority: const Value(5),
              status: const Value('COMPLETED'),
            ),
          );

      final todos = await container.read(allTodosProvider.future);
      expect(todos.length, 2);
    });

    test('createTodoProvider inserts a new todo', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final id = await container
          .read(createTodoProvider)
          .call(
            calendarId: calId,
            summary: 'New Todo',
            priority: 3,
            status: 'NEEDS-ACTION',
          );

      expect(id, greaterThan(0));

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(todo.summary, 'New Todo');
    });

    test('completeTodoProvider marks a todo as completed', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'To complete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container
          .read(toggleTodoProvider)
          .call(id: todoId, isCompleted: true);

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.status, 'COMPLETED');
    });

    test('deleteTodoProvider soft-deletes a todo', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'To delete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container.read(deleteTodoProvider).call(todoId);

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.deletedAt != null, true);
    });

    test('deleteTodoProvider cascades soft-delete to children', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));

      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
            ),
          );
      final otherId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Unrelated',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );

      await container.read(deleteTodoProvider).call(parentId);

      final rows = await testDb.select(testDb.todos).get();
      final parent = rows.firstWhere((t) => t.id == parentId);
      final child = rows.firstWhere((t) => t.id == childId);
      final other = rows.firstWhere((t) => t.id == otherId);
      expect(parent.deletedAt != null, true);
      expect(child.deletedAt != null, true);
      expect(child.deletedAt, parent.deletedAt);
      expect(other.deletedAt == null, true);

      final trashed = await testDb.todosDao.watchDeleted().first;
      expect(trashed.map((t) => t.id), containsAll([parentId, childId]));
    });

    test('restoreTodoProvider clears deletedAt', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );

      await container.read(restoreTodoProvider).call(todoId);

      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.deletedAt == null, true);
    });

    test('restoreTodoProvider cascades restore to children', () async {
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
            ),
          );
      final otherId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Unrelated trashed',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );

      await container.read(deleteTodoProvider).call(parentId);
      var trashed = await testDb.todosDao.watchDeleted().first;
      expect(trashed.map((t) => t.id), containsAll([parentId, childId]));

      await container.read(restoreTodoProvider).call(parentId);

      final rows = await testDb.select(testDb.todos).get();
      final parent = rows.firstWhere((t) => t.id == parentId);
      final child = rows.firstWhere((t) => t.id == childId);
      final other = rows.firstWhere((t) => t.id == otherId);
      expect(parent.deletedAt == null, true);
      expect(child.deletedAt == null, true);
      expect(other.deletedAt != null, true);

      trashed = await testDb.todosDao.watchDeleted().first;
      expect(trashed.map((t) => t.id), isNot(contains(parentId)));
      expect(trashed.map((t) => t.id), isNot(contains(childId)));
      expect(trashed.map((t) => t.id), contains(otherId));

      final activeRoots = await testDb.todosDao.watchAllNotDeleted().first;
      expect(activeRoots.map((t) => t.id), contains(parentId));
      final visibleChildren =
          await testDb.todosDao.watchSubtasks(parentId).first;
      expect(visibleChildren.map((t) => t.id), contains(childId));
    });

    test('restoreTodoProvider restores a trashed parent of the restored child',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      // Hierarchy 1: root parent + child, both trashed (after cascade delete).
      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed root parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              dueDate: Value(DateTime.now().add(const Duration(days: 1))),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
              dueDate: Value(DateTime.now().add(const Duration(days: 1))),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final otherId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Unrelated trashed',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final parentReminder = RemindersCompanion(
        parentType: const Value('todo'),
        parentId: Value(parentId),
        triggerTime: Value(DateTime.now().add(const Duration(hours: 4))),
      );
      final parentReminderId = await testDb
          .into(testDb.reminders)
          .insert(parentReminder);
      final parentReminderRow = await (testDb.select(testDb.reminders)
            ..where((r) => r.id.equals(parentReminderId)))
          .getSingle();

      await container.read(restoreTodoProvider).call(childId);

      await waitForNotifCalls(schedules: 1);

      final rows = await testDb.select(testDb.todos).get();
      final parent = rows.firstWhere((t) => t.id == parentId);
      final child = rows.firstWhere((t) => t.id == childId);
      final other = rows.firstWhere((t) => t.id == otherId);
      expect(parent.deletedAt == null, true);
      expect(child.deletedAt == null, true);
      expect(other.deletedAt != null, true);
      final activeRoots = await testDb.todosDao.watchAllNotDeleted().first;
      expect(activeRoots.map((t) => t.id), containsAll([parentId]));
      final visibleChildren =
          await testDb.todosDao.watchSubtasks(parentId).first;
      expect(visibleChildren.map((t) => t.id), contains(childId));
      verify(
        () => notifMock.scheduleFromReminder(
          parentReminderRow,
          eventReminderTitle: any(named: 'eventReminderTitle'),
          todoReminderTitle: any(named: 'todoReminderTitle'),
          eventReminderBody: any(named: 'eventReminderBody'),
          todoReminderBody: any(named: 'todoReminderBody'),
        ),
      ).called(1);

      // Hierarchy 2: restore stops at one level — grandparent stays trashed.
      final grandparentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed grandparent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final middleId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed middle parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(grandparentId),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final leafId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed leaf',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(middleId),
              deletedAt: Value(DateTime.now()),
            ),
          );

      await container.read(restoreTodoProvider).call(leafId);

      final rows2 = await testDb.select(testDb.todos).get();
      final grandparent = rows2.firstWhere((t) => t.id == grandparentId);
      final middle = rows2.firstWhere((t) => t.id == middleId);
      final leaf = rows2.firstWhere((t) => t.id == leafId);
      expect(middle.deletedAt == null, true);
      expect(leaf.deletedAt == null, true);
      expect(grandparent.deletedAt != null, true);
    });

    test('deleteTodoProvider cancels notifications for parent and children',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
            ),
          );
      final otherId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Unrelated',
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
      final parentReminderId = await addReminder(parentId);
      final childReminderId = await addReminder(childId);
      final otherReminderId = await addReminder(otherId);

      await container.read(deleteTodoProvider).call(parentId);

      await waitForNotifCalls(cancels: 2);

      verify(() => notifMock.cancel(parentReminderId)).called(1);
      verify(() => notifMock.cancel(childReminderId)).called(1);
      verifyNever(() => notifMock.cancel(otherReminderId));
    });

    test('toggleTodoProvider complete cancels reminder notifications',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'To complete',
              priority: const Value(5),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final reminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      await container
          .read(toggleTodoProvider)
          .call(id: todoId, isCompleted: true);

      await waitForNotifCalls(cancels: 1);

      verify(() => notifMock.cancel(reminderId)).called(1);
      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.status, 'COMPLETED');
    });

    test('toggleTodoProvider incomplete reschedules reminder notifications',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'To reopen',
              priority: const Value(5),
              status: const Value('COMPLETED'),
              dueDate: Value(DateTime.now().add(const Duration(days: 1))),
            ),
          );
      final triggerTime = DateTime.now().add(const Duration(hours: 3));
      final reminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: triggerTime,
            ),
          );
      final reminder = await (testDb.select(
        testDb.reminders,
      )..where((t) => t.id.equals(reminderId))).getSingle();

      await container
          .read(toggleTodoProvider)
          .call(id: todoId, isCompleted: false);

      await waitForNotifCalls(schedules: 1);

      verify(
        () => notifMock.scheduleFromReminder(
          reminder,
          eventReminderTitle: any(named: 'eventReminderTitle'),
          todoReminderTitle: any(named: 'todoReminderTitle'),
          eventReminderBody: any(named: 'eventReminderBody'),
          todoReminderBody: any(named: 'todoReminderBody'),
        ),
      ).called(1);
      verifyNever(() => notifMock.cancel(reminderId));
      final todo = await (testDb.select(
        testDb.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(todo.status, 'NEEDS-ACTION');
    });

    test('restoreTodoProvider reschedules reminders of restored todos',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              dueDate: Value(DateTime.now().add(const Duration(days: 1))),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Trashed child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
              dueDate: Value(DateTime.now().add(const Duration(days: 1))),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final triggerTime = DateTime.now().add(const Duration(hours: 5));
      Future<int> addReminder(int todoId) => testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: triggerTime,
            ),
          );
      final parentReminderId = await addReminder(parentId);
      final childReminderId = await addReminder(childId);
      final parentReminder = await (testDb.select(
        testDb.reminders,
      )..where((t) => t.id.equals(parentReminderId))).getSingle();
      final childReminder = await (testDb.select(
        testDb.reminders,
      )..where((t) => t.id.equals(childReminderId))).getSingle();

      await container.read(restoreTodoProvider).call(parentId);

      await waitForNotifCalls(schedules: 2);

      verify(
        () => notifMock.scheduleFromReminder(
          parentReminder,
          eventReminderTitle: any(named: 'eventReminderTitle'),
          todoReminderTitle: any(named: 'todoReminderTitle'),
          eventReminderBody: any(named: 'eventReminderBody'),
          todoReminderBody: any(named: 'todoReminderBody'),
        ),
      ).called(1);
      verify(
        () => notifMock.scheduleFromReminder(
          childReminder,
          eventReminderTitle: any(named: 'eventReminderTitle'),
          todoReminderTitle: any(named: 'todoReminderTitle'),
          eventReminderBody: any(named: 'eventReminderBody'),
          todoReminderBody: any(named: 'todoReminderBody'),
        ),
      ).called(1);
    });

    test('permanentDeleteTodoProvider cancels reminder notifications',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final todoId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Forever gone',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final reminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      await container.read(permanentDeleteTodoProvider).call(todoId);

      await waitForNotifCalls(cancels: 1);

      verify(() => notifMock.cancel(reminderId)).called(1);
      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders, isEmpty);
    });

    test(
        'permanentDeleteTodoProvider cascades to direct children and their rows',
        () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final tagId = await testDb
          .into(testDb.tags)
          .insert(TagsCompanion.insert(name: 'Tag'));
      final parentId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Doomed parent',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final childId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Doomed child',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              parentId: Value(parentId),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final otherId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Survivor',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      await testDb
          .into(testDb.todoTags)
          .insert(TodoTagsCompanion.insert(todoId: childId, tagId: tagId));
      await testDb.into(testDb.attachments).insert(
            AttachmentsCompanion.insert(
              parentType: 'todo',
              parentId: childId,
              filePath: '/tmp/child.txt',
              fileName: 'child.txt',
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
      final parentReminderId = await addReminder(parentId);
      final childReminderId = await addReminder(childId);
      final otherReminderId = await addReminder(otherId);

      await container.read(permanentDeleteTodoProvider).call(parentId);

      await waitForNotifCalls(cancels: 2);

      final todos = await testDb.select(testDb.todos).get();
      expect(todos.map((t) => t.id), [otherId]);
      final todoTags = await testDb.select(testDb.todoTags).get();
      expect(todoTags, isEmpty);
      final attachments = await testDb.select(testDb.attachments).get();
      expect(attachments, isEmpty);
      final reminders = await testDb.select(testDb.reminders).get();
      expect(reminders.map((r) => r.id), [otherReminderId]);
      verify(() => notifMock.cancel(parentReminderId)).called(1);
      verify(() => notifMock.cancel(childReminderId)).called(1);
      verifyNever(() => notifMock.cancel(otherReminderId));
    });

    test('emptyTrashProvider cancels reminders of trashed todos', () async {
      await wireReconciler();
      final calId = await testDb
          .into(testDb.calendars)
          .insert(CalendarsCompanion.insert(name: 'Test'));
      final trashedId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'In trash',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
              deletedAt: Value(DateTime.now()),
            ),
          );
      final activeId = await testDb
          .into(testDb.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'Active',
              priority: const Value(1),
              status: const Value('NEEDS-ACTION'),
            ),
          );
      final trashedReminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: trashedId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );
      final activeReminderId = await testDb
          .into(testDb.reminders)
          .insert(
            RemindersCompanion.insert(
              parentType: 'todo',
              parentId: activeId,
              triggerTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      await container.read(emptyTrashProvider).call();

      await waitForNotifCalls(cancels: 1);

      verify(() => notifMock.cancel(trashedReminderId)).called(1);
      verifyNever(() => notifMock.cancel(activeReminderId));
      final todos = await testDb.select(testDb.todos).get();
      expect(todos.map((t) => t.id), [activeId]);
    });
  });
}
