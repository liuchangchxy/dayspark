import 'package:drift/drift.dart';

import 'calendars_table.dart';

@DataClassName('Event')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get summary => text()();
  DateTimeColumn get startDt => dateTime()();
  DateTimeColumn get endDt => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get rrule => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncId => text().nullable()();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();
}
