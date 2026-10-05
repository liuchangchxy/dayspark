import 'package:drift/drift.dart';

import 'calendars_table.dart';

@DataClassName('Todo')
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get summary => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('NEEDS-ACTION'))();
  TextColumn get description => text().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get recurrenceAnchorSource => text().nullable()();
  TextColumn get recurrenceValueType => text().nullable()();
  TextColumn get recurrenceAnchorValue => text().nullable()();
  TextColumn get recurrenceTimeZone => text().nullable()();
  TextColumn get recurrenceRule => text().nullable()();
  TextColumn get recurrenceLegacyState => text().nullable()();
  TextColumn get recurrenceEvidence => text().nullable()();
  IntColumn get recurrenceRevision =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get percentComplete => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get parentId => integer().nullable()();
  TextColumn get syncId => text().nullable()();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();
}
