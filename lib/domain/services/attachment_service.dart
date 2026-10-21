import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/attachment_writer.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/services/attachment_files.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

/// No server configured: rows stay local and every blob call fails. Failing
/// (instead of no-oping) keeps the "not uploaded yet" marker honest — a row
/// with a null `serverFileRef` really has no blob behind it.
class LocalOnlyAttachmentApi implements AttachmentApi {
  const LocalOnlyAttachmentApi();

  static final StateError _noServer = StateError('no sync server configured');

  @override
  Future<AttachmentUploadResponse> uploadAttachment({
    required List<int> bytes,
  }) => Future.error(_noServer);

  @override
  Future<List<int>> downloadAttachment(String serverFileRef) =>
      Future.error(_noServer);

  @override
  Future<void> deleteAttachment(String serverFileRef) =>
      Future.error(_noServer);
}

/// Owns the attachment blob lifecycle: local copy, server blob, and the
/// metadata row that ties them together.
///
/// Ordering rule: the row is written first and the blob second, because a
/// row without a blob is recoverable (it shows as not-yet-uploaded and
/// [uploadPending] retries it) while a blob without a row is invisible
/// garbage. Every blob operation is therefore retryable from the row.
///
/// Web has no durable local file: there [localFiles] is false, `filePath`
/// stays empty, and content is fetched per open.
class AttachmentService {
  AttachmentService({
    required this.db,
    required this.api,
    AttachmentFileStore? files,
    bool? localFiles,
  }) : files = files ?? AttachmentFileStore(),
       localFiles = localFiles ?? !kIsWeb;

  final AppDatabase db;
  final AttachmentApi api;
  final AttachmentFileStore files;
  final bool localFiles;

  /// Creates the row, copies the bytes into app-owned storage, then uploads.
  ///
  /// The upload is best effort: creating an attachment offline must still
  /// produce a usable local attachment. A null `serverFileRef` is the "not
  /// uploaded yet" marker that [uploadPending] picks up later.
  Future<int> create({
    required String parentType,
    required int parentId,
    required String fileName,
    String? mimeType,
    List<int>? bytes,
    String? sourcePath,
  }) async {
    final data = bytes ?? await _readSource(sourcePath, fileName);
    final id = await RecordScope.run(
      db,
      (tx) => AttachmentWriter.add(
        db,
        tx,
        parentType: parentType,
        parentId: parentId,
        fileName: fileName,
        fileSize: data.length,
        mimeType: mimeType,
      ),
    );
    if (localFiles) {
      final path = await files.write(
        key: _key(id),
        fileName: fileName,
        bytes: data,
      );
      await RecordScope.run(
        db,
        (tx) => AttachmentWriter.update(
          db,
          tx,
          id,
          AttachmentsCompanion(filePath: Value(path)),
        ),
      );
    }
    try {
      await _upload(id, bytes: data);
    } catch (e) {
      // Offline (or a rejected upload): the row stays with a null ref and
      // uploadPending retries it on the next round.
      debugPrint('attachment: upload of $id failed: $e');
    }
    return id;
  }

  /// Uploads every row that has a local file but no server ref yet — the
  /// reconnect drain for attachments created while offline. Errors are per
  /// row and swallowed: one unreadable file must not stall sync.
  Future<void> uploadPending() async {
    if (!localFiles) return;
    final rows = await (db.select(
      db.attachments,
    )..where((t) => t.serverFileRef.isNull())).get();
    for (final row in rows) {
      try {
        await _upload(row.id);
      } catch (e) {
        debugPrint('attachment: upload of ${row.id} failed: $e');
      }
    }
  }

  Future<void> _upload(int id, {List<int>? bytes}) async {
    final row = await rowOf(id);
    if (row == null || row.serverFileRef != null) return;
    final data = bytes ?? await files.read(row.filePath);
    if (data == null) return;
    final uploaded = await api.uploadAttachment(bytes: data);
    await RecordScope.run(
      db,
      (tx) => AttachmentWriter.update(
        db,
        tx,
        id,
        AttachmentsCompanion(
          serverFileRef: Value(uploaded.serverFileRef),
          fileSize: Value(uploaded.fileSize),
        ),
      ),
    );
  }

  /// Bytes for [id], from the local copy when this device has one and from
  /// the server otherwise. Web always goes to the network (nothing local is
  /// durable there). Null when there is nothing to read and nothing to
  /// fetch — a local-only row whose file is gone.
  Future<Uint8List?> loadBytes(int id) async {
    final row = await rowOf(id);
    if (row == null) return null;
    final local = await files.read(row.filePath);
    if (local != null) return local;
    final ref = row.serverFileRef;
    if (ref == null || ref.isEmpty) return null;
    final bytes = await api.downloadAttachment(ref);
    if (localFiles) {
      final path = await files.write(
        key: _key(id),
        fileName: row.fileName,
        bytes: bytes,
      );
      await RecordScope.run(
        db,
        (tx) => AttachmentWriter.update(
          db,
          tx,
          id,
          AttachmentsCompanion(
            filePath: Value(path),
            fileSize: Value(bytes.length),
          ),
        ),
      );
    }
    return Uint8List.fromList(bytes);
  }

  /// Removes the local file, the row, and the server blob.
  ///
  /// The row goes first so a failure mid-way cannot leave a row pointing at
  /// a deleted file; the blob delete is best effort (a lost response must
  /// not fail the user's delete), and an orphaned blob is the accepted
  /// residue — the server has no per-user blob index to sweep it from yet.
  Future<void> delete(int id) async {
    final row = await rowOf(id);
    await RecordScope.run(db, (tx) => AttachmentWriter.delete(db, tx, id));
    await files.delete(row?.filePath);
    final ref = row?.serverFileRef;
    if (ref == null || ref.isEmpty) return;
    try {
      await api.deleteAttachment(ref);
    } catch (e) {
      debugPrint('attachment: blob delete of $ref failed: $e');
    }
  }

  Future<Attachment?> rowOf(int id) => (db.select(
    db.attachments,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  String _key(int id) => attachmentFileKey(id);

  Future<List<int>> _readSource(String? sourcePath, String fileName) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      throw StateError('attachment $fileName has no bytes and no source path');
    }
    final bytes = await files.read(sourcePath);
    if (bytes == null) {
      throw StateError('attachment source is gone: $sourcePath');
    }
    return bytes;
  }
}
