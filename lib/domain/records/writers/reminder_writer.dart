import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

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

  // 提醒行不改变父行的参考时间，只改变"这个父有几条提醒、分别排在哪"：
  // 登记 applied 时 previousReference 取父行当前参考时间（Δ=0 → 消费端按
  // 行内 triggerTime 排这条新提醒）。
  static Future<int> add(
    AppDatabase db,
    RecordScope tx, {
    required String parentType,
    required int parentId,
    required DateTime triggerTime,
  }) async {
    final id = await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            parentType: parentType,
            parentId: parentId,
            triggerTime: triggerTime,
          ),
        );
    tx.applied(
      _recordType(parentType),
      parentId,
      previousReference: await _referenceOf(db, parentType, parentId),
    );
    return id;
  }

  static Future<void> delete(AppDatabase db, RecordScope tx, int id) async {
    final row = await (db.select(
      db.reminders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await (db.delete(db.reminders)..where((t) => t.id.equals(id))).go();
    if (row == null) return;
    tx.removed(
      _recordType(row.parentType),
      row.parentId,
      reminderIds: <int>[id],
    );
  }

  static Future<void> clear(
    AppDatabase db,
    RecordScope tx,
    String parentType,
    int parentId,
  ) async {
    final ids = await idsOfParent(db, parentType, parentId);
    await (db.delete(db.reminders)..where(
          (t) =>
              t.parentType.equals(parentType) & t.parentId.equals(parentId),
        ))
        .go();
    if (ids.isEmpty) return;
    tx.removed(_recordType(parentType), parentId, reminderIds: ids);
  }

  // 参考时间变了：只登记位移，行不动。重排器按 Δ = 现行参考 − previousReference
  // 搬移每条行内时刻并物化回写——自己先删旧建新会被重排器再叠一次位移（双倍），
  // 而且新行在同一批里注定被 removed 覆盖（拿不到调度）。落进过去的行留在库里
  // 当惰性数据（与清空参考时间同一条口径）。
  static Future<void> referenceChanged(
    AppDatabase db,
    RecordScope tx, {
    required String parentType,
    required int parentId,
    required DateTime previousReference,
  }) async {
    tx.applied(
      _recordType(parentType),
      parentId,
      previousReference: previousReference,
    );
  }

  static Future<List<int>> idsOfParent(
    AppDatabase db,
    String parentType,
    int parentId,
  ) async {
    final rows = await _rowsOfParent(db, parentType, parentId);
    return <int>[for (final row in rows) row.id];
  }

  static Future<Map<int, List<int>>> idsByParent(
    AppDatabase db,
    String parentType,
    List<int> parentIds,
  ) async {
    if (parentIds.isEmpty) return <int, List<int>>{};
    final rows =
        await (db.select(db.reminders)..where(
              (t) =>
                  t.parentType.equals(parentType) & t.parentId.isIn(parentIds),
            ))
            .get();
    final grouped = <int, List<int>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.parentId, () => <int>[]).add(row.id);
    }
    return grouped;
  }

  static Future<List<Reminder>> _rowsOfParent(
    AppDatabase db,
    String parentType,
    int parentId,
  ) {
    return (db.select(db.reminders)..where(
          (t) =>
              t.parentType.equals(parentType) & t.parentId.equals(parentId),
        ))
        .get();
  }

  static Future<DateTime?> _referenceOf(
    AppDatabase db,
    String parentType,
    int parentId,
  ) async {
    if (parentType == 'event') {
      final row = await (db.select(
        db.events,
      )..where((t) => t.id.equals(parentId))).getSingleOrNull();
      return row?.startDt;
    }
    final row = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(parentId))).getSingleOrNull();
    return row?.dueDate;
  }

  static RecordType _recordType(String parentType) =>
      parentType == 'event' ? RecordType.event : RecordType.todo;
}
