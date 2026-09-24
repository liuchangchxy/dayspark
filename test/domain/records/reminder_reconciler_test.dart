import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintThrottled;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/record_bus_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark/domain/records/reminder_reconciler.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

class _MockNotificationService extends Mock implements NotificationService {}

// Counts reads of the reminders table so "each parent is reconciled once per
// batch" is observable: platform calls alone cannot see it, because the
// per-parent state cache already collapses a second pass into zero calls.
class _ReminderReadCounter extends QueryInterceptor {
  int count = 0;
  int writes = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('"reminders"')) count++;
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('reminders')) writes++;
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('UPDATE') && statement.contains('reminders')) {
      writes++;
    }
    return super.runCustom(executor, statement, args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> logs;

  // Hand-picked clock so every expectation below is a hand-computed literal.
  final now = DateTime(2026, 6, 1, 12);
  final dueA = DateTime(2026, 6, 10, 9);
  final triggerA = DateTime(2026, 6, 10, 8);

  late AppDatabase db;
  late _ReminderReadCounter reads;
  late _MockNotificationService notif;
  late ReminderReconciler reconciler;
  late int calId;
  late List<Reminder> schedules;
  late List<int> cancels;

  void stubNotificationService() {
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
    when(
      () => notif.snooze(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        scheduledTime: any(named: 'scheduledTime'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({appLocalePrefKey: 'en'});
    logs = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    reads = _ReminderReadCounter();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(reads));
    notif = _MockNotificationService();
    schedules = <Reminder>[];
    cancels = <int>[];
    stubNotificationService();
    calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Test'));
    reconciler = ReminderReconciler(
      db: db,
      notifications: notif,
      clock: () => now,
    );
  });

  tearDown(() async {
    debugPrint = debugPrintThrottled;
    await db.close();
  });

  Future<int> insertTodo({
    DateTime? dueDate,
    String status = 'NEEDS-ACTION',
    DateTime? deletedAt,
    int sortOrder = 0,
  }) {
    return db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Reconciler todo',
            dueDate: Value(dueDate),
            status: Value(status),
            deletedAt: Value(deletedAt),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  Future<void> setDueDate(int id, DateTime? dueDate) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(dueDate: Value(dueDate), updatedAt: Value(now)),
    );
  }

  Future<void> setStatus(int id, String status) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(status: Value(status)),
    );
  }

  Future<void> setDeletedAt(int id, DateTime? deletedAt) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(deletedAt: Value(deletedAt)),
    );
  }

  Future<int> insertReminder(DateTime triggerTime, {int? parentId}) {
    return db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            parentType: 'todo',
            parentId: parentId ?? 0,
            triggerTime: triggerTime,
          ),
        );
  }

  Future<int> seedTodoWithReminder({
    DateTime? dueDate,
    DateTime? triggerTime,
    String status = 'NEEDS-ACTION',
    DateTime? deletedAt,
    bool withoutDueDate = false,
  }) async {
    final id = await insertTodo(
      dueDate: withoutDueDate ? null : (dueDate ?? dueA),
      status: status,
      deletedAt: deletedAt,
    );
    await insertReminder(triggerTime ?? triggerA, parentId: id);
    return id;
  }

  // 条件等待而不是固定次数的 pumpEventQueue：全套件并行跑时事件循环会被挤，
  // 固定次数可能还没等到总线批落地就断言，属于假红。
  Future<void> waitUntil(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await pumpEventQueue(times: 5);
    }
  }

  Future<int> reminderIdOf(int parentId) async {
    final row =
        await (db.select(db.reminders)
              ..where((t) => t.parentId.equals(parentId)))
            .getSingle();
    return row.id;
  }

  void resetLogs() {
    reset(notif);
    stubNotificationService();
    schedules.clear();
    cancels.clear();
    logs.clear();
    reads.writes = 0;
  }

  void expectNoPlatformCalls() {
    expect(schedules, isEmpty);
    expect(cancels, isEmpty);
    verifyNever(() => notif.cancel(any()));
    verifyNever(
      () => notif.scheduleFromReminder(
        any(),
        eventReminderTitle: any(named: 'eventReminderTitle'),
        todoReminderTitle: any(named: 'todoReminderTitle'),
        eventReminderBody: any(named: 'eventReminderBody'),
        todoReminderBody: any(named: 'todoReminderBody'),
      ),
    );
    verifyNever(
      () => notif.snooze(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        scheduledTime: any(named: 'scheduledTime'),
        payload: any(named: 'payload'),
      ),
    );
  }

  group('nextTrigger（纯函数，人工手算字面量）', () {
    // reference / previousReference / storedTrigger → expected
    final cases = <String, (DateTime?, DateTime?, DateTime?, DateTime?)>{
      // 规则 1：父行没有时间了 → 无提醒
      'reference == null → null': (null, dueA, triggerA, null),
      // 规则 2：无位移依据 → 原样保留（新建/从无到有/提醒行后加）
      'previousReference == null → storedTrigger': (
        dueA,
        null,
        triggerA,
        triggerA,
      ),
      'previousReference == null 且 storedTrigger 为过去 → 仍是 storedTrigger（由 pastDue 档决定不动，不由本函数吞掉）': (
        dueA,
        null,
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 1),
      ),
      // 规则 3：位移
      'Δ = +1 天 12 小时': (
        DateTime(2026, 6, 11, 21),
        dueA,
        triggerA,
        DateTime(2026, 6, 11, 20),
      ),
      'Δ = -3 小时': (
        DateTime(2026, 6, 10, 6),
        dueA,
        triggerA,
        DateTime(2026, 6, 10, 5),
      ),
      'Δ = 0 → 原样': (dueA, dueA, triggerA, triggerA),
      'Δ = 0 而 storedTrigger 在午夜前 → 原样': (
        dueA,
        dueA,
        DateTime(2026, 6, 10, 0),
        DateTime(2026, 6, 10, 0),
      ),
      // 跨 DST 的 24h 语义：Δ 是绝对瞬间差（difference），不是墙钟字段差，
      // 所以 24h 位移跨越 DST 边界时仍按 24h 绝对位移搬移（UTC 字面量固定绝对时刻，
      // 与运行机器的时区无关）。
      '跨 DST 的 24h 绝对位移': (
        DateTime.utc(2026, 3, 8, 12),
        DateTime.utc(2026, 3, 7, 12),
        DateTime.utc(2026, 3, 8, 10),
        DateTime.utc(2026, 3, 9, 10),
      ),
      '跨 DST 的 -24h 绝对位移': (
        DateTime.utc(2026, 11, 1, 12),
        DateTime.utc(2026, 11, 2, 12),
        DateTime.utc(2026, 11, 2, 10),
        DateTime.utc(2026, 11, 1, 10),
      ),
      // 规则 3 的第二句：没有 storedTrigger 就没有可搬移的锚
      'storedTrigger == null 且 previousReference != null → null': (
        dueA,
        DateTime(2026, 6, 9),
        null,
        null,
      ),
    };

    cases.forEach((name, c) {
      test(name, () {
        expect(
          nextTrigger(
            reference: c.$1,
            previousReference: c.$2,
            storedTrigger: c.$3,
          ),
          c.$4,
        );
      });
    });
  });

  group('重排器', () {
    test('2 改 due date → 调度到精确到秒的新时刻', () async {
      final todoId = await seedTodoWithReminder();
      final newDue = DateTime(2026, 6, 12, 9, 30);

      await setDueDate(todoId, newDue);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      final scheduledRows = schedules;
      expect(scheduledRows, hasLength(1));
      expect(scheduledRows.single.id, isNot(0));
      // 手算：storedTrigger 08:00 + Δ(2 天 30 分) = 06-12 08:30:00
      expect(scheduledRows.single.triggerTime, DateTime(2026, 6, 12, 8, 30));
      expect(
        scheduledRows.single.triggerTime.second,
        0,
        reason: '精确到秒：新触发时刻必须是完整的 08:30:00',
      );
      expect(cancels, isEmpty);
    });

    test('3 清空 due date → cancel 该 parent 的全部 reminder id', () async {
      final todoId = await insertTodo(dueDate: dueA);
      final first = await insertReminder(triggerA, parentId: todoId);
      final second = await insertReminder(
        DateTime(2026, 6, 9, 9),
        parentId: todoId,
      );

      await setDueDate(todoId, null);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(cancels..sort(), [first, second]..sort());
      expect(schedules.length, 0);
    });

    test('4a 完成 → cancel', () async {
      final todoId = await seedTodoWithReminder();

      await setStatus(todoId, 'COMPLETED');
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(cancels, hasLength(1));
      expect(schedules.length, 0);
    });

    test('4b 取消完成 → 重新调度未来提醒', () async {
      final todoId = await seedTodoWithReminder();
      await setStatus(todoId, 'COMPLETED');
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(cancels, hasLength(1));
      expect(schedules.length, 0);

      await setStatus(todoId, 'NEEDS-ACTION');
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(schedules.length, 1);
      expect(schedules.single.triggerTime, triggerA);
    });

    test('4c inactive 档不看行内时刻：行内已成过去也照样 cancel（与 pastDue 档成对）', () async {
      final todoId = await seedTodoWithReminder(
        triggerTime: DateTime(2026, 5, 20, 8),
      );

      await setStatus(todoId, 'COMPLETED');
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      // inactive 档不看行内时刻：父行不再活跃就必须撤，行内时刻已成过去也一样
      // （与 pastDue 档成对——后者恰恰不动）
      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('5a 进回收站 → cancel', () async {
      final todoId = await seedTodoWithReminder();

      await setDeletedAt(todoId, DateTime(2026, 6, 1, 11));
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(cancels, hasLength(1));
      expect(schedules.length, 0);
    });

    test('5b 恢复 → 重新调度未来提醒', () async {
      final todoId = await seedTodoWithReminder();
      await setDeletedAt(todoId, DateTime(2026, 6, 1, 11));
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(cancels, hasLength(1));

      await setDeletedAt(todoId, null);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(schedules.length, 1);
      expect(schedules.single.triggerTime, triggerA);
    });

    test('6a pastDue 且曾交给 OS 的时刻在未来 → cancel（旧闹钟是幽灵响铃）', () async {
      final todoId = await seedTodoWithReminder();
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.length, 1);

      // due date 挪到"现在之前"：期望变成过去 → 不能再排，但旧的那个未来闹钟必须撤
      final overdueDue = DateTime(2026, 6, 1, 6);
      await setDueDate(todoId, overdueDue);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(cancels, hasLength(1));
      expect(schedules.length, 1, reason: '只 cancel，不再排');
    });

    test('6b pastDue 且已过去/未知 → 不动（保护活跃 snooze）', () async {
      final todoId = await seedTodoWithReminder(
        triggerTime: DateTime(2026, 6, 1, 11),
      );

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expectNoPlatformCalls();
    });

    test('7 幂等：同状态重复 reconcile → 0 次平台调用', () async {
      final todoId = await seedTodoWithReminder();
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.length, 1);
      final readsAfterFirst = reads.count;
      resetLogs();

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expectNoPlatformCalls();
      expect(reads.count, readsAfterFirst, reason: '缓存命中连行都不重读');

      await reconciler.reconcileAll();
      expectNoPlatformCalls();
    });

    test('7b 同一位移被重复登记（第二批写前参考时间相同）→ 0 次平台调用', () async {
      final todoId = await seedTodoWithReminder();
      final movedDue = dueA.add(const Duration(days: 2));
      await setDueDate(todoId, movedDue);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.length, 1);
      resetLogs();

      // 父状态与缓存一致但写前参考时间仍是 A（重放/重复登记），早退条件不成立；
      // 此时算出的期望时刻与已交给 OS 的相同 → 不得重复调度。
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expectNoPlatformCalls();
    });

    test('8 reorderTodos / 纯文案编辑 / 身份重写 → 0 次平台调用', () async {
      // 本次会话从未重排过的父（账本为空）：身份重写若触发全量重算就会把它排上，
      // 缓存早退救不了这一条，所以它才是「bulkChanged → 0 调度」的真钉子。
      await seedTodoWithReminder();
      await reconciler.handle([
        RecordsBulkChanged(RecordType.todo, reason: 'identity-reset'),
      ]);
      expectNoPlatformCalls();

      final todoId = await seedTodoWithReminder();
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.length, 1);
      resetLogs();

      await (db.update(db.todos)..where((t) => t.id.equals(todoId))).write(
        TodosCompanion(
          summary: const Value('renamed'),
          sortOrder: const Value(7),
          updatedAt: Value(now),
        ),
      );
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expectNoPlatformCalls();

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expectNoPlatformCalls();

      await reconciler.handle([
        RecordsBulkChanged(RecordType.todo, reason: 'identity-reset'),
        RecordsBulkChanged(RecordType.event, reason: 'baseline'),
      ]);
      expectNoPlatformCalls();
    });

    test('9 批量：一次批含 5 条 todo → 每个父各 reconcile 一次（不是 5×N）', () async {
      final todos = <int>[];
      for (var i = 0; i < 5; i++) {
        final id = await insertTodo(dueDate: dueA.add(Duration(days: i)));
        await insertReminder(triggerA.add(Duration(days: i)), parentId: id);
        await insertReminder(
          dueA.add(Duration(days: i - 1)),
          parentId: id,
        );
        todos.add(id);
      }
      final readsBefore = reads.count;

      await reconciler.handle([
        for (final id in todos)
          RecordApplied(RecordType.todo, id, previousReference: dueA),
        // 同一父的第二条变更必须并入同一个父，不得各算一次
        RecordApplied(RecordType.todo, todos.first, previousReference: dueA),
      ]);

      expect(schedules.length, 10, reason: '5 个父 × 各 2 条 reminder，各排一次');
      expect(
        reads.count - readsBefore,
        5,
        reason: '每个父只读一次 reminder 行（6 条变更 → 5 个父）',
      );
      expect(cancels, isEmpty);

      // 同一父一个批里带两条位移不同的变更：以最早那条写前参考时间为准
      final target = todos.first;
      final movedDue = dueA.add(const Duration(days: 3));
      await setDueDate(target, movedDue);
      final before = schedules.length;
      await reconciler.handle([
        RecordApplied(RecordType.todo, target, previousReference: dueA),
        RecordApplied(RecordType.todo, target, previousReference: movedDue),
      ]);

      expect(schedules.length - before, 2);
      final moved = schedules.sublist(before);
      expect(
        moved.map((r) => r.triggerTime).toList(),
        [
          triggerA.add(const Duration(days: 3)),
          dueA.subtract(const Duration(days: 1)).add(const Duration(days: 3)),
        ],
      );
    });

    test('10 通知键恒为 parentType:parentId:reminderId，第三段是 reminder.id', () async {
      // 先插一条无关 todo，让父行 id 与 reminder 行 id 必然不同：
      // 否则第三段即使被写成 parentId 也"看起来对"，断言就空转了。
      await insertTodo(dueDate: dueA);
      final todoId = await seedTodoWithReminder();
      expect(todoId, isNot(1));

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      final rows = await db.select(db.reminders).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, isNot(todoId));
      final scheduledRow = schedules.single;
      expect(scheduledRow.id, rows.single.id, reason: '通知 id 就是 reminder 行 id');
      expect(scheduledRow.parentType, 'todo');
      expect(scheduledRow.parentId, todoId);

      final payload = NotificationPayload(
        parentType: scheduledRow.parentType,
        parentId: scheduledRow.parentId,
        reminderId: scheduledRow.id,
      ).encode();
      expect(payload, 'todo:$todoId:${rows.single.id}');
      final parsed = NotificationPayload.tryParse(payload);
      expect(parsed!.parentType, 'todo');
      expect(parsed.parentId, todoId);
      expect(parsed.reminderId, rows.single.id);
    });

    test('13 removed → cancel 事件携带的 reminderIds（行已被硬删，按行遍历够不到）', () async {
      final todoId = await insertTodo(dueDate: dueA);
      final reminderId = await insertReminder(triggerA, parentId: todoId);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.length, 1);

      await (db.delete(
        db.reminders,
      )..where((t) => t.parentId.equals(todoId))).go();
      await (db.delete(db.todos)..where((t) => t.id.equals(todoId))).go();
      await reconciler.handle([
        RecordRemoved(RecordType.todo, todoId, reminderIds: [reminderId]),
      ]);

      expect(cancels, [reminderId]);
    });

    test('14 冷启动（_applied 为空）也要撤 inactive 三档：已完成 / 回收站 / 参考时间为空', () async {
      final activeId = await seedTodoWithReminder();
      final completedId = await seedTodoWithReminder(status: 'COMPLETED');
      final trashedId = await seedTodoWithReminder(
        deletedAt: DateTime(2026, 5, 30),
      );
      final noReferenceId = await seedTodoWithReminder(withoutDueDate: true);
      // pastDue 档是唯一进保守门的档：行内已成过去且本次会话没调度过 → 不动
      final pastDueId = await seedTodoWithReminder(
        triggerTime: DateTime(2026, 5, 1, 8),
      );

      await reconciler.reconcileAll();

      expect(
        schedules.map((r) => r.parentId).toList(),
        [activeId],
        reason: '只补排行内说未来的活跃父行',
      );
      expect(cancels.toSet(), {
        await reminderIdOf(completedId),
        await reminderIdOf(trashedId),
        await reminderIdOf(noReferenceId),
      }, reason: '父行状态是权威的：冷启动、_applied 为空也必须撤这三档');
      expect(
        cancels,
        isNot(contains(await reminderIdOf(pastDueId))),
        reason: 'pastDue 档的保守门仍在：snooze 歧义不能按行判',
      );
    });

    test('16 规则 2 返回过去时刻 → 落入 pastDue 档，0 次调度', () async {
      final todoId = await seedTodoWithReminder(
        triggerTime: DateTime(2026, 5, 1, 8),
      );

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: null),
      ]);

      expect(schedules, isEmpty, reason: '过去的期望时刻不得当未来提醒排上去');
      expect(cancels, isEmpty, reason: 'pastDue + 未知 → 不动，保护 snooze');

      await reconciler.reconcileAll();
      expectNoPlatformCalls();
    });

    test('17 连续两次改期：期望 = t0 + (r2 − r0)，不是 t0 + (r2 − r1)', () async {
      final todoId = await seedTodoWithReminder();
      final r1 = dueA.add(const Duration(days: 2));
      await setDueDate(todoId, r1);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.last.triggerTime, DateTime(2026, 6, 12, 8));
      resetLogs();

      final r2 = r1.add(const Duration(days: 3));
      await setDueDate(todoId, r2);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);

      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [DateTime(2026, 6, 15, 8)],
        reason: '位移锚必须跟着当前 reference：t0 + (r2 − r0) = 06-15 08:00',
      );
      expect(cancels, isEmpty);
    });

    test('18 第二次改期算出的期望落在过去 → 不得撤掉正确的通知又不排（永不响）', () async {
      final todoId = await seedTodoWithReminder();
      final r1 = dueA.add(const Duration(days: 2));
      await setDueDate(todoId, r1);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.last.triggerTime, DateTime(2026, 6, 12, 8));
      resetLogs();

      // r2 比 r1 早 9 天：陈旧锚点会算出 06-01 08:00（已成过去）→ 旧实现在这里
      // cancel 掉 06-12 08:00 的幽灵响铃判断，于是既撤又不再排 = 永不响。
      final r2 = r1.subtract(const Duration(days: 9));
      await setDueDate(todoId, r2);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);

      expect(cancels, isEmpty, reason: '不得撤掉原本正确的 06-12 08:00');
      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [DateTime(2026, 6, 3, 8)],
        reason: 't0 + (r2 − r0)，且仍在未来',
      );
    });

    test('19 改期后 完成 → 取消完成：按当前 reference 排，不是陈旧行值', () async {
      final todoId = await seedTodoWithReminder();
      final r1 = dueA.add(const Duration(days: 2));
      await setDueDate(todoId, r1);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      resetLogs();

      await setStatus(todoId, 'COMPLETED');
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);
      expect(cancels, hasLength(1));

      resetLogs();
      await setStatus(todoId, 'NEEDS-ACTION');
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);

      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [DateTime(2026, 6, 12, 8)],
        reason: '取消完成时行内锚点必须还是当前 reference 的值',
      );
    });

    test('20 跨重启（新实例、账本为空）后改期仍得到正确时刻', () async {
      final todoId = await seedTodoWithReminder();
      final r1 = dueA.add(const Duration(days: 2));
      await setDueDate(todoId, r1);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      resetLogs();

      final restarted = ReminderReconciler(
        db: db,
        notifications: notif,
        clock: () => now,
      );
      final r2 = r1.add(const Duration(days: 3));
      await setDueDate(todoId, r2);
      await restarted.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);

      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [DateTime(2026, 6, 15, 8)],
        reason: '锚点在行内（已回写），内存锚过不了重启这一关',
      );
      expect(cancels, isEmpty);
    });

    test('21 CANCELLED（ical_converter 会写）也算 inactive：cancel', () async {
      final todoId = await seedTodoWithReminder(status: 'CANCELLED');

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      expect(cancels, hasLength(1));
      expect(schedules, isEmpty);
    });

    test('22 物化写失败：可观测 + 同 reference 的事件会重试（不再被缓存吞掉）', () async {
      final todoId = await seedTodoWithReminder();
      await db.customStatement(
        'CREATE TRIGGER block_reminder_write BEFORE UPDATE ON reminders '
        "BEGIN SELECT RAISE(ABORT, 'blocked'); END;",
      );

      final r1 = dueA.add(const Duration(days: 2));
      await setDueDate(todoId, r1);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);

      // (i) 失败不是纯静默：对外动作整段跳过，但日志里有可归因的记录
      expect(schedules, isEmpty);
      expect(cancels, isEmpty);
      expect(
        logs.where((l) => l.contains('reconcile todo:$todoId failed')),
        isNotEmpty,
        reason: '物化失败必须留下可追踪的日志（消费端吞异常不等于静默）',
      );

      // (ii) 同 reference 的事件会重新走一遍（失败不得把本父写进状态缓存，
      //      否则这次事件被早退吞掉 = 提醒永不响）。此时只有行内值可用，
      //      所以按 §2.1 规则 3 的 Δ=0 落在行内锚点——重点是"排上了"，不是 0 次。
      await db.customStatement('DROP TRIGGER block_reminder_write;');
      resetLogs();
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);
      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [triggerA],
        reason: '重试必须发生（行内锚点 = 06-10 08:00），而不是 0 次平台调用',
      );

      // (iii) 位移证据重放（prev 仍是 r0）：锚点没被写坏，落在正确时刻
      resetLogs();
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(schedules.map((r) => r.triggerTime).toList(), [
        DateTime(2026, 6, 12, 8),
      ]);

      // (iv) 且不再漂移：再改期一次仍按 t0 + (r2 − r0)
      resetLogs();
      final r2 = r1.add(const Duration(days: 3));
      await setDueDate(todoId, r2);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1),
      ]);
      expect(schedules.map((r) => r.triggerTime).toList(), [
        DateTime(2026, 6, 15, 8),
      ]);
    });

    test('23 亚秒 / UTC 的 previousReference：按瞬间比较，幂等且锚点分支仍生效', () async {
      final todoId = await seedTodoWithReminder();
      final r1 = dueA.add(const Duration(days: 2));

      // 模拟 T3/T4 把内存里的亚秒值登记进事件
      await setDueDate(todoId, r1);
      await reconciler.handle([
        RecordApplied(
          RecordType.todo,
          todoId,
          previousReference: dueA.subtract(const Duration(milliseconds: 500)),
        ),
      ]);
      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [DateTime(2026, 6, 12, 8)],
        reason: '期望时刻归一到落库精度（整秒），与行内值同一瞬间',
      );
      resetLogs();

      // (i) 重复同一事件：0 次写、0 次平台调用
      await reconciler.handle([
        RecordApplied(
          RecordType.todo,
          todoId,
          previousReference: dueA.subtract(const Duration(milliseconds: 500)),
        ),
      ]);
      expect(reads.writes, 0, reason: '亚秒不得造成写放大（每次 reconcile 都回写一行）');
      expectNoPlatformCalls();

      // (ii) 锚点分支仍生效：陈旧事件（prev 停在 r0）不得重复施加位移
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: dueA),
      ]);
      expect(reads.writes, 0);
      expectNoPlatformCalls();

      // UTC 事件同理：按瞬间比较，不因 isUtc 不同而反复回写
      resetLogs();
      final r2 = r1.add(const Duration(days: 3));
      await setDueDate(todoId, r2);
      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1.toUtc()),
      ]);
      expect(schedules.map((r) => r.triggerTime).toList(), [
        DateTime(2026, 6, 15, 8),
      ]);
      expect(reads.writes, 1, reason: '改期确实要回写一行（且只写一行）');
      resetLogs();

      await reconciler.handle([
        RecordApplied(RecordType.todo, todoId, previousReference: r1.toUtc()),
      ]);
      expect(reads.writes, 0);
      expectNoPlatformCalls();
    });

    test('15 装配：总线发布一批 → 重排器接手（被删掉的 todo_edit_page 补丁的替代路径）', () async {
      // provider 用真实时钟，故此处的时间基准相对 now 现取（nextTrigger 的
      // 手算字面量已由测试 1 钉住，这里只证明接线）。
      final base = DateTime.now().add(const Duration(days: 3));
      final due = DateTime(
        base.year,
        base.month,
        base.day,
        base.hour,
        base.minute,
        base.second,
      );
      final trigger = due.subtract(const Duration(hours: 1));
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: 'wired todo',
              dueDate: Value(due),
            ),
          );
      await insertReminder(trigger, parentId: todoId);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(notif),
        ],
      );
      addTearDown(container.dispose);
      container.read(reminderReconcilerProvider);
      await waitUntil(() => schedules.isNotEmpty);

      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [trigger],
        reason: '冷启动重算补排了行内说未来的提醒',
      );
      resetLogs();

      await setDueDate(todoId, due.add(const Duration(days: 1)));
      container.read(recordBusProvider).publish([
        RecordApplied(RecordType.todo, todoId, previousReference: due),
      ]);
      await waitUntil(() => schedules.isNotEmpty);

      expect(
        schedules.map((r) => r.triggerTime).toList(),
        [trigger.add(const Duration(days: 1))],
        reason: '改期事件经总线到达重排器：按新参考时间落到精确时刻',
      );
    });
  });
}
