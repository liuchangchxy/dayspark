// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v7 to v8 does not corrupt data', () async {
    // v7 rows carry the CalDAV columns (caldav_href/sync_token/etag/account_id,
    // uid/is_dirty) that the v8 migration must drop without touching the rest.
    final eventStart = DateTime.utc(2026, 5, 1, 10);
    final eventEnd = DateTime.utc(2026, 5, 1, 11);
    final rowTime = DateTime.utc(2026, 1, 1);
    final dueDate = DateTime.utc(2026, 6, 1);
    int secs(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

    final oldCalendarsData = <v7.CalendarsData>[
      const v7.CalendarsData(
        id: 1,
        accountId: 7,
        caldavHref: '/cal/work/',
        name: 'Work',
        color: '#FF0000',
        timezone: 'Asia/Shanghai',
        syncToken: 'sync-1',
        etag: 'etag-1',
        lastSyncedAt: null,
        isActive: true,
        sortOrder: 2,
      ),
    ];
    final expectedNewCalendarsData = <v8.CalendarsData>[
      const v8.CalendarsData(
        id: 1,
        name: 'Work',
        color: '#FF0000',
        timezone: 'Asia/Shanghai',
        lastSyncedAt: null,
        isActive: 1,
        sortOrder: 2,
      ),
    ];

    final oldEventsData = <v7.EventsData>[
      v7.EventsData(
        id: 1,
        calendarId: 1,
        uid: 'evt-1',
        summary: 'Meeting',
        startDt: eventStart,
        endDt: eventEnd,
        isAllDay: false,
        description: 'Discuss roadmap',
        etag: 'evt-etag',
        isDirty: true,
        createdAt: rowTime,
        updatedAt: rowTime,
      ),
    ];
    final expectedNewEventsData = <v8.EventsData>[
      v8.EventsData(
        id: 1,
        calendarId: 1,
        summary: 'Meeting',
        startDt: secs(eventStart),
        endDt: secs(eventEnd),
        isAllDay: 0,
        description: 'Discuss roadmap',
        createdAt: secs(rowTime),
        updatedAt: secs(rowTime),
      ),
    ];

    final oldTodosData = <v7.TodosData>[
      v7.TodosData(
        id: 1,
        calendarId: 1,
        uid: 'td-1',
        summary: 'Buy milk',
        dueDate: dueDate,
        priority: 3,
        status: 'NEEDS-ACTION',
        percentComplete: 0,
        etag: 'td-etag',
        isDirty: true,
        createdAt: rowTime,
        updatedAt: rowTime,
        sortOrder: 0,
      ),
    ];
    final expectedNewTodosData = <v8.TodosData>[
      v8.TodosData(
        id: 1,
        calendarId: 1,
        summary: 'Buy milk',
        dueDate: secs(dueDate),
        priority: 3,
        status: 'NEEDS-ACTION',
        percentComplete: 0,
        createdAt: secs(rowTime),
        updatedAt: secs(rowTime),
        sortOrder: 0,
      ),
    ];

    final oldTagsData = <v7.TagsData>[];
    final expectedNewTagsData = <v8.TagsData>[];

    final oldEventTagsData = <v7.EventTagsData>[];
    final expectedNewEventTagsData = <v8.EventTagsData>[];

    final oldTodoTagsData = <v7.TodoTagsData>[];
    final expectedNewTodoTagsData = <v8.TodoTagsData>[];

    final oldAttachmentsData = <v7.AttachmentsData>[];
    final expectedNewAttachmentsData = <v8.AttachmentsData>[];

    final oldRemindersData = <v7.RemindersData>[];
    final expectedNewRemindersData = <v8.RemindersData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 7,
      newVersion: 8,
      createOld: v7.DatabaseAtV7.new,
      createNew: v8.DatabaseAtV8.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.calendars, oldCalendarsData);
        batch.insertAll(oldDb.events, oldEventsData);
        batch.insertAll(oldDb.todos, oldTodosData);
        batch.insertAll(oldDb.tags, oldTagsData);
        batch.insertAll(oldDb.eventTags, oldEventTagsData);
        batch.insertAll(oldDb.todoTags, oldTodoTagsData);
        batch.insertAll(oldDb.attachments, oldAttachmentsData);
        batch.insertAll(oldDb.reminders, oldRemindersData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewCalendarsData,
          await newDb.select(newDb.calendars).get(),
        );
        expect(expectedNewEventsData, await newDb.select(newDb.events).get());
        expect(expectedNewTodosData, await newDb.select(newDb.todos).get());
        expect(expectedNewTagsData, await newDb.select(newDb.tags).get());
        expect(
          expectedNewEventTagsData,
          await newDb.select(newDb.eventTags).get(),
        );
        expect(
          expectedNewTodoTagsData,
          await newDb.select(newDb.todoTags).get(),
        );
        expect(
          expectedNewAttachmentsData,
          await newDb.select(newDb.attachments).get(),
        );
        expect(
          expectedNewRemindersData,
          await newDb.select(newDb.reminders).get(),
        );
      },
    );
  });
}
