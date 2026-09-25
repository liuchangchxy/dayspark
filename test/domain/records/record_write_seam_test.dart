import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/account_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/domain/services/ics_service.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/infrastructure/platform/home_widget_service.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import '../sync/sync_test_support.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi(this.session);

  final AuthSession session;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async => session;

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
  }) async => session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('home_widget');
  late Map<String, Object?> store;
  late AppDatabase db;
  late ProviderContainer container;
  late _MockNotificationService notif;
  late List<Reminder> schedules;
  late List<int> cancels;
  late List<List<RecordChange>> batches;
  late int calId;

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({appLocalePrefKey: 'en'});
    store = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = (call.arguments as Map).cast<String, dynamic>();
          switch (call.method) {
            case 'getWidgetData':
              return store[args['id'] as String];
            case 'saveWidgetData':
              store[args['id'] as String] = args['data'];
              return true;
            case 'updateWidget':
            case 'setAppGroupId':
              return true;
            default:
              return null;
          }
        });
    notif = _MockNotificationService();
    schedules = <Reminder>[];
    cancels = <int>[];
    batches = <List<RecordChange>>[];
    when(() => notif.cancel(captureAny())).thenAnswer((inv) async {
      cancels.add(inv.positionalArguments.first as int);
    });
    when(
      () => notif.scheduleFromReminder(
        captureAny(),
        eventReminderTitle: any(named: 'eventReminderTitle'),
        todoReminderTitle: any(named: 'todoReminderTitle'),
        eventReminderBody: any(named: 'eventReminderBody'),
        todoReminderBody: any(named: 'todoReminderBody'),
      ),
    ).thenAnswer((inv) async {
      schedules.add(inv.positionalArguments.first as Reminder);
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
      ],
    );
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
    await db.close();
  });

  Future<void> waitUntil(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await pumpEventQueue(times: 5);
    }
    await pumpEventQueue(times: 50);
  }

  List<RecordChange> flatBatches() => batches.expand((b) => b).toList();

  Future<int> insertTodo({
    DateTime? dueDate,
    String status = 'NEEDS-ACTION',
    DateTime? deletedAt,
  }) {
    return db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Seam todo',
            dueDate: Value(dueDate),
            status: Value(status),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<int> insertEvent({required DateTime start, DateTime? deletedAt}) {
    return db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calId,
            summary: 'Seam event',
            startDt: start,
            endDt: start.add(const Duration(hours: 1)),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<int> insertReminder(
    String parentType,
    int parentId,
    DateTime triggerTime,
  ) {
    return db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            parentType: parentType,
            parentId: parentId,
            triggerTime: triggerTime,
          ),
        );
  }

  Future<DateTime?> reminderTriggerTime(int id) async {
    final row = await (db.select(
      db.reminders,
    )..where((t) => t.id.equals(id))).getSingle();
    return row.triggerTime;
  }

  // 冷启动全量重算在装配时就跑：先放一个"哨兵"父 + 未来提醒，等到它被排
  // 就说明本会话的首次重算已落地（条件等待，不用固定轮数）。哨兵同时是
  // "消费端确实活着"的正向对照，避免 0 调用断言变成空转。
  Future<void> wireSeamConsumers({bool widget = false}) async {
    container.read(recordBusProvider).changes.listen(batches.add);
    if (widget) container.read(homeWidgetAutoRefreshProvider);
    final sentinelTodo = await insertTodo(
      dueDate: DateTime(2027, 1, 4, 9),
    );
    await insertReminder('todo', sentinelTodo, DateTime(2027, 1, 4, 8));
    container.read(reminderReconcilerProvider);
    await waitUntil(() => schedules.isNotEmpty);
    schedules.clear();
    cancels.clear();
    batches.clear();
  }

  // 等到"这次逻辑变更的期望平台调用条数"出现（条件等待，非固定轮数），再额外
  // 让若干轮——专门用来捕捉"多余的那一次"（通道① 与重排器并存时会各来一次）。
  Future<void> settleBatch({int cancelCount = 0, int scheduleCount = 0}) async {
    for (var i = 0;
        i < 200 &&
            (cancels.length < cancelCount || schedules.length < scheduleCount);
        i++) {
      await pumpEventQueue(times: 5);
    }
    await pumpEventQueue(times: 50);
  }

  group('单一动作（一次逻辑变更 = 恰好一次平台调用）', () {
    test('S1 改期（事件 start 变）→ 恰好 1 次调度（位移后时刻）、0 次取消', () async {
      await wireSeamConsumers();
      final oldStart = DateTime(2027, 6, 1, 9);
      final eventId = await insertEvent(start: oldStart);
      final reminderId = await insertReminder(
        'event',
        eventId,
        DateTime(2027, 6, 1, 8, 55),
      );

      await container.read(updateEventProvider)(
        eventId,
        EventsCompanion(
          startDt: Value(DateTime(2027, 6, 1, 11)),
          endDt: Value(DateTime(2027, 6, 1, 12)),
        ),
      );

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(schedules.single.id, reminderId);
      expect(schedules.single.triggerTime, DateTime(2027, 6, 1, 10, 55));
      expect(cancels, isEmpty);
    });

    test('S2 完成待办 → 恰好 1 次取消、0 次调度', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(dueDate: DateTime(2027, 6, 2, 9));
      await insertReminder('todo', todoId, DateTime(2027, 6, 2, 8));

      await container.read(toggleTodoProvider)(
        id: todoId,
        isCompleted: true,
      );

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('S3 软删待办（进回收站）→ 恰好 1 次取消、0 次调度', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(dueDate: DateTime(2027, 6, 3, 9));
      await insertReminder('todo', todoId, DateTime(2027, 6, 3, 8));

      await container.read(deleteTodoProvider)(todoId);

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('S4 硬删待办 → 恰好 1 次取消、0 次调度', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(dueDate: DateTime(2027, 6, 4, 9));
      await insertReminder('todo', todoId, DateTime(2027, 6, 4, 8));

      await container.read(permanentDeleteTodoProvider)(todoId);

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('S5 清空回收站 → 每条提醒恰好 1 次取消', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(
        dueDate: DateTime(2027, 6, 5, 9),
        deletedAt: DateTime(2027, 6, 4),
      );
      await insertReminder('todo', todoId, DateTime(2027, 6, 5, 8));

      await container.read(emptyTrashProvider)();

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('S6 提醒行删除 → 恰好 1 次取消', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(dueDate: DateTime(2027, 6, 6, 9));
      final reminderId = await container.read(createReminderProvider)(
        parentType: 'todo',
        parentId: todoId,
        triggerTime: DateTime(2027, 6, 6, 8),
      );
      await settleBatch(scheduleCount: 1);
      schedules.clear();
      cancels.clear();
      batches.clear();

      await container.read(deleteReminderProvider)(reminderId);

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('S7 提醒行新增 → 恰好 1 次调度（不是内联 + 重排器各一次）', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(dueDate: DateTime(2027, 6, 7, 9));

      await container.read(createReminderProvider)(
        parentType: 'todo',
        parentId: todoId,
        triggerTime: DateTime(2027, 6, 7, 8),
      );

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(cancels, isEmpty);
    });

    test('S8 取消完成（reopen）→ 恰好 1 次调度', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(
        dueDate: DateTime(2027, 6, 8, 9),
        status: 'COMPLETED',
      );
      await insertReminder('todo', todoId, DateTime(2027, 6, 8, 8));

      await container.read(toggleTodoProvider)(
        id: todoId,
        isCompleted: false,
      );

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(cancels, isEmpty);
    });

    test('S9 回收站恢复待办 → 恰好 1 次调度', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(
        dueDate: DateTime(2027, 6, 9, 9),
        deletedAt: DateTime(2027, 6, 8),
      );
      await insertReminder('todo', todoId, DateTime(2027, 6, 9, 8));

      await container.read(restoreTodoProvider)(todoId);

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(cancels, isEmpty);
    });

    test('S10 事件软删（进回收站）→ 恰好 1 次取消', () async {
      await wireSeamConsumers();
      final eventId = await insertEvent(start: DateTime(2027, 6, 10, 9));
      await insertReminder('event', eventId, DateTime(2027, 6, 10, 8, 55));

      await container.read(deleteEventProvider)(eventId);

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    // 事件软删与待办侧对称：父行只置 deletedAt，提醒行**保留**为惰性。行仍在 =
    // 记录仍在回收站里，所以登记 applied、靠父行 inactive 档撤通知，而不是
    // removed（后者语义是"记录已不存在"）。行保留正是"恢复能重挂"的前提。
    test('S14 事件软删（进回收站）→ 提醒行保留 + 按父行 inactive 档撤通知', () async {
      await wireSeamConsumers();
      final start = DateTime(2027, 6, 14, 9);
      final eventId = await insertEvent(start: start);
      final reminderId = await insertReminder(
        'event',
        eventId,
        DateTime(2027, 6, 14, 8, 55),
      );

      await container.read(deleteEventProvider)(eventId);

      await settleBatch(cancelCount: 1);
      expect(cancels, [reminderId]);
      expect(schedules, isEmpty);

      final rows = await db.select(db.reminders).get();
      expect(
        rows.where((r) => r.id == reminderId),
        hasLength(1),
        reason: '软删不删提醒行，否则回收站恢复后无可重挂',
      );

      final change = flatBatches().single;
      expect(
        change,
        isA<RecordApplied>(),
        reason: '记录仍在回收站里 → 登记 applied 靠父行 inactive 判定，不用 removed',
      );
      expect((change as RecordApplied).localId, eventId);
      expect(change.previousReference, start);
    });

    // 本次决策要修的用户可见行为：事件软删保留提醒行后，"进回收站 → 恢复"
    // 必须像待办一样把提醒重新排上（旧实现硬删行 → 恢复后提醒永久沉默）。
    test('S15 事件进回收站后恢复 → 同一 reminder id 按行内绝对时刻重新排上', () async {
      await wireSeamConsumers();
      final start = DateTime(2027, 6, 15, 9);
      final eventId = await insertEvent(start: start);
      final reminderId = await insertReminder(
        'event',
        eventId,
        DateTime(2027, 6, 15, 8, 55),
      );

      await container.read(deleteEventProvider)(eventId);
      await settleBatch(cancelCount: 1);
      expect(cancels, [reminderId], reason: '前置：软删先撤掉已排的通知');
      expect(schedules, isEmpty);
      cancels.clear();
      batches.clear();

      await container.read(restoreEventProvider)(eventId);

      await settleBatch(scheduleCount: 1);
      expect(
        schedules.single.id,
        reminderId,
        reason: '重挂回原 reminder 行（id 空间就是通知 id）',
      );
      expect(
        schedules.single.triggerTime,
        DateTime(2027, 6, 15, 8, 55),
        reason: 'start 未变（Δ=0）→ 绝对时刻 = 行内时刻',
      );
      expect(cancels, isEmpty);
    });

    // 参考时间为空的父行（无 dueDate 的待办）在 SPEC §3.5 规则 4 里属 inactive
    // 档：撤掉通道① 后由重排器统一判定——旧内联通道无条件重排，是与规则 4 相左
    // 的历史行为。reminder 行保留为惰性（不删行）。
    test('S12 取消完成但父行无参考时间 → 恰好 1 次取消（不是重排）', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(status: 'COMPLETED');
      final reminderId = await insertReminder(
        'todo',
        todoId,
        DateTime(2027, 6, 12, 8),
      );

      await container.read(toggleTodoProvider)(id: todoId, isCompleted: false);

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
      final rows = await db.select(db.reminders).get();
      expect(rows.where((r) => r.id == reminderId), hasLength(1));
    });

    // 撤掉通道① 后 `_applied` 才完整：曾交给 OS 的未来时刻现在都记在账本里，
    // 于是"期望时刻位移到过去"这一档能真的撤销幽灵响铃（此前只有内联通道排过
    // 的 id 不在账本里，这一档对它们永远不成立）。
    test('S13 位移到过去 → 撤销曾交给 OS 的未来时刻（幽灵响铃）', () async {
      await wireSeamConsumers();
      final due = DateTime(2027, 6, 1, 9);
      final todoId = await insertTodo(dueDate: due);
      final reminderId = await insertReminder(
        'todo',
        todoId,
        DateTime(2027, 6, 1, 8),
      );

      await container.read(updateTodoProvider)(
        todoId,
        TodosCompanion(dueDate: Value(due)),
      );
      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1), reason: '先把未来时刻交给 OS（入账本）');
      expect(cancels, isEmpty);
      schedules.clear();

      await container.read(updateTodoProvider)(
        todoId,
        TodosCompanion(dueDate: Value(DateTime(2026, 1, 1, 9))),
      );

      await settleBatch(cancelCount: 1);
      expect(cancels, [reminderId], reason: '旧闹钟在新时间点仍是幽灵响铃');
      expect(schedules, isEmpty);
    });

    test('S11 事件硬删 → 恰好 1 次取消', () async {
      await wireSeamConsumers();
      final eventId = await insertEvent(start: DateTime(2027, 6, 11, 9));
      await insertReminder('event', eventId, DateTime(2027, 6, 11, 8, 55));

      await container.read(hardDeleteEventWithChildrenProvider)(eventId);

      await settleBatch(cancelCount: 1);
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });
  });

  group('事件写路径', () {
    test('1 更新事件改 start → 重排提醒到绝对时刻（位移 = 新 start − 旧 start）', () async {
      await wireSeamConsumers();
      final oldStart = DateTime(2027, 3, 10, 9);
      final eventId = await insertEvent(start: oldStart);
      final reminderId = await insertReminder(
        'event',
        eventId,
        DateTime(2027, 3, 10, 8, 55),
      );

      final newStart = DateTime(2027, 3, 10, 11);
      await container.read(updateEventProvider)(
        eventId,
        EventsCompanion(
          startDt: Value(newStart),
          endDt: Value(DateTime(2027, 3, 10, 12)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await settleBatch(scheduleCount: 1);
      expect(
        schedules.single.id,
        reminderId,
        reason: '重排必须落在原 reminder 行（id 空间就是通知 id）',
      );
      expect(schedules.single.triggerTime, DateTime(2027, 3, 10, 10, 55));
      expect(
        await reminderTriggerTime(reminderId),
        DateTime(2027, 3, 10, 10, 55),
        reason: '行内值是下一次位移的锚，必须被物化回写',
      );

      final applied = flatBatches().single as RecordApplied;
      expect(applied.type, RecordType.event);
      expect(applied.localId, eventId);
      expect(applied.previousReference, oldStart);
    });

    test('1b 拖拽改期路径（onEventChanged 的等价调用）→ 同一条重排', () async {
      await wireSeamConsumers();
      final oldStart = DateTime(2027, 3, 10, 14);
      final eventId = await insertEvent(start: oldStart);
      final reminderId = await insertReminder(
        'event',
        eventId,
        DateTime(2027, 3, 10, 13),
      );

      final dragged = CalendaEventAdapter(
        drifId: eventId,
        calendarId: calId,
        title: 'Seam event',
        start: oldStart.add(const Duration(hours: 3)),
        end: oldStart.add(const Duration(hours: 4)),
      );
      await container.read(updateEventProvider)(
        dragged.drifId,
        dragged.toUpdateCompanion(),
      );

      await settleBatch(scheduleCount: 1);
      expect(schedules.single.id, reminderId);
      expect(schedules.single.triggerTime, DateTime(2027, 3, 10, 16));
    });

    test('3 回收站恢复事件 → 重挂提醒（行仍在时按行内时刻排）', () async {
      await wireSeamConsumers();
      final start = DateTime(2027, 3, 12, 10);
      final eventId = await insertEvent(
        start: start,
        deletedAt: DateTime(2027, 3, 11),
      );
      final reminderId = await insertReminder(
        'event',
        eventId,
        DateTime(2027, 3, 12, 9, 45),
      );

      await container.read(restoreEventProvider)(eventId);

      await settleBatch(scheduleCount: 1);
      expect(schedules.single.id, reminderId);
      expect(schedules.single.triggerTime, DateTime(2027, 3, 12, 9, 45));

      final applied = flatBatches().single as RecordApplied;
      expect(applied.localId, eventId);
      expect(applied.previousReference, start);
    });
  });

  group('待办写路径', () {
    test('2 moveOverdueToToday 3 条 → 每条按自己的位移重排', () async {
      await wireSeamConsumers();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueA = DateTime(today.year, today.month, today.day - 6, 9);
      final dueB = DateTime(today.year, today.month, today.day - 3, 9);
      final dueC = DateTime(today.year, today.month, today.day - 1, 9);
      final todoA = await insertTodo(dueDate: dueA);
      final todoB = await insertTodo(dueDate: dueB);
      final todoC = await insertTodo(dueDate: dueC);
      // 提醒相对 due 的偏移分别是 +2d / +3d / +1d。移动后的参考时间是"今天
      // 00:00"，所以位移后的时刻 = 今天 00:00 + 偏移（三条都落在未来，才可观
      // 察；负偏移会落进 pastDue 档，那是 T2 已钉死的另一档）。
      final reminderA = await insertReminder('todo', todoA, dueA.add(const Duration(days: 2)));
      final reminderB = await insertReminder('todo', todoB, dueB.add(const Duration(days: 3)));
      final reminderC = await insertReminder('todo', todoC, dueC.add(const Duration(days: 1)));

      await container.read(moveOverdueToTodayProvider)([
        todoA,
        todoB,
        todoC,
      ]);

      await settleBatch(scheduleCount: 3);
      final byId = <int, DateTime>{
        for (final r in schedules) r.id: r.triggerTime,
      };
      expect(byId[reminderA], DateTime(today.year, today.month, today.day + 2));
      expect(byId[reminderB], DateTime(today.year, today.month, today.day + 3));
      expect(byId[reminderC], DateTime(today.year, today.month, today.day + 1));

      final applied = flatBatches().cast<RecordApplied>();
      expect(applied, hasLength(3), reason: '每条被移动的 todo 各一条 applied');
      expect(
        {for (final a in applied) a.localId: a.previousReference},
        {todoA: dueA, todoB: dueB, todoC: dueC},
        reason: 'previousReference 必须是写前的旧 dueDate（位移锚）',
      );
    });
  });

  group('ICS 导入', () {
    String icsWith(String body) =>
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n'
        '$body'
        'END:VCALENDAR\r\n';

    test('4 ICS 2 行正常 + 1 行畸形 → 落 2 行 + 2 条 applied、0 条 removed', () async {
      await wireSeamConsumers();
      final ics = icsWith(
        'BEGIN:VEVENT\r\nUID:one@dayspark\r\nDTSTAMP:20270301T000000Z\r\nSUMMARY:Imported one\r\n'
        'DTSTART:20270315T100000\r\nDTEND:20270315T110000\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:bad@dayspark\r\nDTSTAMP:20270301T000000Z\r\nSUMMARY:Malformed row\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:two@dayspark\r\nDTSTAMP:20270301T000000Z\r\nSUMMARY:Imported two\r\n'
        'DTSTART:20270315T120000\r\nDTEND:20270315T130000\r\nEND:VEVENT\r\n',
      );

      final result = await IcsService(db).importIcs(ics, calId);

      expect(result, (events: 2, todos: 0));
      final rows = await db.select(db.events).get();
      expect(rows.map((e) => e.summary), ['Imported one', 'Imported two']);

      await waitUntil(() => batches.isNotEmpty);
      final flat = flatBatches();
      expect(flat.whereType<RecordRemoved>(), isEmpty);
      final applied = flat.cast<RecordApplied>();
      expect(applied, hasLength(2));
      expect(applied.map((a) => a.type), everyElement(RecordType.event));
      expect(applied.map((a) => a.localId), rows.map((r) => r.id));
      expect(applied.map((a) => a.previousReference), everyElement(isNull));
    });

    test('5 ICS 导入 → 小组件快照立即含导入事件（不再靠 tableUpdates）', () async {
      await wireSeamConsumers(widget: true);
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final ics = icsWith(
        'BEGIN:VEVENT\r\nUID:today@dayspark\r\nDTSTAMP:20270301T000000Z\r\nSUMMARY:Imported today\r\n'
        'DTSTART:${stamp}T100000\r\nDTEND:${stamp}T110000\r\nEND:VEVENT\r\n',
      );

      await IcsService(db).importIcs(ics, calId);

      await waitUntil(
        () => (store[HomeWidgetService.snapshotKey] as String? ?? '')
            .contains('Imported today'),
      );
      final snapshot =
          jsonDecode(store[HomeWidgetService.snapshotKey] as String)
              as Map<String, dynamic>;
      expect(
        jsonEncode(snapshot['todayEvents']),
        contains('Imported today'),
        reason: 'ICS 导入必须立刻把新事件推进快照（裸 insert 不给 tableUpdates 了）',
      );
    });
  });

  group('账号身份重写', () {
    test('6 身份切换的全表元数据重写 → 一条粗粒度 bulkChanged 且 0 次平台调用', () async {
      SharedPreferences.setMockInitialValues({
        appLocalePrefKey: 'en',
        'account_email': 'old@example.com',
        'last_sync_identity': 'https://sync.example.com|user-1',
      });
      final scoped = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(notif),
          syncTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          accountAuthApiFactoryProvider.overrideWithValue(
            (baseUrl) => _FakeAuthApi(
              const AuthSession(
                userId: 'user-2',
                accessToken: 'access-2',
                refreshToken: 'refresh-2',
              ),
            ),
          ),
          syncEngineProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(scoped.dispose);
      scoped.read(recordBusProvider).changes.listen(batches.add);
      scoped.read(reminderReconcilerProvider);
      await pumpEventQueue(times: 20);

      final todoId = await insertTodo(dueDate: DateTime(2027, 5, 1, 9));
      final reminderId = await insertReminder(
        'todo',
        todoId,
        DateTime(2027, 5, 1, 8),
      );
      schedules.clear();
      cancels.clear();
      batches.clear();

      await scoped.read(accountAuthProvider.future);
      await scoped
          .read(accountAuthProvider.notifier)
          .login(
            serverUrl: 'https://sync.example.com/',
            email: 'new@example.com',
            password: 'secret123',
          );

      await waitUntil(() => batches.isNotEmpty);
      await pumpEventQueue(times: 50);
      final flat = flatBatches();
      expect(flat.whereType<RecordApplied>(), isEmpty);
      expect(flat.whereType<RecordRemoved>(), isEmpty);
      expect(
        flat.whereType<RecordsBulkChanged>().map((c) => c.type).toSet(),
        {RecordType.event, RecordType.todo},
        reason: '两类记录各一条粗粒度事件（不逐个 id）',
      );
      expect(flat, hasLength(2));
      for (final change in flat) {
        expect((change as RecordsBulkChanged).reason, 'identity-reset');
      }
      expect(schedules, isEmpty, reason: '参考时间与父状态都没变 → 零平台调用');
      expect(cancels, isEmpty);

      final row = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(todoId))).getSingle();
      expect(row.syncId, isNull);

      // 正向对照：消费端确实活着——同一条总线上再发一条真事件就会排提醒。
      scoped.read(recordBusProvider).publish([
        RecordApplied(RecordType.todo, todoId, previousReference: null),
      ]);
      await settleBatch(scheduleCount: 1);
      expect(schedules.single.id, reminderId);
      expect(schedules.single.triggerTime, DateTime(2027, 5, 1, 8));
    });
  });

  // referenceChanged 是 T4 applier 应用"远端改期"时用的那一格：父行已被写（写它的人
  // 未必知道旧值），这里只登记位移，由重排器按 Δ 搬移行内时刻并物化回写。
  group('referenceChanged（位移登记格）', () {
    test('R1a 父行已改 + 只登记位移 → 按 Δ 位移、物化回写、恰好 1 次调度', () async {
      await wireSeamConsumers();
      final oldDue = DateTime(2027, 7, 1, 9);
      final newDue = DateTime(2027, 7, 1, 15);
      final todoId = await insertTodo(dueDate: newDue);
      final reminderId = await insertReminder(
        'todo',
        todoId,
        DateTime(2027, 7, 1, 8),
      );

      await RecordScope.run(
        db,
        (tx) => ReminderWriter.referenceChanged(
          db,
          tx,
          parentType: 'todo',
          parentId: todoId,
          previousReference: oldDue,
        ),
      );

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(schedules.single.id, reminderId);
      expect(schedules.single.triggerTime, DateTime(2027, 7, 1, 14));
      expect(
        await reminderTriggerTime(reminderId),
        DateTime(2027, 7, 1, 14),
        reason: '位移结果必须物化回写，否则第二次改期会按上一段位移漂移',
      );
      expect(cancels, isEmpty);
    });

    test('R1b 同批里父行更新 + 位移登记 → 位移只施加一次（不叠加、也不丢失）', () async {
      await wireSeamConsumers();
      final oldDue = DateTime(2027, 7, 2, 9);
      final newDue = DateTime(2027, 7, 2, 15);
      final todoId = await insertTodo(dueDate: oldDue);
      await insertReminder('todo', todoId, DateTime(2027, 7, 2, 8));

      await RecordScope.run(db, (tx) async {
        await TodoWriter.updateTodo(
          db,
          tx,
          todoId,
          TodosCompanion(dueDate: Value(newDue)),
        );
        await ReminderWriter.referenceChanged(
          db,
          tx,
          parentType: 'todo',
          parentId: todoId,
          previousReference: oldDue,
        );
      });

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(
        schedules.single.triggerTime,
        DateTime(2027, 7, 2, 14),
        reason: 'Δ 施加一次：不是 08:00（位移丢失），也不是 20:00（叠加两次）',
      );
      expect(cancels, isEmpty);
    });

    test('R1c 成对：同值重复登记 → 0 调用；真的变了再登记 → 立刻位移（名字即契约）', () async {
      await wireSeamConsumers();
      final due = DateTime(2027, 7, 3, 9);
      final todoId = await insertTodo(dueDate: due);
      await insertReminder('todo', todoId, DateTime(2027, 7, 3, 8));

      await RecordScope.run(
        db,
        (tx) => ReminderWriter.referenceChanged(
          db,
          tx,
          parentType: 'todo',
          parentId: todoId,
          previousReference: due,
        ),
      );
      await settleBatch(scheduleCount: 1);
      schedules.clear();
      cancels.clear();

      await RecordScope.run(
        db,
        (tx) => ReminderWriter.referenceChanged(
          db,
          tx,
          parentType: 'todo',
          parentId: todoId,
          previousReference: due,
        ),
      );

      await settleBatch();
      expect(schedules, isEmpty);
      expect(cancels, isEmpty);

      // 成对的正向：applier 真把父行改到别处后再登记同一个 previousReference，
      // 位移必须发生（这条把"静默 no-op"与"真的无变化"区分开）。
      final laterDue = DateTime(2027, 7, 3, 13);
      await (db.update(db.todos)..where((t) => t.id.equals(todoId))).write(
        TodosCompanion(dueDate: Value(laterDue)),
      );
      await RecordScope.run(
        db,
        (tx) => ReminderWriter.referenceChanged(
          db,
          tx,
          parentType: 'todo',
          parentId: todoId,
          previousReference: due,
        ),
      );

      await settleBatch(scheduleCount: 1);
      expect(schedules, hasLength(1));
      expect(schedules.single.triggerTime, DateTime(2027, 7, 3, 12));
    });
  });

  group('提醒行写路径', () {
    test('7a 提醒行新增 → 登记 applied（Δ=0）且整批落到行内时刻', () async {
      await wireSeamConsumers();
      final due = DateTime(2027, 4, 2, 9);
      final todoId = await insertTodo(dueDate: due);
      final trigger = DateTime(2027, 4, 2, 8);

      final reminderId = await container.read(createReminderProvider)(
        parentType: 'todo',
        parentId: todoId,
        triggerTime: trigger,
      );

      await waitUntil(() => batches.isNotEmpty);
      final applied = flatBatches().single as RecordApplied;
      expect(applied.type, RecordType.todo);
      expect(applied.localId, todoId);
      expect(applied.previousReference, due);

      await settleBatch(scheduleCount: 1);
      final forReminder = schedules.where((r) => r.id == reminderId).toList();
      expect(forReminder, isNotEmpty);
      for (final reminder in forReminder) {
        expect(reminder.triggerTime, trigger);
      }
      expect(await reminderTriggerTime(reminderId), trigger);
    });

    test('7b 提醒行删除 → 登记 removed 携带该 id，且该 id 被 cancel', () async {
      await wireSeamConsumers();
      final todoId = await insertTodo(dueDate: DateTime(2027, 4, 5, 9));
      final reminderId = await container.read(createReminderProvider)(
        parentType: 'todo',
        parentId: todoId,
        triggerTime: DateTime(2027, 4, 5, 8),
      );
      await waitUntil(() => batches.isNotEmpty);
      batches.clear();
      cancels.clear();

      await container.read(deleteReminderProvider)(reminderId);

      await waitUntil(() => batches.isNotEmpty);
      final removed = flatBatches().single as RecordRemoved;
      expect(removed.type, RecordType.todo);
      expect(removed.localId, todoId);
      expect(removed.reminderIds, [reminderId]);

      await settleBatch(cancelCount: 1);
      expect(cancels, contains(reminderId));
      final rows = await db.select(db.reminders).get();
      expect(rows.where((r) => r.id == reminderId), isEmpty);
    });
  });
}
