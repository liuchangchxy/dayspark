import 'dart:io';
import 'dart:typed_data';

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
}
