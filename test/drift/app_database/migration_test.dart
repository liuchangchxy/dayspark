// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;

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

  test(
    'real v9 to v11 migration preserves records, indexes and FK behavior',
    () async {
      final now = DateTime.utc(2026, 10, 4, 12).millisecondsSinceEpoch ~/ 1000;
      final trigger = now + 3600;
      await verifier.testWithDataIntegrity(
        oldVersion: 9,
        newVersion: 11,
        createOld: v9.DatabaseAtV9.new,
        createNew: v11.DatabaseAtV11.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(
            oldDb.calendars,
            v9.CalendarsCompanion.insert(
              name: 'Work',
              color: const Value('#123456'),
              timezone: const Value('Asia/Hong_Kong'),
              isActive: const Value(0),
              sortOrder: const Value(7),
            ),
          );
          batch.insert(
            oldDb.events,
            v9.EventsCompanion.insert(
              calendarId: 1,
              summary: 'v9 event',
              startDt: now,
              endDt: now + 3600,
              isAllDay: const Value(1),
              description: const Value('Event description'),
              location: const Value('Office'),
              rrule: const Value('FREQ=WEEKLY'),
              deletedAt: const Value(12345),
              createdAt: Value(now - 100),
              updatedAt: Value(now - 50),
              syncId: const Value('event-sync-id'),
              serverRev: const Value(8),
            ),
          );
          batch.insert(
            oldDb.todos,
            v9.TodosCompanion.insert(
              calendarId: 1,
              summary: 'v9 todo',
              dueDate: Value(now + 86400),
              startDate: Value(now - 3600),
              priority: const Value(3),
              status: const Value('NEEDS-ACTION'),
              description: const Value('Keep this field'),
              rrule: const Value('FREQ=MONTHLY'),
              completedAt: const Value(23456),
              percentComplete: const Value(25),
              createdAt: Value(now - 200),
              updatedAt: Value(now - 100),
              deletedAt: const Value(34567),
              sortOrder: const Value(12),
              parentId: const Value(9),
              syncId: const Value('todo-sync-id'),
              serverRev: const Value(9),
            ),
          );
          batch.insert(
            oldDb.tags,
            v9.TagsCompanion.insert(
              name: 'preserved',
              color: const Value('#654321'),
            ),
          );
          batch.insert(
            oldDb.eventTags,
            const v9.EventTagsCompanion(eventId: Value(1), tagId: Value(1)),
          );
          batch.insert(
            oldDb.todoTags,
            const v9.TodoTagsCompanion(todoId: Value(1), tagId: Value(1)),
          );
          batch.insert(
            oldDb.attachments,
            v9.AttachmentsCompanion.insert(
              parentType: 'todo',
              parentId: 1,
              filePath: '/data/keep.txt',
              fileName: 'keep.txt',
              fileSize: const Value(123),
              mimeType: const Value('text/plain'),
              createdAt: Value(now - 300),
            ),
          );
          batch.insert(
            oldDb.reminders,
            v9.RemindersCompanion.insert(
              parentType: 'todo',
              parentId: 1,
              triggerTime: trigger,
              isTriggered: const Value(1),
            ),
          );
        },
        validateItems: (newDb) async {
          expect(newDb.schemaVersion, 11);
          final calendars = await newDb.select(newDb.calendars).get();
          final events = await newDb.select(newDb.events).get();
          final todos = await newDb.select(newDb.todos).get();
          final reminders = await newDb.select(newDb.reminders).get();
          expect(
            calendars.single,
            const v11.CalendarsData(
              id: 1,
              name: 'Work',
              color: '#123456',
              timezone: 'Asia/Hong_Kong',
              isActive: 0,
              sortOrder: 7,
            ),
          );
          expect(
            events.single,
            v11.EventsData(
              id: 1,
              calendarId: 1,
              summary: 'v9 event',
              startDt: now,
              endDt: now + 3600,
              isAllDay: 1,
              description: 'Event description',
              location: 'Office',
              rrule: 'FREQ=WEEKLY',
              deletedAt: 12345,
              createdAt: now - 100,
              updatedAt: now - 50,
              syncId: 'event-sync-id',
              serverRev: 8,
            ),
          );
          expect(
            todos.single,
            v11.TodosData(
              id: 1,
              calendarId: 1,
              summary: 'v9 todo',
              dueDate: now + 86400,
              startDate: now - 3600,
              priority: 3,
              status: 'NEEDS-ACTION',
              description: 'Keep this field',
              rrule: 'FREQ=MONTHLY',
              completedAt: 23456,
              percentComplete: 25,
              createdAt: now - 200,
              updatedAt: now - 100,
              deletedAt: 34567,
              sortOrder: 12,
              parentId: 9,
              syncId: 'todo-sync-id',
              serverRev: 9,
            ),
          );
          expect(
            reminders.single,
            v11.RemindersData(
              id: 1,
              parentType: 'todo',
              parentId: 1,
              triggerTime: trigger,
              isTriggered: 1,
            ),
          );
          expect(
            (await newDb.select(newDb.tags).get()).single,
            const v11.TagsData(id: 1, name: 'preserved', color: '#654321'),
          );
          expect(await newDb.select(newDb.eventTags).get(), hasLength(1));
          expect(await newDb.select(newDb.todoTags).get(), hasLength(1));
          expect(await newDb.select(newDb.attachments).get(), [
            v11.AttachmentsData(
              id: 1,
              parentType: 'todo',
              parentId: 1,
              filePath: '/data/keep.txt',
              fileName: 'keep.txt',
              fileSize: 123,
              mimeType: 'text/plain',
              createdAt: now - 300,
            ),
          ]);
          expect(await newDb.select(newDb.taskAllocations).get(), isEmpty);
          final indexes = await newDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'task_allocations_%'",
              )
              .get();
          expect(indexes.map((row) => row.read<String>('name')).toSet(), {
            'task_allocations_todo_id',
            'task_allocations_todo_sync_id',
            'task_allocations_sync_id',
            'task_allocations_time_range',
          });
          final todoId = todos.single.id;
          await newDb.customStatement('PRAGMA foreign_keys = ON');
          final foreignKeys = await newDb
              .customSelect('PRAGMA foreign_key_list(task_allocations)')
              .get();
          expect(foreignKeys, hasLength(1));
          expect(foreignKeys.single.read<String>('table'), 'todos');
          expect(foreignKeys.single.read<String>('on_delete'), 'CASCADE');
          await (newDb.delete(
            newDb.todoTags,
          )..where((row) => row.todoId.equals(todoId))).go();
          final allocationId = await newDb
              .into(newDb.taskAllocations)
              .insert(
                v11.TaskAllocationsCompanion.insert(
                  todoId: Value(todoId),
                  startAt: DateTime.utc(2026, 10, 5, 9).millisecondsSinceEpoch,
                  endAt: DateTime.utc(2026, 10, 5, 10).millisecondsSinceEpoch,
                ),
              );
          await (newDb.delete(
            newDb.todos,
          )..where((row) => row.id.equals(todoId))).go();
          expect(
            await (newDb.select(
              newDb.taskAllocations,
            )..where((row) => row.id.equals(allocationId))).get(),
            isEmpty,
          );
        },
      );
    },
  );

  test(
    'v10 to v11 preserves allocations and permits unresolved parents',
    () async {
      final now = DateTime.utc(2026, 10, 4, 12).millisecondsSinceEpoch ~/ 1000;
      await verifier.testWithDataIntegrity(
        oldVersion: 10,
        newVersion: 11,
        createOld: v10.DatabaseAtV10.new,
        createNew: v11.DatabaseAtV11.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(
            oldDb.calendars,
            v10.CalendarsCompanion.insert(name: 'Personal'),
          );
          batch.insert(
            oldDb.todos,
            v10.TodosCompanion.insert(calendarId: 1, summary: 'Preserved Todo'),
          );
          batch.insert(
            oldDb.taskAllocations,
            v10.TaskAllocationsCompanion.insert(
              todoId: 1,
              startAt: now + 3600,
              endAt: now + 7200,
              state: const Value('cancelledByUser'),
              createdAt: Value(now - 20),
              updatedAt: Value(now - 10),
            ),
          );
        },
        validateItems: (newDb) async {
          expect(newDb.schemaVersion, 11);
          final migrated = await newDb.select(newDb.taskAllocations).get();
          expect(migrated, hasLength(1));
          expect(migrated.single.todoId, 1);
          expect(migrated.single.todoSyncId, equals(null));
          expect(migrated.single.syncId, equals(null));
          expect(migrated.single.state, 'cancelledByUser');
          final unresolvedId = await newDb
              .into(newDb.taskAllocations)
              .insert(
                v11.TaskAllocationsCompanion.insert(
                  todoId: const Value(null),
                  todoSyncId: const Value('todo-from-another-device'),
                  startAt: DateTime.utc(2026, 10, 5, 9).millisecondsSinceEpoch,
                  endAt: DateTime.utc(2026, 10, 5, 10).millisecondsSinceEpoch,
                ),
              );
          final unresolved = await (newDb.select(
            newDb.taskAllocations,
          )..where((row) => row.id.equals(unresolvedId))).getSingle();
          expect(unresolved.todoId, equals(null));
          expect(unresolved.todoSyncId, 'todo-from-another-device');
        },
      );
    },
  );
}
