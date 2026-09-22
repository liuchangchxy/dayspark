// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todos_dao.dart';

// ignore_for_file: type=lint
mixin _$TodosDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarsTable get calendars => attachedDatabase.calendars;
  $TodosTable get todos => attachedDatabase.todos;
  $TagsTable get tags => attachedDatabase.tags;
  $TodoTagsTable get todoTags => attachedDatabase.todoTags;
  $AttachmentsTable get attachments => attachedDatabase.attachments;
  $RemindersTable get reminders => attachedDatabase.reminders;
  TodosDaoManager get managers => TodosDaoManager(this);
}

class TodosDaoManager {
  final _$TodosDaoMixin _db;
  TodosDaoManager(this._db);
  $$CalendarsTableTableManager get calendars =>
      $$CalendarsTableTableManager(_db.attachedDatabase, _db.calendars);
  $$TodosTableTableManager get todos =>
      $$TodosTableTableManager(_db.attachedDatabase, _db.todos);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$TodoTagsTableTableManager get todoTags =>
      $$TodoTagsTableTableManager(_db.attachedDatabase, _db.todoTags);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db.attachedDatabase, _db.attachments);
  $$RemindersTableTableManager get reminders =>
      $$RemindersTableTableManager(_db.attachedDatabase, _db.reminders);
}
