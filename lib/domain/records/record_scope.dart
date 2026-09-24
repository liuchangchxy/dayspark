import 'dart:async';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import 'record_bus.dart';
import 'record_change.dart';

final class RecordScope {
  RecordScope._();

  static final Object _scopeKey = Object();

  final List<RecordChange> _pending = <RecordChange>[];
  bool _closed = false;

  static Future<T> run<T>(
    AppDatabase db,
    Future<T> Function(RecordScope tx) body,
  ) async {
    final joined = Zone.current[_scopeKey] as RecordScope?;
    if (joined != null) return body(joined);
    _rejectForeignTransaction();

    final scope = RecordScope._();
    try {
      final result = await runZoned<Future<T>>(
        () => db.transaction(() => body(scope)),
        zoneValues: <Object, Object>{_scopeKey: scope},
      );
      RecordBus.of(db).publish(scope._drain());
      return result;
    } finally {
      scope._closed = true;
    }
  }

  static void _rejectForeignTransaction() {
    final driftUser = Zone.current[#DatabaseConnectionUser];
    if (driftUser == null) return;
    throw StateError(
      'RecordScope.run 不得在他人开的 drift 事务里调用'
      '（db.transaction / db.exclusively / db.runWithInterceptor 都会命中同一事务 zone）：'
      '那里的“提交”只是 RELEASE SAVEPOINT，外层未提交事件就已发布，'
      '外层一旦回滚就会留下与库内不符的幽灵事件。'
      '请把外层 db.transaction(...) 换成本缝自己开事务：'
      'RecordScope.run(db, (tx) async { ... })。',
    );
  }

  void applied(RecordType type, int localId, {DateTime? previousReference}) {
    _register(
      RecordApplied(type, localId, previousReference: previousReference),
    );
  }

  void removed(RecordType type, int localId, {required List<int> reminderIds}) {
    _register(RecordRemoved(type, localId, reminderIds: reminderIds));
  }

  // 粗粒度登记：整表元数据重写（身份切换 / baseline 回填）不逐个 id 登记，
  // 消费端按 type 自行决定要不要重读。
  void bulkChanged(RecordType type, {required String reason}) {
    _register(RecordsBulkChanged(type, reason: reason));
  }

  void _register(RecordChange change) {
    if (_closed) {
      throw StateError(
        'RecordScope 已在提交时关闭：登记必须发生在 run 的 body 内'
        '（body 结束后再登记会静默漏发事件，派生态就再也不会被通知）。',
      );
    }
    _pending.add(change);
  }

  List<RecordChange> _drain() {
    final drained = List<RecordChange>.of(_pending);
    _pending.clear();
    return drained;
  }
}
