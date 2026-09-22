// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_dao.dart';

// ignore_for_file: type=lint
mixin _$EventsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarsTable get calendars => attachedDatabase.calendars;
  $EventsTable get events => attachedDatabase.events;
  $TagsTable get tags => attachedDatabase.tags;
  $EventTagsTable get eventTags => attachedDatabase.eventTags;
  $RemindersTable get reminders => attachedDatabase.reminders;
  $AttachmentsTable get attachments => attachedDatabase.attachments;
  EventsDaoManager get managers => EventsDaoManager(this);
}

class EventsDaoManager {
  final _$EventsDaoMixin _db;
  EventsDaoManager(this._db);
  $$CalendarsTableTableManager get calendars =>
      $$CalendarsTableTableManager(_db.attachedDatabase, _db.calendars);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$EventTagsTableTableManager get eventTags =>
      $$EventTagsTableTableManager(_db.attachedDatabase, _db.eventTags);
  $$RemindersTableTableManager get reminders =>
      $$RemindersTableTableManager(_db.attachedDatabase, _db.reminders);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db.attachedDatabase, _db.attachments);
}
