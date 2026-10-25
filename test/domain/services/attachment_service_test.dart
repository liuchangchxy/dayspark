import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/services/attachment_files.dart';
import 'package:dayspark/domain/services/attachment_service.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

import '../sync/sync_test_support.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late FakeTransport transport;
  late AttachmentService service;
  late int todoId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('dayspark_att_svc');
    transport = FakeTransport();
    final tokens = MemoryTokenStore(access: 'access-1', refresh: 'refresh-1');
    service = AttachmentService(
      db: db,
      api: AuthSyncApiClient(transport: transport, tokens: tokens),
      files: AttachmentFileStore(root: () async => dir),
    );
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    todoId = await db
        .into(db.todos)
        .insert(TodosCompanion.insert(calendarId: calId, summary: 'Task'));
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<int> createFromBytes(List<int> bytes, {String name = 'notes.txt'}) =>
      service.create(
        parentType: 'todo',
        parentId: todoId,
        fileName: name,
        mimeType: 'text/plain',
        bytes: bytes,
      );

  test('create copies the source file into app storage and uploads it', () async {
    final picked = File('${dir.path}/picked.txt')
      ..writeAsStringSync('attachment body');

    final id = await service.create(
      parentType: 'todo',
      parentId: todoId,
      fileName: 'notes.txt',
      mimeType: 'text/plain',
      sourcePath: picked.path,
    );

    final row = (await service.rowOf(id))!;
    expect(row.serverFileRef, 'blob-1');
    expect(transport.blobs['blob-1'], utf8.encode('attachment body'));
    expect(row.fileSize, utf8.encode('attachment body').length);
    // The picker path is a temp path the OS purges; the row must point at
    // the copy this app owns.
    expect(row.filePath, isNot(picked.path));
    expect(File(row.filePath).readAsStringSync(), 'attachment body');
    // The parent travels as its sync id — local integer ids are device-scoped.
    final todo = await (db.select(
      db.todos,
    )..where((t) => t.id.equals(todoId))).getSingle();
    expect(row.parentSyncId, todo.syncId);
    expect(row.parentSyncId, isNotNull);
  });

  test('create enqueues exactly one attachment upsert carrying the ref', () async {
    final id = await createFromBytes(const <int>[1, 2, 3]);

    final ops = await db.select(db.syncOutbox).get();
    expect(ops, hasLength(1));
    expect(ops.single.type, RecordType.attachment.wireName);
    expect(
      jsonDecode(ops.single.payloadJson!)['serverFileRef'],
      'blob-1',
    );
    expect((await service.rowOf(id))!.syncId, ops.single.recordId);
  });

  test('an upload that fails leaves the row local and uploadPending drains it', () async {
    transport.offlineUploads = true;
    final id = await createFromBytes(const <int>[4, 5, 6]);

    final offlineRow = (await service.rowOf(id))!;
    expect(offlineRow.serverFileRef, isNull);
    expect(File(offlineRow.filePath).existsSync(), isTrue);

    transport.offlineUploads = false;
    await service.uploadPending();

    final row = (await service.rowOf(id))!;
    expect(row.serverFileRef, 'blob-1');
    expect(transport.blobs['blob-1'], const <int>[4, 5, 6]);
  });

  test('loadBytes downloads the blob when this device has no file', () async {
    // A row that arrived over sync: metadata only, no local file.
    final id = await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            parentType: 'todo',
            parentId: todoId,
            filePath: '',
            fileName: 'remote.bin',
            syncId: const Value('att-remote'),
            serverFileRef: const Value('blob-9'),
          ),
        );
    transport.blobs['blob-9'] = const <int>[9, 8, 7];

    final bytes = await service.loadBytes(id);
    expect(bytes, const <int>[9, 8, 7]);
    final row = (await service.rowOf(id))!;
    expect(File(row.filePath).existsSync(), isTrue);
    expect(File(row.filePath).readAsBytesSync(), const <int>[9, 8, 7]);
    expect(row.fileSize, 3);
  });

  test('loadBytes returns null when there is neither a file nor a ref', () async {
    final id = await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            parentType: 'todo',
            parentId: todoId,
            filePath: '',
            fileName: 'ghost.txt',
          ),
        );
    expect(await service.loadBytes(id), isNull);
  });

  test('delete removes the local file, the row, and the server blob', () async {
    final id = await createFromBytes(const <int>[1, 1, 1]);
    final row = (await service.rowOf(id))!;
    final path = row.filePath;
    expect(transport.blobs, contains('blob-1'));

    await service.delete(id);

    expect(await service.rowOf(id), isNull);
    expect(File(path).existsSync(), isFalse);
    expect(transport.blobs, isEmpty);
    final deletes = await db.select(db.syncOutbox).get();
    expect(
      deletes.where((op) => op.op == OpType.delete.name),
      hasLength(1),
    );
  });

  test('delete still succeeds when the blob delete fails', () async {
    final id = await createFromBytes(const <int>[2, 2, 2]);
    transport.offlineDeletes = true;

    await service.delete(id);

    expect(await service.rowOf(id), isNull);
  });

  test('a rolled-back stage leaves no row and no file', () async {
    // A form commits its whole draft in one transaction. The attachment row
    // and its local file are written inside it, so a rollback has to take the
    // file too — SQLite can hand the same id to a later insert, which would
    // then adopt the orphan as its own. The path is reported through the
    // callback the moment the file exists, so a rollback *at any point after*
    // is covered.
    final staged = <String?>[];
    await expectLater(
      RecordScope.run(db, (tx) async {
        final doomed = await service.insertRow(
          tx,
          parentType: 'todo',
          parentId: todoId,
          fileName: 'doomed.txt',
          mimeType: 'text/plain',
          data: const <int>[7],
          onFileWritten: staged.add,
        );
        expect(File(doomed.filePath!).existsSync(), isTrue);
        expect(
          await service.rowOf(doomed.id),
          isNotNull,
          reason: 'the row is written in the same transaction as the file',
        );
        throw StateError('the draft failed after the attachment');
      }),
      throwsA(isA<StateError>()),
    );

    // What a form does on the way past its own rethrow.
    await service.discardStagedFiles(staged);

    expect(staged.single, isNotNull);
    expect(File(staged.single!).existsSync(), isFalse);
    expect(
      (await db.select(db.attachments).get()).where(
        (a) => a.fileName == 'doomed.txt',
      ),
      isEmpty,
      reason: 'the transaction took the row with it',
    );
  });

  test('discarding a staged file never throws', () async {
    // It runs while an error is on its way out; replacing that error with a
    // cleanup failure would hide what actually went wrong.
    await service.discardStagedFiles(<String?>[
      null,
      '/no/such/path/at/all',
      '${dir.path}/never-written.txt',
    ]);
  });
}
