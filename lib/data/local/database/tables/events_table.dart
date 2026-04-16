import 'package:drift/drift.dart';

import 'calendars_table.dart';

@DataClassName('Event')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get calendarId => integer().references(Calendars, #id)();
  TextColumn get uid => text()();
  TextColumn get summary => text()();
  DateTimeColumn get startDt => dateTime()();
  DateTimeColumn get endDt => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get etag => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
