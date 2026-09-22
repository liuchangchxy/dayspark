// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema. AppDatabase always migrates
    // fully to its current schemaVersion, so each known starting version is
    // only validated against the latest schema — intermediate targets would
    // demand step-wise migrations the app does not implement.
    const versions = GeneratedHelper.versions;
    final latest = versions.last;
    for (final fromVersion in versions.take(versions.length - 1)) {
      group('from $fromVersion', () {
        test('to $latest', () async {
          final schema = await verifier.schemaAt(fromVersion);
          final db = AppDatabase(schema.newConnection());
          await verifier.migrateAndValidate(db, latest);
          await db.close();
        });
      });
    }
  });

  test('migration from v8 to v9 does not corrupt data', () async {
    // v9 adds events/todos sync_id + server_rev (NULL/0 for rows that were
    // never enqueued) and the sync_outbox table; everything else must come
    // through untouched.
    final eventStart = DateTime.utc(2026, 5, 1, 10);
    final eventEnd = DateTime.utc(2026, 5, 1, 11);
    final rowTime = DateTime.utc(2026, 1, 1);
    final dueDate = DateTime.utc(2026, 6, 1);
    int secs(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

    final oldCalendarsData = <v8.CalendarsData>[
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
    final expectedNewCalendarsData = <v9.CalendarsData>[
      const v9.CalendarsData(
        id: 1,
        name: 'Work',
        color: '#FF0000',
        timezone: 'Asia/Shanghai',
        lastSyncedAt: null,
        isActive: 1,
        sortOrder: 2,
      ),
    ];

    final oldEventsData = <v8.EventsData>[
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
    final expectedNewEventsData = <v9.EventsData>[
      v9.EventsData(
        id: 1,
        calendarId: 1,
        summary: 'Meeting',
        startDt: secs(eventStart),
        endDt: secs(eventEnd),
        isAllDay: 0,
        description: 'Discuss roadmap',
        createdAt: secs(rowTime),
        updatedAt: secs(rowTime),
        syncId: null,
        serverRev: 0,
      ),
    ];

    final oldTodosData = <v8.TodosData>[
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
    final expectedNewTodosData = <v9.TodosData>[
      v9.TodosData(
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
        syncId: null,
        serverRev: 0,
      ),
    ];

    final oldTagsData = <v8.TagsData>[];
    final expectedNewTagsData = <v9.TagsData>[];

    final oldEventTagsData = <v8.EventTagsData>[];
    final expectedNewEventTagsData = <v9.EventTagsData>[];

    final oldTodoTagsData = <v8.TodoTagsData>[];
    final expectedNewTodoTagsData = <v9.TodoTagsData>[];

    final oldAttachmentsData = <v8.AttachmentsData>[];
    final expectedNewAttachmentsData = <v9.AttachmentsData>[];

    final oldRemindersData = <v8.RemindersData>[];
    final expectedNewRemindersData = <v9.RemindersData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 8,
      newVersion: 9,
      createOld: v8.DatabaseAtV8.new,
      createNew: v9.DatabaseAtV9.new,
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
        expect(await newDb.select(newDb.syncOutbox).get(), isEmpty);
      },
    );
  });
}
