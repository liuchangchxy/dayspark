import 'package:drift/drift.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

/// Attachment rows are not parents of derived state (no reminders, no widget
/// projection), so none of these register a [RecordScope] event — the scope
/// is still opened so the row write and its outbox op commit together.
final class AttachmentWriter {
  const AttachmentWriter._();

  static Future<int> add(
    AppDatabase db,
    RecordScope tx, {
    required String parentType,
    required int parentId,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final id = await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            parentType: parentType,
            parentId: parentId,
            filePath: '',
            fileName: fileName,
            fileSize: Value(fileSize),
            mimeType: Value(mimeType),
          ),
        );
    await SyncOutbox.enqueueUpsert(db, RecordType.attachment, id);
    return id;
  }

  /// Patches a row and re-queues it: the metadata push is what carries the
  /// server file ref to the peer devices, so every change to it must sync.
  static Future<void> update(
    AppDatabase db,
    RecordScope tx,
    int id,
    AttachmentsCompanion patch,
  ) async {
    await (db.update(
      db.attachments,
    )..where((t) => t.id.equals(id))).write(patch);
    await SyncOutbox.enqueueUpsert(db, RecordType.attachment, id);
  }

  static Future<void> delete(AppDatabase db, RecordScope tx, int id) async {
    final targets = await SyncOutbox.captureDeletes(db, RecordType.attachment, [
      id,
    ]);
    await (db.delete(db.attachments)..where((t) => t.id.equals(id))).go();
    await SyncOutbox.enqueueDeletes(db, targets);
  }
}
