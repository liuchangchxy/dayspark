import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';

final class ReminderWriter {
  const ReminderWriter._();

  // 派生文物化：只把重排器算出的触发时刻写回行内值，不建行、不删行、不动父行。
  // tx 有意不登记——这条写不改变领域事实（reminder 行的生命周期仍归写入路径），
  // 登记会在总线上转一圈回到重排器自己；空批会被 publish 直接丢弃。
  static Future<void> materializeTrigger(
    AppDatabase db,
    RecordScope tx,
    int id,
    DateTime triggerTime,
  ) async {
    await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(triggerTime: Value(triggerTime)),
    );
  }
}
