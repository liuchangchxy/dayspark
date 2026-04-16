import 'package:drift/drift.dart';

@DataClassName('Reminder')
class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get parentType => text()();
  IntColumn get parentId => integer()();
  DateTimeColumn get triggerTime => dateTime()();
  BoolColumn get isTriggered => boolean().withDefault(const Constant(false))();
}
