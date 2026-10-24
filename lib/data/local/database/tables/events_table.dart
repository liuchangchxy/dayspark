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

  /// Excluded occurrence anchors, one ISO-8601 instant per line.
  ///
  /// Deleting a single occurrence of a series has to leave the series intact,
  /// and RFC 5545's answer for that is EXDATE. Kept on the event row rather
  /// than in a side table so the exception travels with the record through
  /// sync, backup and iCal export without a second entity to reconcile.
  TextColumn get exdates => text().nullable()();

  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncId => text().nullable()();
  TextColumn get icsUid => text().nullable()();
  IntColumn get serverRev => integer().withDefault(const Constant(0))();
}
