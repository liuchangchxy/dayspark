import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
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
  // 上次排期时实际使用的语言（languageCode）。通知文案已经写死在 OS 里，
  // 这是判断「要不要为语言变更重排」的唯一可靠依据。
  String? _stringsLocale;
  // 我们物化过的行值：只有这些行的"所属 reference"确定等于 _parentStates 的锚点，
  // 才敢拿锚点当位移基准；行内值是写入路径建的（新建/后挂提醒行）时只能退回
  // 事件自述的 previousReference——那正是 §2.1 规则 2/3 的原意。
  final Map<int, DateTime> _materialized = <int, DateTime>{};
  final Map<_ParentKey, _ParentState> _parentStates = <_ParentKey, _ParentState>{};

  Future<void> _tail = Future<void>.value();

  Future<void> handle(List<RecordChange> batch) => _enqueue(() => _handle(batch));

  Future<void> reconcileAll() => _enqueue(_reconcileAll);

  /// 语言切换后重排：通知的 title/body 是排期时烘焙进 OS 的，_applied 只记
  /// 「上次交给 OS 的时刻」，时刻没变就短路——于是切语言后，切换之前排好的
  /// 提醒仍会按旧语言弹。清掉 _applied 再整轮重算，才会用新语言重新下发。
  ///
  /// 只清 _applied：_materialized/_parentStates 描述的是行值基线，与语言无关，
  /// 清掉反而会退化成「只能靠行内值兜底」（见 _reconcileParent 的基准选择）。
  /// 走 _enqueue 是同一条串行链，不会与批次重排交错。
  ///
  /// 以「上次排期实际用的语言」做判据，而不是让调用方去猜这是不是首次回调——
  /// 后者依赖「监听先于 localeProvider.load() 注册」，是个说不清的次序假设。
  /// 只清「确实交给过 OS」的条目（值非 null），保留「已知无通知」的 null 标记：
  /// 前者必须按新语言重发，后者本来就没东西可发，留着能省掉一轮无谓 cancel。
  Future<void> onLocaleChanged() => _enqueue(() async {
    final next = (await resolveAppLocale()).languageCode;
    if (_stringsLocale == next) return;
    _stringsLocale = next;
    _applied.removeWhere((_, handedToOs) => handedToOs != null);
    await _reconcileAll(force: true);
  });

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

  Future<void> _reconcileAll({bool force = false}) async {
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
          force: force,
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
    bool force = false,
  }) async {
    final key = (parentType, parentId);
    final parent = await _readParent(parentType, parentId);
    final reference = parent?.reference;
    final active = parent?.active ?? false;
    final state = (reference: reference, active: active);
    final anchorReference = _parentStates[key]?.reference;
    // 早退是常规优化：父状态与参考时间都没变 → 这一父没有任何事要做。
    // force 绕过它，用于「数据没变但平台侧必须重做」的场景——目前只有语言
    // 切换（通知文案已烘焙进 OS）。
    if (!force && _parentStates[key] == state && previousReference == reference) {
      return;
    }

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
    final locale = await resolveAppLocale();
    _stringsLocale = locale.languageCode;
    final strings = await loadNotificationStrings(locale: locale);
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
