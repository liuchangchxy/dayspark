import 'package:drift/drift.dart';

import 'calendars_table.dart';

@DataClassName('Todo')
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get uid => text()();
  TextColumn get summary => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('NEEDS-ACTION'))();
  TextColumn get description => text().nullable()();
  TextColumn get rrule => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get percentComplete => integer().withDefault(const Constant(0))();
  TextColumn get etag => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
