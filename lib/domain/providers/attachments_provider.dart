import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

/// Attachments for an event.
final eventAttachmentsProvider = StreamProvider.family<List<Attachment>, int>((
  ref,
  eventId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.attachments)..where(
        (t) => t.parentType.equals('event') & t.parentId.equals(eventId),
      ))
      .watch();
});

/// Attachments for a todo.
final todoAttachmentsProvider = StreamProvider.family<List<Attachment>, int>((
  ref,
  todoId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.attachments)
        ..where((t) => t.parentType.equals('todo') & t.parentId.equals(todoId)))
      .watch();
});

/// Create an attachment.
final createAttachmentProvider =
    Provider<
      Future<int> Function({
        required String parentType,
        required int parentId,
        required String filePath,
        required String fileName,
        String? mimeType,
      })
    >((ref) {
      final db = ref.read(databaseProvider);
      return ({
        required parentType,
        required parentId,
        required filePath,
        required fileName,
        mimeType,
      }) async {
        final id = await db
            .into(db.attachments)
            .insert(
              AttachmentsCompanion.insert(
                parentType: parentType,
                parentId: parentId,
                filePath: filePath,
                fileName: fileName,
                mimeType: Value(mimeType),
              ),
            );
        await SyncOutbox.enqueueUpsert(db, RecordType.attachment, id);
        return id;
      };
    });

/// Delete an attachment.
final deleteAttachmentProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.read(databaseProvider);
  return (int id) async {
    final targets = await SyncOutbox.captureDeletes(db, RecordType.attachment, [id]);
    await (db.delete(db.attachments)..where((t) => t.id.equals(id))).go();
    await SyncOutbox.enqueueDeletes(db, targets);
  };
});
