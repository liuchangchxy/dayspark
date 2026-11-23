import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/services/attachment_files.dart';
import 'package:dayspark/domain/services/backup_service.dart';

void main() {
  late AppDatabase db;
  late BackupService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BackupService(db);
  });

  tearDown(() => db.close());

  test('BackupService exports and restores all private DaySpark data roundtrip', () async {
    // 1. Seed full database state across all tables
    final calId = await db.into(db.calendars).insert(
      CalendarsCompanion.insert(
        name: 'Personal',
        syncId: const Value('cal-sync-1'),
      ),
    );

    final eventId = await db.into(db.events).insert(
      EventsCompanion.insert(
        calendarId: calId,
        summary: 'Dentist appointment',
        startDt: DateTime.utc(2026, 11, 10, 9),
        endDt: DateTime.utc(2026, 11, 10, 10),
        location: const Value('Dental Clinic'),
        syncId: const Value('event-sync-1'),
        icsUid: const Value('uid-event-123'),
      ),
    );

    final todoId = await db.into(db.todos).insert(
      TodosCompanion.insert(
        calendarId: calId,
        summary: 'Buy groceries',
        dueDate: Value(DateTime.utc(2026, 11, 10, 18)),
        startDate: Value(DateTime.utc(2026, 11, 10, 12)),
        syncId: const Value('todo-sync-1'),
        icsUid: const Value('uid-todo-456'),
      ),
    );

    final tagId = await db.into(db.tags).insert(
      TagsCompanion.insert(
        name: 'Health',
        color: const Value('#10B981'),
        syncId: const Value('tag-sync-1'),
      ),
    );

    await db.into(db.eventTags).insert(
      EventTagsCompanion.insert(
        eventId: eventId,
        tagId: tagId,
        syncId: const Value('tagassoc-event-1'),
      ),
    );

    await db.into(db.todoTags).insert(
      TodoTagsCompanion.insert(
        todoId: todoId,
        tagId: tagId,
        syncId: const Value('tagassoc-todo-1'),
      ),
    );

    final reminderId = await db.into(db.reminders).insert(
      RemindersCompanion.insert(
        parentType: 'event',
        parentId: eventId,
        triggerTime: DateTime.utc(2026, 11, 10, 8, 30),
        syncId: const Value('rem-sync-1'),
        parentSyncId: const Value('event-sync-1'),
      ),
    );

    final attachmentId = await db.into(db.attachments).insert(
      AttachmentsCompanion.insert(
        parentType: 'event',
        parentId: eventId,
        filePath: '/storage/x-ray.pdf',
        fileName: 'x-ray.pdf',
        fileSize: const Value(1024),
        mimeType: const Value('application/pdf'),
        syncId: const Value('att-sync-1'),
        parentSyncId: const Value('event-sync-1'),
        serverFileRef: const Value('server-ref-789'),
      ),
    );

    // 2. Export full backup JSON
    final jsonString = await service.exportJson();
    expect(jsonString, contains('Dentist appointment'));
    expect(jsonString, contains('Buy groceries'));
    expect(jsonString, contains('Health'));
    expect(jsonString, contains('x-ray.pdf'));
    expect(jsonString, contains('server-ref-789'));

    // 3. Clear database completely
    await db.delete(db.attachments).go();
    await db.delete(db.reminders).go();
    await db.delete(db.eventTags).go();
    await db.delete(db.todoTags).go();
    await db.delete(db.tags).go();
    await db.delete(db.events).go();
    await db.delete(db.todos).go();
    await db.delete(db.calendars).go();

    expect(await db.select(db.events).get(), isEmpty);
    expect(await db.select(db.todos).get(), isEmpty);
    expect(await db.select(db.reminders).get(), isEmpty);
    expect(await db.select(db.tags).get(), isEmpty);
    expect(await db.select(db.attachments).get(), isEmpty);

    // 4. Restore from JSON
    await service.restoreFromJson(jsonString);

    // 5. Verify restored rows and relationships
    final restoredEvents = await db.select(db.events).get();
    expect(restoredEvents, hasLength(1));
    expect(restoredEvents.first.id, eventId);
    expect(restoredEvents.first.summary, 'Dentist appointment');
    expect(restoredEvents.first.location, 'Dental Clinic');
    expect(restoredEvents.first.syncId, 'event-sync-1');
    expect(restoredEvents.first.icsUid, 'uid-event-123');

    final restoredTodos = await db.select(db.todos).get();
    expect(restoredTodos, hasLength(1));
    expect(restoredTodos.first.id, todoId);
    expect(restoredTodos.first.summary, 'Buy groceries');
    expect(restoredTodos.first.syncId, 'todo-sync-1');
    expect(restoredTodos.first.icsUid, 'uid-todo-456');

    final restoredReminders = await db.select(db.reminders).get();
    expect(restoredReminders, hasLength(1));
    expect(restoredReminders.first.id, reminderId);
    expect(restoredReminders.first.triggerTime.toUtc(), DateTime.utc(2026, 11, 10, 8, 30));
    expect(restoredReminders.first.parentSyncId, 'event-sync-1');

    final restoredTags = await db.select(db.tags).get();
    expect(restoredTags, hasLength(1));
    expect(restoredTags.first.id, tagId);
    expect(restoredTags.first.name, 'Health');

    final restoredEventTags = await db.select(db.eventTags).get();
    expect(restoredEventTags, hasLength(1));
    expect(restoredEventTags.first.eventId, eventId);
    expect(restoredEventTags.first.tagId, tagId);

    final restoredAttachments = await db.select(db.attachments).get();
    expect(restoredAttachments, hasLength(1));
    expect(restoredAttachments.first.id, attachmentId);
    expect(restoredAttachments.first.fileName, 'x-ray.pdf');
    expect(restoredAttachments.first.serverFileRef, 'server-ref-789');
    // The recorded path points at a file this device does not have, so it
    // is cleared rather than restored as a dangling path.
    expect(restoredAttachments.first.filePath, isEmpty);
  });

  test('an excluded occurrence survives a backup round trip', () async {
    // "Delete just this one" on a recurring event is stored as an EXDATE on
    // the series row. A backup that drops the column resurrects the
    // occurrence the user deleted, which is silent data loss.
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    final eventId = await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            calendarId: calId,
            summary: 'Daily standup',
            startDt: DateTime.utc(2026, 10, 1, 9),
            endDt: DateTime.utc(2026, 10, 1, 9, 30),
            rrule: const Value('FREQ=DAILY;COUNT=5'),
            exdates: const Value(
              '2026-10-03T09:00:00.000Z\n2026-10-04T09:00:00.000Z',
            ),
          ),
        );

    final json = await service.exportJson();
    expect(
      json,
      contains('exdates'),
      reason: 'the export has to carry the field at all',
    );

    await db.delete(db.events).go();
    await service.restoreFromJson(json);

    final restored = await (db.select(
      db.events,
    )..where((t) => t.id.equals(eventId))).getSingle();
    expect(
      restored.exdates,
      '2026-10-03T09:00:00.000Z\n2026-10-04T09:00:00.000Z',
      reason: 'the excluded dates are part of the series, not decoration',
    );
    expect(restored.rrule, 'FREQ=DAILY;COUNT=5');
  });

  test('a repeating todo survives a backup round trip as itself', () async {
    // The recurrence lives in nine columns, not one: the RRULE, the anchor it
    // counts from, and the state that says whether it has been reconciled.
    // Sync carries the whole set; a backup that carries only `rrule` restores
    // a todo the recurrence engine can no longer expand — it reads as a
    // one-off the user never asked for.
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    final todoId = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Weekly report',
            dueDate: Value(DateTime.utc(2026, 10, 5)),
            rrule: const Value('FREQ=WEEKLY;BYDAY=MO'),
            recurrenceAnchorSource: const Value('due'),
            recurrenceValueType: const Value('date'),
            recurrenceAnchorValue: const Value('2026-10-05'),
            recurrenceTimeZone: const Value('UTC'),
            recurrenceRule: const Value('FREQ=WEEKLY;BYDAY=MO'),
            recurrenceLegacyState: const Value('knownZoned'),
            recurrenceRevision: const Value(3),
            percentComplete: const Value(40),
            sortOrder: const Value(7),
          ),
        );

    final json = await service.exportJson();
    expect(json, contains('recurrenceRule'));

    await db.delete(db.todos).go();
    await service.restoreFromJson(json);

    final restored = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(restored.rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(restored.recurrenceAnchorSource, 'due');
    expect(restored.recurrenceValueType, 'date');
    expect(restored.recurrenceAnchorValue, '2026-10-05');
    expect(restored.recurrenceTimeZone, 'UTC');
    expect(restored.recurrenceRule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(restored.recurrenceLegacyState, 'knownZoned');
    expect(restored.recurrenceRevision, 3);
    expect(restored.percentComplete, 40);
    expect(restored.sortOrder, 7);
  });

  test('a todo from before the recurrence columns restores as a one-off', () async {
    // Old packages have no recurrence keys. Restoring one must leave a plain
    // todo rather than throw on a missing field.
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    final json =
        '{"version":1,"exportedAt":"2026-01-01T00:00:00.000Z",'
        '"calendars":[{"id":$calId,"name":"Personal","color":"#2563EB",'
        '"timezone":"UTC","isActive":true,"sortOrder":0,"syncId":null}],'
        '"todos":[{"id":1,"calendarId":$calId,"summary":"Old task",'
        '"description":null,"dueDate":null,"startDate":null,"status":null,'
        '"completedAt":null,"priority":0,"parentId":null,"deletedAt":null,'
        '"syncId":null,"icsUid":null}]}';

    await service.restoreFromJson(json);

    final restored = await db.select(db.todos).getSingle();
    expect(restored.summary, 'Old task');
    expect(restored.rrule, isNull);
    expect(restored.recurrenceRule, isNull);
    expect(restored.percentComplete, 0);
  });

  test('a backup from before the column restores with it unset', () async {
    // Old packages have no `exdates` key. Restoring one must leave the series
    // with no exclusions rather than throw on a missing field.
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    final json =
        '{"version":1,"exportedAt":"2026-01-01T00:00:00.000Z",'
        '"calendars":[{"id":$calId,"name":"Personal","color":"#2563EB",'
        '"timezone":"UTC","isActive":true,"sortOrder":0,"syncId":null}],'
        '"events":[{"id":1,"calendarId":$calId,"summary":"Old series",'
        '"description":null,"startDt":"2026-10-01T09:00:00.000Z",'
        '"endDt":"2026-10-01T09:30:00.000Z","isAllDay":false,"location":null,'
        '"rrule":"FREQ=DAILY;COUNT=5","deletedAt":null,"syncId":null,'
        '"icsUid":null}]}';

    await service.restoreFromJson(json);

    final restored = await db.select(db.events).getSingle();
    expect(restored.summary, 'Old series');
    expect(restored.exdates, isNull);
  });

  group('zip package', () {
    late Directory sourceDir;
    late Directory restoreDir;
    late BackupService zipper;
    late BackupService restorer;

    setUp(() {
      sourceDir = Directory.systemTemp.createTempSync('dayspark_backup_src');
      restoreDir = Directory.systemTemp.createTempSync('dayspark_backup_dst');
      zipper = BackupService(
        db,
        files: AttachmentFileStore(root: () async => sourceDir),
      );
      restorer = BackupService(
        db,
        files: AttachmentFileStore(root: () async => restoreDir),
      );
    });

    tearDown(() {
      for (final dir in [sourceDir, restoreDir]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    Future<(int, Uint8List)> seedAttachment() async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Personal'),
      );
      final todoId = await db.into(db.todos).insert(
        TodosCompanion.insert(calendarId: calId, summary: 'Scan receipt'),
      );
      final attId = await db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          parentType: 'todo',
          parentId: todoId,
          filePath: '',
          fileName: 'receipt.pdf',
          syncId: const Value('att-sync-zip'),
        ),
      );
      // Non-UTF8 bytes on purpose: a text-shaped body would survive an
      // accidental String round trip and hide a broken package.
      final bytes = Uint8List.fromList(
        List<int>.generate(2048, (i) => (i * 7) % 256),
      );
      final path = await AttachmentFileStore(
        root: () async => sourceDir,
      ).write(
        key: attachmentFileKey(attId),
        fileName: 'receipt.pdf',
        bytes: bytes,
      );
      await (db.update(
        db.attachments,
      )..where((t) => t.id.equals(attId))).write(
        AttachmentsCompanion(
          filePath: Value(path),
          fileSize: Value(bytes.length),
        ),
      );
      return (attId, bytes);
    }

    test('carries attachment bodies and restores them to disk', () async {
      final (attId, bytes) = await seedAttachment();

      final zip = await zipper.exportZip();

      // Wipe everything, including the original file.
      await db.delete(db.attachments).go();
      await db.delete(db.todos).go();
      await db.delete(db.calendars).go();
      sourceDir.deleteSync(recursive: true);

      await restorer.restoreZip(zip);

      final restored = await db.select(db.attachments).getSingle();
      expect(restored.id, attId);
      expect(restored.fileName, 'receipt.pdf');
      expect(restored.fileSize, bytes.length);
      expect(restored.filePath, startsWith(restoreDir.path));
      expect(File(restored.filePath).existsSync(), isTrue);
      expect(await File(restored.filePath).readAsBytes(), bytes);
      expect(
        (await db.select(db.todos).getSingle()).summary,
        'Scan receipt',
      );
    });

    test('a row whose file is already gone exports without bytes', () async {
      final (attId, _) = await seedAttachment();
      File(
        (await (db.select(
          db.attachments,
        )..where((t) => t.id.equals(attId))).getSingle()).filePath,
      ).deleteSync();

      final zip = await zipper.exportZip();
      await db.delete(db.attachments).go();
      await restorer.restoreZip(zip);

      final restored = await db.select(db.attachments).getSingle();
      expect(restored.fileName, 'receipt.pdf');
      // Fileless, not dangling: the row reads as "fetch from the server"
      // instead of pointing at a path that does not exist.
      expect(restored.filePath, isEmpty);
    });

    test('a package without db.json is rejected', () async {
      await expectLater(
        restorer.restoreZip(const <int>[0, 1, 2, 3]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('P0 Safety Requirements (Items 19-23)', () {
    test('Item 19 & Point 1: keepRemote imports collided rows as new rows; keepLocal skips', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Personal'),
      );
      final localEventId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: 'Local Event 1',
          startDt: DateTime.utc(2026, 11, 15, 9),
          endDt: DateTime.utc(2026, 11, 15, 10),
        ),
      );
      final localTodoId = await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Local Todo 1',
        ),
      );

      final json = '''
{
  "version": 1,
  "exportedAt": "2026-11-23T00:00:00.000Z",
  "calendars": [{"id": $calId, "name": "Personal", "color": "#2563EB", "timezone": "UTC", "isActive": true, "sortOrder": 0, "syncId": null}],
  "events": [{
    "id": $localEventId,
    "calendarId": $calId,
    "summary": "Remote Event 1",
    "description": null,
    "startDt": "2026-11-20T09:00:00.000Z",
    "endDt": "2026-11-20T10:00:00.000Z",
    "isAllDay": false,
    "location": null,
    "rrule": null,
    "exdates": null,
    "deletedAt": null,
    "syncId": "remote-event-sync-1",
    "icsUid": "remote-event-uid-1"
  }],
  "todos": [{
    "id": $localTodoId,
    "calendarId": $calId,
    "summary": "Remote Todo 1",
    "description": null,
    "dueDate": null,
    "startDate": null,
    "status": "NEEDS-ACTION",
    "completedAt": null,
    "priority": 0,
    "parentId": null,
    "deletedAt": null,
    "syncId": "remote-todo-sync-1",
    "icsUid": "remote-todo-uid-1"
  }]
}
''';

      // Path A: keepRemote must not overwrite the unrelated local row. The
      // remote event/todo shares only the integer id, so it is imported as a
      // separate row with its own sync identity.
      await service.restoreFromJson(
        json,
        resolutions: {
          'events:$localEventId': BackupConflictResolution.keepRemote,
          'todos:$localTodoId': BackupConflictResolution.keepRemote,
        },
      );

      final eventsAfterRemote = await db.select(db.events).get();
      expect(eventsAfterRemote, hasLength(2), reason: 'keepRemote imports the remote as a new row, keeping the local row');
      final keptLocalEvent = eventsAfterRemote.firstWhere((e) => e.id == localEventId);
      expect(keptLocalEvent.summary, 'Local Event 1');
      final importedEvent = eventsAfterRemote.firstWhere((e) => e.id != localEventId);
      expect(importedEvent.summary, 'Remote Event 1');
      expect(importedEvent.syncId, 'remote-event-sync-1');

      final todosAfterRemote = await db.select(db.todos).get();
      expect(todosAfterRemote, hasLength(2), reason: 'keepRemote imports the remote as a new row, keeping the local row');
      final keptLocalTodo = todosAfterRemote.firstWhere((t) => t.id == localTodoId);
      expect(keptLocalTodo.summary, 'Local Todo 1');
      final importedTodo = todosAfterRemote.firstWhere((t) => t.id != localTodoId);
      expect(importedTodo.summary, 'Remote Todo 1');
      expect(importedTodo.syncId, 'remote-todo-sync-1');

      // Path B: keepLocal skips remote and preserves local row intact
      final json2 = '''
{
  "version": 1,
  "exportedAt": "2026-11-23T00:00:00.000Z",
  "calendars": [{"id": $calId, "name": "Personal", "color": "#2563EB", "timezone": "UTC", "isActive": true, "sortOrder": 0, "syncId": null}],
  "events": [{
    "id": $localEventId,
    "calendarId": $calId,
    "summary": "Another Remote Event",
    "description": null,
    "startDt": "2026-11-20T09:00:00.000Z",
    "endDt": "2026-11-20T10:00:00.000Z",
    "isAllDay": false,
    "location": null,
    "rrule": null,
    "exdates": null,
    "deletedAt": null,
    "syncId": "another-sync",
    "icsUid": "another-uid"
  }],
  "todos": [{
    "id": $localTodoId,
    "calendarId": $calId,
    "summary": "Another Remote Todo",
    "description": null,
    "dueDate": null,
    "startDate": null,
    "status": "NEEDS-ACTION",
    "completedAt": null,
    "priority": 0,
    "parentId": null,
    "deletedAt": null,
    "syncId": "another-todo-sync",
    "icsUid": "another-todo-uid"
  }]
}
''';

      await service.restoreFromJson(
        json2,
        resolutions: {
          'events:$localEventId': BackupConflictResolution.keepLocal,
          'todos:$localTodoId': BackupConflictResolution.keepLocal,
        },
      );

      final eventsAfterLocal = await db.select(db.events).get();
      expect(eventsAfterLocal, hasLength(2));
      expect(
        eventsAfterLocal.firstWhere((e) => e.id == localEventId).summary,
        'Local Event 1',
        reason: 'keepLocal keeps existing and skips remote',
      );
      expect(
        eventsAfterLocal.where((e) => e.summary == 'Another Remote Event'),
        isEmpty,
        reason: 'keepLocal skips the remote event',
      );

      final todosAfterLocal = await db.select(db.todos).get();
      expect(todosAfterLocal, hasLength(2));
      expect(
        todosAfterLocal.firstWhere((t) => t.id == localTodoId).summary,
        'Local Todo 1',
        reason: 'keepLocal keeps existing and skips remote',
      );
      expect(
        todosAfterLocal.where((t) => t.summary == 'Another Remote Todo'),
        isEmpty,
        reason: 'keepLocal skips the remote todo',
      );
    });

    test('Item 23: child todo appearing before parent todo in backup array restores parentId correctly', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Personal'),
      );

      // Child (id=2, parentId=1) comes BEFORE Parent (id=1, parentId=null)
      final json = '''
{
  "version": 1,
  "exportedAt": "2026-11-23T00:00:00.000Z",
  "calendars": [{"id": $calId, "name": "Personal", "color": "#2563EB", "timezone": "UTC", "isActive": true, "sortOrder": 0, "syncId": null}],
  "todos": [
    {
      "id": 2,
      "calendarId": $calId,
      "summary": "Child Todo",
      "description": null,
      "dueDate": null,
      "startDate": null,
      "status": "NEEDS-ACTION",
      "completedAt": null,
      "priority": 0,
      "parentId": 1,
      "deletedAt": null,
      "syncId": "child-sync",
      "icsUid": "child-uid"
    },
    {
      "id": 1,
      "calendarId": $calId,
      "summary": "Parent Todo",
      "description": null,
      "dueDate": null,
      "startDate": null,
      "status": "NEEDS-ACTION",
      "completedAt": null,
      "priority": 0,
      "parentId": null,
      "deletedAt": null,
      "syncId": "parent-sync",
      "icsUid": "parent-uid"
    }
  ]
}
''';

      await service.restoreFromJson(json);

      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(2));
      final parent = todos.firstWhere((t) => t.summary == 'Parent Todo');
      final child = todos.firstWhere((t) => t.summary == 'Child Todo');
      expect(child.parentId, parent.id, reason: 'Child parentId must link to parent regardless of array ordering');
    });

    test('Item 21: keepLocal on parent event/todo skips dependent tags, reminders, attachments, and child todos', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Personal'),
      );
      final tagId = await db.into(db.tags).insert(
        TagsCompanion.insert(name: 'Work', syncId: const Value('tag-1')),
      );
      final localEventId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: 'Original Local Event',
          startDt: DateTime.utc(2026, 11, 15, 9),
          endDt: DateTime.utc(2026, 11, 15, 10),
          syncId: const Value('event-sync-local'),
        ),
      );

      final json = '''
{
  "version": 1,
  "exportedAt": "2026-11-23T00:00:00.000Z",
  "calendars": [{"id": $calId, "name": "Personal", "color": "#2563EB", "timezone": "UTC", "isActive": true, "sortOrder": 0, "syncId": null}],
  "tags": [{"id": $tagId, "name": "Work", "color": "#2563EB", "syncId": "tag-1"}],
  "events": [{
    "id": $localEventId,
    "calendarId": $calId,
    "summary": "Backup Remote Event",
    "description": null,
    "startDt": "2026-11-15T09:00:00.000Z",
    "endDt": "2026-11-15T10:00:00.000Z",
    "isAllDay": false,
    "location": null,
    "rrule": null,
    "exdates": null,
    "deletedAt": null,
    "syncId": "event-sync-remote",
    "icsUid": "event-uid-remote"
  }],
  "eventTags": [{"eventId": $localEventId, "tagId": $tagId, "syncId": "assoc-1"}],
  "reminders": [{
    "id": 99,
    "parentType": "event",
    "parentId": $localEventId,
    "triggerTime": "2026-11-15T08:30:00.000Z",
    "isTriggered": false,
    "syncId": "rem-1",
    "parentSyncId": "event-sync-remote"
  }],
  "attachments": [{
    "id": 99,
    "parentType": "event",
    "parentId": $localEventId,
    "filePath": "/some/remote/path.pdf",
    "fileName": "path.pdf",
    "fileSize": 100,
    "mimeType": "application/pdf",
    "syncId": "att-1",
    "parentSyncId": "event-sync-remote",
    "serverFileRef": null
  }]
}
''';

      // Keep local for the event conflict
      await service.restoreFromJson(
        json,
        resolutions: {
          'events:$localEventId': BackupConflictResolution.keepLocal,
        },
      );

      final event = await (db.select(db.events)..where((e) => e.id.equals(localEventId))).getSingle();
      expect(event.summary, 'Original Local Event');

      final rems = await db.select(db.reminders).get();
      expect(rems, isEmpty, reason: 'Reminders for skipped event must not be written');

      final evTags = await db.select(db.eventTags).get();
      expect(evTags, isEmpty, reason: 'EventTags for skipped event must not be written');

      final atts = await db.select(db.attachments).get();
      expect(atts, isEmpty, reason: 'Attachments for skipped event must not be written');
    });

    test('Item 20: attachment with no body in backup preserves existing local valid filePath', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Personal'),
      );
      final todoId = await db.into(db.todos).insert(
        TodosCompanion.insert(calendarId: calId, summary: 'Task with photo'),
      );
      final attId = await db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          parentType: 'todo',
          parentId: todoId,
          filePath: '/existing/valid/local/photo.jpg',
          fileName: 'photo.jpg',
          fileSize: const Value(5000),
          syncId: const Value('att-sync-20'),
        ),
      );

      final json = '''
{
  "version": 1,
  "exportedAt": "2026-11-23T00:00:00.000Z",
  "calendars": [{"id": $calId, "name": "Personal", "color": "#2563EB", "timezone": "UTC", "isActive": true, "sortOrder": 0, "syncId": null}],
  "todos": [{
    "id": $todoId,
    "calendarId": $calId,
    "summary": "Task with photo",
    "description": null,
    "dueDate": null,
    "startDate": null,
    "status": "NEEDS-ACTION",
    "completedAt": null,
    "priority": 0,
    "parentId": null,
    "deletedAt": null,
    "syncId": null,
    "icsUid": null
  }],
  "attachments": [{
    "id": $attId,
    "parentType": "todo",
    "parentId": $todoId,
    "filePath": "",
    "fileName": "photo.jpg",
    "fileSize": 5000,
    "mimeType": "image/jpeg",
    "syncId": "att-sync-20",
    "parentSyncId": null,
    "serverFileRef": null
  }]
}
''';

      // Restore without archive body
      await service.restoreFromJson(json);

      final att = await (db.select(db.attachments)..where((a) => a.id.equals(attId))).getSingle();
      expect(att.filePath, '/existing/valid/local/photo.jpg', reason: 'Existing valid local filePath must NOT be cleared');
    });

    test('Item 22: inspectConflicts detects conflicts across all tables and resolutions gate writes', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Local Calendar', syncId: const Value('cal-local')),
      );
      final tagId = await db.into(db.tags).insert(
        TagsCompanion.insert(name: 'Local Tag', syncId: const Value('tag-local')),
      );

      final data = {
        'calendars': [
          {'id': calId, 'name': 'Conflicting Remote Calendar', 'color': '#FF0000', 'syncId': 'cal-remote'}
        ],
        'tags': [
          {'id': tagId, 'name': 'Conflicting Remote Tag', 'color': '#00FF00', 'syncId': 'tag-remote'}
        ],
        'events': <Map<String, dynamic>>[],
        'todos': <Map<String, dynamic>>[],
        'reminders': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
      };

      final conflicts = await service.inspectConflicts(data);
      expect(conflicts.any((c) => c.table == 'calendars' && c.id == calId), isTrue);
      expect(conflicts.any((c) => c.table == 'tags' && c.id == tagId), isTrue);

      // Without resolution (unselected), neither conflicting calendar nor tag should overwrite local
      await service.restoreData(data);

      final cal = await (db.select(db.calendars)..where((c) => c.id.equals(calId))).getSingle();
      expect(cal.name, 'Local Calendar');

      final tag = await (db.select(db.tags)..where((t) => t.id.equals(tagId))).getSingle();
      expect(tag.name, 'Local Tag');
    });

    test('Calendar & Tag ID collision: keepRemote imports a new row instead of overwriting the unrelated local row', () async {
      await db.delete(db.calendars).go();
      await db.delete(db.tags).go();
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Local Cal', color: const Value('#111111')),
      );
      final tagId = await db.into(db.tags).insert(
        TagsCompanion.insert(name: 'Local Tag', color: const Value('#222222')),
      );

      final data = {
        'calendars': [
          {'id': calId, 'name': 'Remote Cal', 'color': '#333333', 'syncId': 'diff-cal-sync'}
        ],
        'tags': [
          {'id': tagId, 'name': 'Remote Tag', 'color': '#444444', 'syncId': 'diff-tag-sync'}
        ],
        'events': <Map<String, dynamic>>[],
        'todos': <Map<String, dynamic>>[],
        'reminders': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
      };

      // Path A: keepRemote must not touch the unrelated local row; it imports
      // the remote calendar/tag as separate rows.
      await service.restoreData(
        data,
        resolutions: {
          'calendars:$calId': BackupConflictResolution.keepRemote,
          'tags:$tagId': BackupConflictResolution.keepRemote,
        },
      );

      final cals = await db.select(db.calendars).get();
      expect(cals, hasLength(2));
      final keptCal = cals.firstWhere((c) => c.id == calId);
      expect(keptCal.name, 'Local Cal');
      expect(keptCal.color, '#111111');
      final importedCal = cals.firstWhere((c) => c.id != calId);
      expect(importedCal.name, 'Remote Cal');
      expect(importedCal.color, '#333333');
      expect(importedCal.syncId, 'diff-cal-sync');

      final tags = await db.select(db.tags).get();
      expect(tags, hasLength(2));
      final keptTag = tags.firstWhere((t) => t.id == tagId);
      expect(keptTag.name, 'Local Tag');
      expect(keptTag.color, '#222222');
      final importedTag = tags.firstWhere((t) => t.id != tagId);
      expect(importedTag.name, 'Remote Tag');
      expect(importedTag.color, '#444444');
      expect(importedTag.syncId, 'diff-tag-sync');

      // Path B: keepLocal skips the remote row and leaves everything intact.
      final data2 = {
        'calendars': [
          {'id': calId, 'name': 'Another Cal', 'color': '#555555', 'syncId': 'yet-another-sync'}
        ],
        'tags': [
          {'id': tagId, 'name': 'Another Tag', 'color': '#666666', 'syncId': 'yet-another-tag-sync'}
        ],
        'events': <Map<String, dynamic>>[],
        'todos': <Map<String, dynamic>>[],
        'reminders': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
      };

      await service.restoreData(
        data2,
        resolutions: {
          'calendars:$calId': BackupConflictResolution.keepLocal,
          'tags:$tagId': BackupConflictResolution.keepLocal,
        },
      );

      final cals2 = await db.select(db.calendars).get();
      expect(cals2, hasLength(2));
      expect(cals2.firstWhere((c) => c.id == calId).name, 'Local Cal');

      final tags2 = await db.select(db.tags).get();
      expect(tags2, hasLength(2));
      expect(tags2.firstWhere((t) => t.id == tagId).name, 'Local Tag');
    });

    test('Event & Todo ID collision: keepRemote imports new rows and keeps both local rows distinct', () async {
      await db.delete(db.events).go();
      await db.delete(db.todos).go();
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Cal'),
      );
      final localEventId = await db.into(db.events).insert(
        EventsCompanion.insert(
          id: const Value(10),
          calendarId: calId,
          summary: 'Local Event',
          startDt: DateTime.utc(2026, 11, 20, 9),
          endDt: DateTime.utc(2026, 11, 20, 10),
          syncId: const Value('local-event-sync'),
        ),
      );
      final localTodoId = await db.into(db.todos).insert(
        TodosCompanion.insert(
          id: const Value(20),
          calendarId: calId,
          summary: 'Local Todo',
          syncId: const Value('local-todo-sync'),
        ),
      );

      final data = {
        'calendars': <Map<String, dynamic>>[],
        'events': [
          {
            'id': 10,
            'calendarId': calId,
            'summary': 'Remote Event',
            'startDt': '2026-11-20T09:00:00.000Z',
            'endDt': '2026-11-20T10:00:00.000Z',
            'syncId': 'remote-event-sync',
            'icsUid': 'remote-event-uid',
          }
        ],
        'todos': [
          {
            'id': 20,
            'calendarId': calId,
            'summary': 'Remote Todo',
            'syncId': 'remote-todo-sync',
            'icsUid': 'remote-todo-uid',
          }
        ],
        'reminders': <Map<String, dynamic>>[],
        'tags': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
      };

      await service.restoreData(
        data,
        resolutions: {
          'events:10': BackupConflictResolution.keepRemote,
          'todos:20': BackupConflictResolution.keepRemote,
        },
      );

      final events = await db.select(db.events).get();
      expect(events, hasLength(2));
      final keptEvent = events.firstWhere((e) => e.id == localEventId);
      expect(keptEvent.summary, 'Local Event', reason: 'the collided local row keeps its own content');
      expect(keptEvent.syncId, 'local-event-sync');
      final importedEvent = events.firstWhere((e) => e.id != localEventId);
      expect(importedEvent.summary, 'Remote Event');
      expect(importedEvent.syncId, 'remote-event-sync');

      final todos = await db.select(db.todos).get();
      expect(todos, hasLength(2));
      final keptTodo = todos.firstWhere((t) => t.id == localTodoId);
      expect(keptTodo.summary, 'Local Todo', reason: 'the collided local row keeps its own content');
      expect(keptTodo.syncId, 'local-todo-sync');
      final importedTodo = todos.firstWhere((t) => t.id != localTodoId);
      expect(importedTodo.summary, 'Remote Todo');
      expect(importedTodo.syncId, 'remote-todo-sync');
    });

    test('Parent ID collision: keepRemote repoints its reminder and attachment to the imported parent', () async {
      final tempDir = Directory.systemTemp.createTempSync('dayspark_test_parent_collision');
      final attService = BackupService(
        db,
        files: AttachmentFileStore(root: () async => tempDir),
      );
      try {
        await db.delete(db.attachments).go();
        await db.delete(db.reminders).go();
        await db.delete(db.events).go();
        final calId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(name: 'Cal'),
        );
        final localEventId = await db.into(db.events).insert(
          EventsCompanion.insert(
            id: const Value(30),
            calendarId: calId,
            summary: 'Local Parent',
            startDt: DateTime.utc(2026, 11, 20, 9),
            endDt: DateTime.utc(2026, 11, 20, 10),
            syncId: const Value('local-parent-sync'),
          ),
        );
        final localReminderId = await db.into(db.reminders).insert(
          RemindersCompanion.insert(
            id: const Value(40),
            parentType: 'event',
            parentId: localEventId,
            triggerTime: DateTime.utc(2026, 11, 20, 8),
            syncId: const Value('local-reminder-sync'),
            parentSyncId: const Value('local-parent-sync'),
          ),
        );
        final localAttId = await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: const Value(50),
            parentType: 'event',
            parentId: localEventId,
            filePath: '/local/local.txt',
            fileName: 'local.txt',
          ),
        );

        final archive = Archive();
        final content = utf8.encode('remote-body');
        archive.addFile(ArchiveFile(
          BackupService.attachmentEntryName(id: 50, syncId: 'remote-att-sync', fileName: 'remote.txt'),
          content.length,
          content,
        ));

        final data = {
          'calendars': <Map<String, dynamic>>[],
          'events': [
            {
              'id': 30,
              'calendarId': calId,
              'summary': 'Remote Parent',
              'startDt': '2026-11-20T09:00:00.000Z',
              'endDt': '2026-11-20T10:00:00.000Z',
              'syncId': 'remote-parent-sync',
              'icsUid': 'remote-parent-uid',
            }
          ],
          'todos': <Map<String, dynamic>>[],
          'reminders': [
            {
              'id': 40,
              'parentType': 'event',
              'parentId': 30,
              'triggerTime': '2026-11-20T07:00:00.000Z',
              'isTriggered': false,
              'syncId': 'remote-reminder-sync',
              'parentSyncId': 'remote-parent-sync',
            }
          ],
          'tags': <Map<String, dynamic>>[],
          'attachments': [
            {
              'id': 50,
              'parentType': 'event',
              'parentId': 30,
              'filePath': '/remote/remote.txt',
              'fileName': 'remote.txt',
              'fileSize': content.length,
              'mimeType': 'text/plain',
              'syncId': 'remote-att-sync',
              'parentSyncId': 'remote-parent-sync',
              'serverFileRef': null,
            }
          ],
        };

        await attService.restoreData(
          data,
          archive: archive,
          resolutions: {
            'events:30': BackupConflictResolution.keepRemote,
            'reminders:40': BackupConflictResolution.keepRemote,
            'attachments:50': BackupConflictResolution.keepRemote,
          },
        );

        final events = await db.select(db.events).get();
        expect(events, hasLength(2));
        final keptEvent = events.firstWhere((e) => e.id == localEventId);
        expect(keptEvent.summary, 'Local Parent');
        final importedEvent = events.firstWhere((e) => e.id != localEventId);
        expect(importedEvent.summary, 'Remote Parent');

        final reminders = await db.select(db.reminders).get();
        expect(reminders, hasLength(2));
        final keptReminder = reminders.firstWhere((r) => r.id == localReminderId);
        expect(keptReminder.parentId, localEventId);
        final importedReminder = reminders.firstWhere((r) => r.id != localReminderId);
        expect(importedReminder.syncId, 'remote-reminder-sync');
        expect(
          importedReminder.parentId,
          importedEvent.id,
          reason: 'a reminder follows the parent it was imported with, not the collided local parent',
        );
        expect(importedReminder.parentSyncId, 'remote-parent-sync');

        final atts = await db.select(db.attachments).get();
        expect(atts, hasLength(2));
        final keptAtt = atts.firstWhere((a) => a.id == localAttId);
        expect(keptAtt.fileName, 'local.txt');
        expect(keptAtt.filePath, '/local/local.txt', reason: 'the collided local attachment is untouched');
        final importedAtt = atts.firstWhere((a) => a.id != localAttId);
        expect(importedAtt.fileName, 'remote.txt');
        expect(
          importedAtt.parentId,
          importedEvent.id,
          reason: 'an attachment follows the parent it was imported with, not the collided local parent',
        );
        expect(importedAtt.filePath, contains(attachmentFileKey(importedAtt.id)));
        expect(File(importedAtt.filePath).existsSync(), isTrue);
        expect(await File(importedAtt.filePath).readAsBytes(), content);
        expect(
          File('${tempDir.path}/a50_remote.txt').existsSync(),
          isFalse,
          reason: 'no orphan file keyed by the backup id',
        );
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('inspectConflicts correctly populates associatedSkippedCount', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Cal 1', color: const Value('#111111')),
      );

      final data = {
        'calendars': [
          {'id': calId, 'name': 'Changed Cal', 'color': '#999999', 'syncId': null}
        ],
        'events': [
          {
            'id': 101,
            'calendarId': calId,
            'summary': 'Event 1',
            'startDt': '2026-11-20T09:00:00.000Z',
            'endDt': '2026-11-20T10:00:00.000Z',
          },
          {
            'id': 102,
            'calendarId': calId,
            'summary': 'Event 2',
            'startDt': '2026-11-20T11:00:00.000Z',
            'endDt': '2026-11-20T12:00:00.000Z',
          },
        ],
        'todos': [
          {
            'id': 201,
            'calendarId': calId,
            'summary': 'Todo 1',
          },
        ],
        'tags': <Map<String, dynamic>>[],
        'eventTags': [
          {'eventId': 101, 'tagId': 301, 'syncId': 'et-1'},
        ],
        'todoTags': [
          {'todoId': 201, 'tagId': 301, 'syncId': 'tt-1'},
        ],
        'reminders': [
          {
            'id': 401,
            'parentType': 'event',
            'parentId': 102,
            'triggerTime': '2026-11-20T08:00:00.000Z',
            'isTriggered': false,
            'syncId': 'rem-1',
            'parentSyncId': null,
          },
          {
            'id': 402,
            'parentType': 'todo',
            'parentId': 201,
            'triggerTime': '2026-11-20T08:00:00.000Z',
            'isTriggered': false,
            'syncId': 'rem-2',
            'parentSyncId': null,
          },
        ],
        'attachments': [
          {
            'id': 501,
            'parentType': 'event',
            'parentId': 101,
            'filePath': '',
            'fileName': 'a.pdf',
            'fileSize': 1,
            'mimeType': 'application/pdf',
            'syncId': 'att-1',
            'parentSyncId': null,
            'serverFileRef': null,
          },
        ],
      };

      final conflicts = await service.inspectConflicts(data);
      final calConflict = conflicts.firstWhere((c) => c.table == 'calendars' && c.id == calId);
      expect(
        calConflict.associatedSkippedCount,
        8,
        reason:
            '2 events + 1 todo + 1 eventTag + 1 todoTag + 2 reminders + 1 attachment',
      );
    });

    test('Attachment inserted as new row writes file matching the newly generated row id', () async {
      final tempDir = Directory.systemTemp.createTempSync('dayspark_test_att');
      final attService = BackupService(
        db,
        files: AttachmentFileStore(root: () async => tempDir),
      );
      try {
        final calId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(name: 'Cal'),
        );
        final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(calendarId: calId, summary: 'Task A'),
        );

        // Pre-seed an attachment with id 50 so that backup attachment id 50 collides
        await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: const Value(50),
            parentType: 'todo',
            parentId: todoId,
            filePath: '/local/file50.txt',
            fileName: 'file50.txt',
          ),
        );

        final archive = Archive();
        final content = utf8.encode('attachment-content');
        archive.addFile(ArchiveFile(
          BackupService.attachmentEntryName(id: 80, syncId: 'att-sync-80', fileName: 'new-file.txt'),
          content.length,
          content,
        ));

        final data = {
          'calendars': <Map<String, dynamic>>[],
          'tags': <Map<String, dynamic>>[],
          'events': <Map<String, dynamic>>[],
          'todos': <Map<String, dynamic>>[],
          'reminders': <Map<String, dynamic>>[],
          'attachments': [
            {
              'id': 80,
              'parentType': 'todo',
              'parentId': todoId,
              'filePath': '/remote/new-file.txt',
              'fileName': 'new-file.txt',
              'fileSize': content.length,
              'syncId': 'att-sync-80',
              'parentSyncId': null,
              'serverFileRef': null,
            }
          ],
        };

        await attService.restoreData(data, archive: archive);

        final atts = await (db.select(db.attachments)..where((tbl) => tbl.fileName.equals('new-file.txt'))).get();
        expect(atts, hasLength(1));
        final newAtt = atts.first;
        expect(newAtt.filePath, contains(attachmentFileKey(newAtt.id)),
            reason: 'File key must be built with the actual row id in DB');
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('eventTags and todoTags are gated when parent or association resolution is keepLocal', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Cal', syncId: const Value('cal-sync')),
      );
      final tagId = await db.into(db.tags).insert(
        TagsCompanion.insert(name: 'Tag 1', color: const Value('#111111'), syncId: const Value('tag-sync-1')),
      );
      final eventId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: 'Local Event',
          startDt: DateTime.utc(2026, 11, 20, 9),
          endDt: DateTime.utc(2026, 11, 20, 10),
          syncId: const Value('event-sync-local'),
        ),
      );
      final todoId = await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Local Todo',
          syncId: const Value('todo-sync-local'),
        ),
      );

      // Pre-condition: no eventTags or todoTags
      expect(await db.select(db.eventTags).get(), isEmpty);
      expect(await db.select(db.todoTags).get(), isEmpty);

      // Scenario A: parent item kept local -> association rows must NOT be written
      final dataA = {
        'calendars': <Map<String, dynamic>>[],
        'tags': <Map<String, dynamic>>[],
        'events': [
          {
            'id': eventId,
            'calendarId': calId,
            'summary': 'Remote Event Conflict',
            'startDt': '2026-11-20T09:00:00.000Z',
            'endDt': '2026-11-20T10:00:00.000Z',
            'syncId': 'diff-event-sync',
          }
        ],
        'todos': [
          {
            'id': todoId,
            'calendarId': calId,
            'summary': 'Remote Todo Conflict',
            'syncId': 'diff-todo-sync',
          }
        ],
        'eventTags': [
          {'eventId': eventId, 'tagId': tagId, 'syncId': 'et-sync-1'}
        ],
        'todoTags': [
          {'todoId': todoId, 'tagId': tagId, 'syncId': 'tt-sync-1'}
        ],
        'reminders': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
      };

      await service.restoreData(
        dataA,
        resolutions: {
          'events:$eventId': BackupConflictResolution.keepLocal,
          'todos:$todoId': BackupConflictResolution.keepLocal,
        },
      );

      expect(await db.select(db.eventTags).get(), isEmpty,
          reason: 'eventTags must not be written when event resolution is keepLocal');
      expect(await db.select(db.todoTags).get(), isEmpty,
          reason: 'todoTags must not be written when todo resolution is keepLocal');

      // Scenario B: parent item keepRemote -> association rows ARE written
      await service.restoreData(
        dataA,
        resolutions: {
          'events:$eventId': BackupConflictResolution.keepRemote,
          'todos:$todoId': BackupConflictResolution.keepRemote,
        },
      );

      expect(await db.select(db.eventTags).get(), hasLength(1),
          reason: 'eventTags must be written when event resolution is keepRemote');
      expect(await db.select(db.todoTags).get(), hasLength(1),
          reason: 'todoTags must be written when todo resolution is keepRemote');
    });

    test('join rows follow the effective parent id on keepRemote and drop on keepLocal', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Cal', syncId: const Value('cal-sync')),
      );
      final tagId = await db.into(db.tags).insert(
        TagsCompanion.insert(
          name: 'Tag 1',
          color: const Value('#111111'),
          syncId: const Value('tag-sync-1'),
        ),
      );
      final eventId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: 'Local Event',
          startDt: DateTime.utc(2026, 11, 20, 9),
          endDt: DateTime.utc(2026, 11, 20, 10),
          syncId: const Value('event-shared'),
        ),
      );
      final todoId = await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Local Todo',
          syncId: const Value('todo-shared'),
        ),
      );

      // keepRemote: backup rows match by syncId under different backup ids, so
      // the effective parent id is the existing local row, not the backup id.
      await service.restoreData(
        {
          'calendars': <Map<String, dynamic>>[],
          'tags': <Map<String, dynamic>>[],
          'events': [
            {
              'id': 900,
              'calendarId': calId,
              'summary': 'Remote Event',
              'startDt': '2026-11-20T09:00:00.000Z',
              'endDt': '2026-11-20T10:00:00.000Z',
              'syncId': 'event-shared',
            }
          ],
          'todos': [
            {
              'id': 901,
              'calendarId': calId,
              'summary': 'Remote Todo',
              'syncId': 'todo-shared',
            }
          ],
          'eventTags': [
            {'eventId': 900, 'tagId': tagId, 'syncId': 'et-1'}
          ],
          'todoTags': [
            {'todoId': 901, 'tagId': tagId, 'syncId': 'tt-1'}
          ],
          'reminders': <Map<String, dynamic>>[],
          'attachments': <Map<String, dynamic>>[],
        },
        resolutions: {
          'events:900': BackupConflictResolution.keepRemote,
          'todos:901': BackupConflictResolution.keepRemote,
        },
      );

      final eventTags = await db.select(db.eventTags).get();
      expect(eventTags, hasLength(1));
      expect(eventTags.single.eventId, eventId,
          reason: 'join must point at the kept local event, not backup id 900');
      expect(eventTags.single.tagId, tagId);
      final todoTags = await db.select(db.todoTags).get();
      expect(todoTags, hasLength(1));
      expect(todoTags.single.todoId, todoId,
          reason: 'join must point at the kept local todo, not backup id 901');
      expect(todoTags.single.tagId, tagId);

      // keepLocal: the parent is skipped, so its joins must not be written.
      final tag2Id = await db.into(db.tags).insert(
        TagsCompanion.insert(
          name: 'Tag 2',
          color: const Value('#222222'),
          syncId: const Value('tag-sync-2'),
        ),
      );
      await service.restoreData(
        {
          'calendars': <Map<String, dynamic>>[],
          'tags': <Map<String, dynamic>>[],
          'events': [
            {
              'id': eventId,
              'calendarId': calId,
              'summary': 'Clashing Event',
              'startDt': '2026-11-20T11:00:00.000Z',
              'endDt': '2026-11-20T12:00:00.000Z',
              'syncId': 'event-clash',
            }
          ],
          'todos': [
            {
              'id': todoId,
              'calendarId': calId,
              'summary': 'Clashing Todo',
              'syncId': 'todo-clash',
            }
          ],
          'eventTags': [
            {'eventId': eventId, 'tagId': tag2Id, 'syncId': 'et-clash'}
          ],
          'todoTags': [
            {'todoId': todoId, 'tagId': tag2Id, 'syncId': 'tt-clash'}
          ],
          'reminders': <Map<String, dynamic>>[],
          'attachments': <Map<String, dynamic>>[],
        },
        resolutions: {
          'events:$eventId': BackupConflictResolution.keepLocal,
          'todos:$todoId': BackupConflictResolution.keepLocal,
        },
      );

      expect(await db.select(db.eventTags).get(), hasLength(1),
          reason: 'keepLocal parent must drop its eventTags join rows');
      expect(await db.select(db.todoTags).get(), hasLength(1),
          reason: 'keepLocal parent must drop its todoTags join rows');
      expect(
        (await db.select(db.eventTags).get()).any((et) => et.tagId == tag2Id),
        isFalse,
      );
      expect(
        (await db.select(db.todoTags).get()).any((tt) => tt.tagId == tag2Id),
        isFalse,
      );
    });

    test('a keepLocal conflict on the effective id does not suppress a keepRemote join', () async {
      final calId = await db.into(db.calendars).insert(
        CalendarsCompanion.insert(name: 'Cal', syncId: const Value('cal-sync')),
      );
      final tagId = await db.into(db.tags).insert(
        TagsCompanion.insert(
          name: 'Tag',
          color: const Value('#111111'),
          syncId: const Value('tag-sync'),
        ),
      );
      final eventPId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: 'P local',
          startDt: DateTime.utc(2026, 11, 20, 9),
          endDt: DateTime.utc(2026, 11, 20, 10),
          syncId: const Value('p-local'),
        ),
      );
      final eventQId = await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calId,
          summary: 'Q local',
          startDt: DateTime.utc(2026, 11, 20, 11),
          endDt: DateTime.utc(2026, 11, 20, 12),
          syncId: const Value('shared'),
        ),
      );

      // The first backup row collides on P's integer id but matches Q by
      // syncId, so its effective parent is Q. The second row collides on Q's
      // integer id and is kept local. That keepLocal decision must not gate
      // the first row's join.
      await service.restoreData(
        {
          'calendars': <Map<String, dynamic>>[],
          'tags': <Map<String, dynamic>>[],
          'events': [
            {
              'id': eventPId,
              'calendarId': calId,
              'summary': 'Q remote',
              'startDt': '2026-11-20T11:00:00.000Z',
              'endDt': '2026-11-20T12:00:00.000Z',
              'syncId': 'shared',
            },
            {
              'id': eventQId,
              'calendarId': calId,
              'summary': 'Other remote',
              'startDt': '2026-11-20T13:00:00.000Z',
              'endDt': '2026-11-20T14:00:00.000Z',
              'syncId': 'q-other',
            },
          ],
          'todos': <Map<String, dynamic>>[],
          'eventTags': [
            {'eventId': eventPId, 'tagId': tagId, 'syncId': 'et-1'}
          ],
          'todoTags': <Map<String, dynamic>>[],
          'reminders': <Map<String, dynamic>>[],
          'attachments': <Map<String, dynamic>>[],
        },
        resolutions: {
          'events:$eventPId': BackupConflictResolution.keepRemote,
          'events:$eventQId': BackupConflictResolution.keepLocal,
        },
      );

      final eventTags = await db.select(db.eventTags).get();
      expect(eventTags, hasLength(1));
      expect(eventTags.single.eventId, eventQId,
          reason: 'join follows keepRemote to the effective parent id');
      expect(eventTags.single.tagId, tagId);
    });

    test('attachment matched by syncId writes bytes under the existing row id, not the backup id', () async {
      final tempDir = Directory.systemTemp.createTempSync('dayspark_test_att_key');
      final attService = BackupService(
        db,
        files: AttachmentFileStore(root: () async => tempDir),
      );
      try {
        final calId = await db.into(db.calendars).insert(
          CalendarsCompanion.insert(name: 'Cal'),
        );
        final todoId = await db.into(db.todos).insert(
          TodosCompanion.insert(calendarId: calId, summary: 'Task A'),
        );
        final localAttId = await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            parentType: 'todo',
            parentId: todoId,
            filePath: '',
            fileName: 'old.txt',
            syncId: const Value('att-shared'),
          ),
        );

        final archive = Archive();
        final content = utf8.encode('body');
        archive.addFile(ArchiveFile(
          BackupService.attachmentEntryName(
            id: 80,
            syncId: 'att-shared',
            fileName: 'new.txt',
          ),
          content.length,
          content,
        ));

        await attService.restoreData(
          {
            'calendars': <Map<String, dynamic>>[],
            'tags': <Map<String, dynamic>>[],
            'events': <Map<String, dynamic>>[],
            'todos': <Map<String, dynamic>>[],
            'reminders': <Map<String, dynamic>>[],
            'attachments': [
              {
                'id': 80,
                'parentType': 'todo',
                'parentId': todoId,
                'filePath': '/remote/new.txt',
                'fileName': 'new.txt',
                'fileSize': content.length,
                'mimeType': 'text/plain',
                'syncId': 'att-shared',
                'parentSyncId': null,
                'serverFileRef': null,
              }
            ],
          },
          archive: archive,
        );

        final restored = await (db.select(db.attachments)
              ..where((a) => a.id.equals(localAttId)))
            .getSingle();
        expect(restored.id, localAttId);
        expect(restored.filePath, contains(attachmentFileKey(localAttId)));
        expect(File(restored.filePath).existsSync(), isTrue);
        expect(await File(restored.filePath).readAsBytes(), content);
        expect(
          File('${tempDir.path}/a80_new.txt').existsSync(),
          isFalse,
          reason: 'no orphan file keyed by the backup id',
        );
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });
}
