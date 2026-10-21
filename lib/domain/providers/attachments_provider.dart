import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/sync_client_provider.dart';
import 'package:dayspark/domain/services/attachment_service.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';

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

/// Blob seam for attachments.
///
/// Without a configured server this is a local-only service rather than a
/// null provider: adding an attachment offline has to keep working, and the
/// row's null `serverFileRef` is what marks it for a later upload.
final attachmentServiceProvider = Provider<AttachmentService>((ref) {
  final db = ref.watch(databaseProvider);
  final settings = ref.watch(syncSettingsProvider).valueOrNull;
  final baseUrl = settings?.baseUrl;
  if (settings == null || baseUrl == null) {
    return AttachmentService(db: db, api: const LocalOnlyAttachmentApi());
  }
  return AttachmentService(
    db: db,
    api: AuthSyncApiClient(
      transport: DioSyncTransport(baseUrl: baseUrl),
      tokens: ref.watch(syncTokenStoreProvider),
      deviceId: settings.deviceId,
    ),
  );
});

/// Create an attachment: row, local copy, then upload (best effort).
final createAttachmentProvider =
    Provider<
      Future<int> Function({
        required String parentType,
        required int parentId,
        required String fileName,
        String? mimeType,
        List<int>? bytes,
        String? sourcePath,
      })
    >((ref) {
      final service = ref.read(attachmentServiceProvider);
      return ({
        required parentType,
        required parentId,
        required fileName,
        mimeType,
        bytes,
        sourcePath,
      }) => service.create(
        parentType: parentType,
        parentId: parentId,
        fileName: fileName,
        mimeType: mimeType,
        bytes: bytes,
        sourcePath: sourcePath,
      );
    });

/// Delete an attachment: local file, row, then the server blob.
final deleteAttachmentProvider = Provider<Future<void> Function(int)>((ref) {
  final service = ref.read(attachmentServiceProvider);
  return service.delete;
});

/// Bytes of an attachment, fetched from the server when this device only
/// holds the synced metadata. Null when there is nothing to open.
///
/// Bytes rather than a path because web has no filesystem to hand back and
/// the sharing path accepts in-memory data on every platform.
final loadAttachmentBytesProvider =
    Provider<Future<Uint8List?> Function(int)>((ref) {
      final service = ref.read(attachmentServiceProvider);
      return service.loadBytes;
    });

/// Flushes attachments whose upload did not land (created offline). Wired to
/// the sync round so a reconnect drains them without user action.
final uploadPendingAttachmentsProvider = Provider<Future<void> Function()>((
  ref,
) {
  final service = ref.read(attachmentServiceProvider);
  return service.uploadPending;
});
