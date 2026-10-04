import 'package:drift/drift.dart';

import 'todos_table.dart';

/// TaskAllocation intervals are UTC instants stored at millisecond precision.
class TaskAllocationInstantConverter extends TypeConverter<DateTime, int> {
  const TaskAllocationInstantConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

@DataClassName('TaskAllocation')
@TableIndex(name: 'task_allocations_todo_id', columns: {#todoId})
@TableIndex(name: 'task_allocations_todo_sync_id', columns: {#todoSyncId})
@TableIndex(name: 'task_allocations_sync_id', columns: {#syncId})
@TableIndex(name: 'task_allocations_time_range', columns: {#startAt, #endAt})
class TaskAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get todoId => integer().nullable().references(
    Todos,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get todoSyncId => text().nullable()();
  TextColumn get occurrenceId => text().nullable()();
  IntColumn get startAt =>
      integer().map(const TaskAllocationInstantConverter())();
  IntColumn get endAt =>
      integer().map(const TaskAllocationInstantConverter())();
  TextColumn get state => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncId => text().nullable()();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();
}
