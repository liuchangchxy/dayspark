// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_dao.dart';

// ignore_for_file: type=lint
mixin _$EventsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarsTable get calendars => attachedDatabase.calendars;
  $EventsTable get events => attachedDatabase.events;
  EventsDaoManager get managers => EventsDaoManager(this);
}

class EventsDaoManager {
  final _$EventsDaoMixin _db;
  EventsDaoManager(this._db);
  $$CalendarsTableTableManager get calendars =>
      $$CalendarsTableTableManager(_db.attachedDatabase, _db.calendars);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
}
