import 'package:drift/drift.dart';

class TaskInstanceStates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().unique()();
  TextColumn get todoSyncId => text()();
  IntColumn get todoId => integer().nullable()();
  TextColumn get occurrenceId => text()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {todoSyncId, occurrenceId},
  ];
}
