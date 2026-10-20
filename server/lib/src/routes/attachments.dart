import 'dart:io';

import 'package:dayspark_contracts/dayspark_contracts.dart';
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
      final bytes = await readBodyBytes(request);
      if (bytes.isEmpty) {
        throw ApiException(400, errValidation, 'attachment body cannot be empty');
      }
      final fileRef = newOpId();
      final file = File('${dir.path}/$fileRef');
      await file.writeAsBytes(bytes);
      return jsonResponse(200, {'serverFileRef': fileRef, 'fileSize': bytes.length});
    }),
  );

  // Download attachment file: GET /attachments/<ref>
  router.get(
    '/attachments/<ref>',
    auth.requireAuth((request, context) async {
      final ref = request.params['ref'];
      if (ref == null || ref.isEmpty) {
        throw ApiException(400, errValidation, 'file ref required');
      }
      final file = File('${dir.path}/$ref');
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
}
