import 'dart:async';

import 'package:dayspark/data/local/database/app_database.dart';

import 'record_change.dart';

final class RecordBus {
  RecordBus._();

  static final Expando<RecordBus> _buses = Expando<RecordBus>();

  static RecordBus of(AppDatabase db) => _buses[db] ??= RecordBus._();

  final StreamController<List<RecordChange>> _controller =
      StreamController<List<RecordChange>>.broadcast();

  Stream<List<RecordChange>> get changes => _controller.stream;

  void publish(List<RecordChange> batch) {
    assert(
      Zone.current[#DatabaseConnectionUser] == null,
      'RecordBus.publish 必须在任何 drift 事务之外调用（db.transaction / '
      'db.exclusively / db.runWithInterceptor 任一都会命中）：提交前发布会'
      '在外层回滚时留下幽灵事件。发布只属于 RecordScope.run 在事务返回之后。',
    );
    if (batch.isEmpty) return;
    _controller.add(batch);
  }
}
