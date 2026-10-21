import 'dart:io';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../data/record_writer.dart';
import '../db.dart';
import '../http.dart';

void registerAttachmentRoutes(
  Router router, {
  required AppDatabase db,
  required Auth auth,
  String storageDir = './data/attachments',
}) {
  final dir = Directory(storageDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  // Upload attachment file: POST /attachments/upload
  router.post(
    '/attachments/upload',
    auth.requireAuth((request, context) async {
      final bytes = await readBodyBytes(request, maxBytes: maxAttachmentBytes);
      if (bytes.isEmpty) {
        throw ApiException(400, errValidation, 'attachment body cannot be empty');
      }
      final fileRef = newOpId();
      final userDir = _userDir(dir, context.userId);
      await userDir.create(recursive: true);
      final file = File(p.join(userDir.path, fileRef));
      await file.writeAsBytes(bytes, flush: true);
      return jsonResponse(200, {'serverFileRef': fileRef, 'fileSize': bytes.length});
    }),
  );

  // Download attachment file: GET /attachments/<ref>
  router.get(
    '/attachments/<ref>',
    auth.requireAuth((request, context) async {
      final file = _attachmentFile(dir, context.userId, request.params['ref']);
      if (!file.existsSync()) {
        throw ApiException(404, 'not_found', 'attachment file not found');
      }
      final bytes = await file.readAsBytes();
      return Response.ok(
        bytes,
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': bytes.length.toString(),
        },
      );
    }),
  );

  // Delete attachment file: DELETE /attachments/<ref>
  // Idempotent: the client deletes the blob whenever the user removes an
  // attachment, and a retry after a lost response must not fail the UI.
  router.delete(
    '/attachments/<ref>',
    auth.requireAuth((request, context) async {
      final file = _attachmentFile(dir, context.userId, request.params['ref']);
      if (file.existsSync()) await file.delete();
      return jsonResponse(200, {'deleted': true});
    }),
  );
}

/// Blobs live under their owner's directory, so a ref only resolves inside
/// the caller's namespace: another account holding the same opaque token
/// finds nothing there (404 on download, no-op on delete).
Directory _userDir(Directory root, String userId) =>
    Directory(p.join(root.path, _plainSegment(userId, 'user scope')));

/// Resolves a ref to a blob path.
///
/// Refs are opaque ids the server issued, so anything that is not a plain
/// file-name token — a path separator, a dot segment, or a percent-encoded
/// form of either (shelf_router does not decode `%2F`, so `..%2Fsecret`
/// would otherwise be looked up as a literal name) — is a traversal
/// attempt rather than a ref. The user id gets the same rule; it is signed
/// by us, but a filesystem path should never depend on that.
File _attachmentFile(Directory root, String userId, String? ref) {
  if (ref == null || ref.isEmpty) {
    throw ApiException(400, errValidation, 'file ref required');
  }
  return File(
    p.join(_userDir(root, userId).path, _plainSegment(ref, 'file ref')),
  );
}

String _plainSegment(String value, String field) {
  final isPlain =
      value != '.' &&
      value != '..' &&
      value == p.basename(value) &&
      !value.contains('%') &&
      !value.contains('\\');
  if (!isPlain) {
    throw ApiException(400, errValidation, 'invalid $field');
  }
  return value;
}
