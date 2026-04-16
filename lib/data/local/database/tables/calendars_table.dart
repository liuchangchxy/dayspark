import 'package:drift/drift.dart';

@DataClassName('Calendar')
class Calendars extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get caldavHref => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#2563EB'))();
  TextColumn get timezone => text().withDefault(const Constant('UTC'))();
  TextColumn get syncToken => text().nullable()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
