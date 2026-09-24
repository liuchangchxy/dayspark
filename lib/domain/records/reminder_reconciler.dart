import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_change.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/reminder_writer.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

typedef _ParentKey = (String, int);

typedef _ParentState = ({DateTime? reference, bool active});

DateTime? nextTrigger({
  required DateTime? reference,
  required DateTime? previousReference,
  required DateTime? storedTrigger,
}) {
  if (reference == null) return null;
  if (previousReference == null) return storedTrigger;
  if (storedTrigger == null) return null;
  return storedTrigger.add(reference.difference(previousReference));
}

final class ReminderReconciler {
  ReminderReconciler({
    required AppDatabase db,
    required NotificationService notifications,
    DateTime Function()? clock,
  }) : _db = db,
       _notifications = notifications,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  // 上次实际交给 OS 的时刻（null = 已知没有通知）；缺键 = 本次会话没碰过。
  final Map<int, DateTime?> _applied = <int, DateTime?>{};
  // 我们物化过的行值：只有这些行的"所属 reference"确定等于 _parentStates 的锚点，
  // 才敢拿锚点当位移基准；行内值是写入路径建的（新建/后挂提醒行）时只能退回
  // 事件自述的 previousReference——那正是 §2.1 规则 2/3 的原意。
  final Map<int, DateTime> _materialized = <int, DateTime>{};
  final Map<_ParentKey, _ParentState> _parentStates = <_ParentKey, _ParentState>{};

  Future<void> _tail = Future<void>.value();

  Future<void> handle(List<RecordChange> batch) => _enqueue(() => _handle(batch));

  Future<void> reconcileAll() => _enqueue(_reconcileAll);

  // 两个入口共用一条串行链：批与批、重算与批都不得交错重排同一个父，否则会拿
  // 半更新的 _applied/父状态去求差。catchError 保证一次意外异常不会堵死整条链。
  Future<void> _enqueue(Future<void> Function() action) {
    final guarded = _tail
        .then((_) => action())
        .catchError((Object e) {
          debugPrint('reminder_reconciler: $e');
        });
    _tail = guarded;
    return guarded;
  }

  Future<void> _handle(List<RecordChange> batch) async {
    final removed = <_ParentKey, List<int>>{};
    final applied = <_ParentKey, DateTime?>{};
    for (final change in batch) {
      switch (change) {
        case RecordsBulkChanged():
          // 身份/baseline 重写只动同步标识，参考时间与父状态不变 → 零动作。
          break;
        case RecordRemoved(:final type, :final localId, :final reminderIds):
          final key = _keyOf(type, localId);
          removed.putIfAbsent(key, () => <int>[]).addAll(reminderIds);
        case RecordApplied(
          :final type,
          :final localId,
          :final previousReference,
        ):
          // 一个批 = 一个事务；同一父取批内最早那条写前参考时间——后一条的
          // previousReference 已是事务内的中间值，拿它算位移会少算一截。
          applied.putIfAbsent(_keyOf(type, localId), () => previousReference);
      }
    }

    for (final entry in removed.entries) {
      for (final id in entry.value) {
        if (_applied.containsKey(id) && _applied[id] == null) continue;
        await _safely('cancel reminder $id', () async {
          await _notifications.cancel(id);
          _applied[id] = null;
          _materialized.remove(id);
        });
      }
      _parentStates.remove(entry.key);
    }

    for (final entry in applied.entries) {
      if (removed.containsKey(entry.key)) continue;
      await _safely(
        'reconcile ${entry.key.$1}:${entry.key.$2}',
        () => _reconcileParent(
          parentType: entry.key.$1,
          parentId: entry.key.$2,
          previousReference: entry.value,
        ),
      );
    }
  }

  Future<void> _reconcileAll() async {
    final rows =
        await (_db.select(_db.reminders)
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    final parents = <_ParentKey>[];
    for (final row in rows) {
      final key = (row.parentType, row.parentId);
      if (parents.contains(key)) continue;
      parents.add(key);
    }

    for (final parent in parents) {
      await _safely(
        'reconcile ${parent.$1}:${parent.$2}',
        () => _reconcileParent(
          parentType: parent.$1,
          parentId: parent.$2,
          // 基准取会话内已知的锚点 reference；首次（冷启动）无锚点时交给
          // nextTrigger 规则 2 用行内值兜底——行内值现在会被物化回写，跨重启有效。
          previousReference: _parentStates[parent]?.reference,
        ),
      );
    }
  }

  Future<void> _reconcileParent({
    required String parentType,
    required int parentId,
    required DateTime? previousReference,
  }) async {
    final key = (parentType, parentId);
    final parent = await _readParent(parentType, parentId);
    final reference = parent?.reference;
    final active = parent?.active ?? false;
    final state = (reference: reference, active: active);
    final anchorReference = _parentStates[key]?.reference;
    if (_parentStates[key] == state && previousReference == reference) return;

    final reminders = await _readReminders(parentType, parentId);
    if (reminders.isEmpty) {
      _parentStates[key] = state;
      return;
    }
    final now = _clock();

    for (final reminder in reminders) {
      // 按瞬间比较：行内值经 drift 往返（整秒、local），事件里的 previousReference
      // 可能来自内存（亚秒 / UTC），用 == 会让锚点分支永远不成立。
      final owned = _materialized[reminder.id]?.isAtSameMomentAs(
        reminder.triggerTime,
      );
      final basis = (owned ?? false)
          ? (anchorReference ?? previousReference)
          : previousReference;
      final computed = active
          ? nextTrigger(
              reference: reference,
              previousReference: basis,
              storedTrigger: reminder.triggerTime,
            )
          : null;
      final desired = computed == null
          ? null
          : _atStoragePrecision(computed);
      if (desired != null && !desired.isAtSameMomentAs(reminder.triggerTime)) {
        // 先物化再对外动作：行内值是下一次位移的锚。物化失败时本趟对外动作
        // 会被 _safely 记日志后跳过，且本父不写状态缓存 → 下一次事件（同 reference
        // 亦可）重新走一遍；反过来先排后写，崩溃/写失败都会让锚点永久陈旧。
        await _materialize(reminder.id, desired);
      }
      if (desired != null && desired.isAfter(now)) {
        await _schedule(reminder, desired);
        continue;
      }
      await _settleEmpty(reminder, inactive: desired == null, now: now);
    }

    // 状态落位放在整段对外动作之后：中途失败（物化/调度抛错）就不写缓存，
    // 让下一次同 reference 的事件能重试；已成功的部分靠 _applied 与行内值
    // 比对短路，重试是幂等的。
    _parentStates[key] = state;
  }

  // drift 的 dateTime 落库精度是 unix 秒：期望时刻先归一到整秒，才能与行内值
  // 稳定比较（否则每趟 reconcile 都会判定"变了"而回写一次）。
  DateTime _atStoragePrecision(DateTime value) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch - value.millisecond,
      isUtc: value.isUtc,
    );
  }

  Future<void> _settleEmpty(
    Reminder reminder, {
    required bool inactive,
    required DateTime now,
  }) async {
    final handedToOs = _applied[reminder.id];
    final knownClean = _applied.containsKey(reminder.id) && handedToOs == null;
    final bool cancel;
    if (inactive) {
      // 父行状态（回收站/已完成/参考时间为空）是权威的，不需要本次会话的账本
      // 佐证：冷启动、_applied 为空也要撤，含 snooze（CONSTRAINTS.md 的 90 行）。
      cancel = !knownClean;
    } else {
      // pastDue：唯一进保守门的档——只有"曾交给 OS 的未来时刻"才是幽灵响铃，
      // 已过去/未知的是活跃 snooze（snooze 在 reminder.id 上重排，其行内
      // triggerTime 必然在过去），按行判会误杀。
      cancel = handedToOs != null && handedToOs.isAfter(now);
    }
    if (!cancel) return;
    await _notifications.cancel(reminder.id);
    _applied[reminder.id] = null;
  }

  Future<void> _materialize(int reminderId, DateTime triggerTime) async {
    await RecordScope.run(
      _db,
      (tx) =>
          ReminderWriter.materializeTrigger(_db, tx, reminderId, triggerTime),
    );
    _materialized[reminderId] = triggerTime;
  }

  Future<void> _schedule(Reminder reminder, DateTime desired) async {
    final applied = _applied[reminder.id];
    if (_applied.containsKey(reminder.id) &&
        applied != null &&
        applied.isAtSameMomentAs(desired)) {
      return;
    }
    final strings = await loadNotificationStrings();
    await _notifications.scheduleFromReminder(
      reminder.copyWith(triggerTime: desired),
      eventReminderTitle: strings.eventReminderTitle,
      todoReminderTitle: strings.todoReminderTitle,
      eventReminderBody: strings.eventReminderBody,
      todoReminderBody: strings.todoReminderBody,
    );
    _applied[reminder.id] = desired;
  }

  Future<void> _safely(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      // 派生态重排失败不得反噬写入路径（否则一条坏提醒会拖垮整批收敛），
      // 但也不许静默：日志必须能定位到是哪个父/哪条提醒失败的。
      debugPrint('reminder_reconciler: $what failed: $e');
    }
  }

  _ParentKey _keyOf(RecordType type, int localId) =>
      type == RecordType.event ? ('event', localId) : ('todo', localId);

  Future<_ParentState?> _readParent(String parentType, int parentId) async {
    if (parentType == 'event') {
      final event =
          await (_db.select(_db.events)
                ..where((t) => t.id.equals(parentId)))
              .getSingleOrNull();
      if (event == null) return null;
      return (reference: event.startDt, active: event.deletedAt == null);
    }
    final todo =
        await (_db.select(_db.todos)
              ..where((t) => t.id.equals(parentId)))
            .getSingleOrNull();
    if (todo == null) return null;
    return (
      reference: todo.dueDate,
      active:
          todo.deletedAt == null &&
          todo.status != 'COMPLETED' &&
          todo.status != 'CANCELLED',
    );
  }

  Future<List<Reminder>> _readReminders(String parentType, int parentId) {
    return (_db.select(_db.reminders)
          ..where(
            (t) => t.parentType.equals(parentType) & t.parentId.equals(parentId),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }
}
