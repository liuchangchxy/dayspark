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
@TableIndex(name: 'task_allocations_time_range', columns: {#startAt, #endAt})
class TaskAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get todoId =>
      integer().references(Todos, #id, onDelete: KeyAction.cascade)();
  IntColumn get startAt =>
      integer().map(const TaskAllocationInstantConverter())();
  IntColumn get endAt =>
      integer().map(const TaskAllocationInstantConverter())();
  TextColumn get state => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
