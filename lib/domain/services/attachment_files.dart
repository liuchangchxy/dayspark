import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk home for attachment bodies.
///
/// WHY every attachment is copied in here instead of keeping the picker's
/// path: file_picker hands out cache/temp paths that the OS purges, and a
/// path from another device means nothing locally — so a row's `filePath`
/// only ever points at a file this app owns.
class AttachmentFileStore {
  AttachmentFileStore({Future<Directory> Function()? root})
    : _root = root ?? _defaultRoot;

  static Future<Directory> _defaultRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'attachments'));
  }

  final Future<Directory> Function() _root;

  Future<Directory> directory() async {
    final dir = await _root();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes [bytes] under a name derived from [key] so two attachments that
  /// share a file name never collide, and the same row always maps to the
  /// same path (restore recomputes it instead of trusting the backup's
  /// absolute path, which is meaningless on another device).
  Future<String> write({
    required String key,
    required String fileName,
    required List<int> bytes,
  }) async {
    final dir = await directory();
    final file = File(p.join(dir.path, pathFor(key: key, fileName: fileName)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String pathFor({required String key, required String fileName}) =>
      '${sanitizeKey(key)}_${sanitizeFileName(fileName)}';

  Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  Future<Uint8List?> read(String? path) async {
    if (!await exists(path)) return null;
    return File(path!).readAsBytes();
  }

  Future<void> delete(String? path) async {
    if (!await exists(path)) return;
    await File(path!).delete();
  }
}

/// Local file key for an attachment row. One definition because the writer
/// ([AttachmentService]) and the restorer ([BackupService]) must agree, or a
/// restored row points at a file nobody wrote.
String attachmentFileKey(int id) => 'a$id';

String sanitizeKey(String key) {
  final cleaned = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return cleaned.isEmpty ? 'attachment' : cleaned;
}

String sanitizeFileName(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last;
  final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return cleaned.isEmpty ? 'attachment' : cleaned;
}

/// Content type for an attachment row.
///
/// Rows written before the picker's bare extension was mapped to a real type
/// still carry values like `pdf`, so anything without a `/` is treated as an
/// extension and resolved through [_byExtension].
String attachmentMimeType({String? stored, required String fileName}) {
  final value = stored?.trim() ?? '';
  if (value.contains('/')) return value;
  final ext = (value.isNotEmpty ? value : fileName.split('.').last)
      .toLowerCase();
  return _byExtension[ext] ?? 'application/octet-stream';
}

const _byExtension = <String, String>{
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'svg': 'image/svg+xml',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'ics': 'text/calendar',
  'zip': 'application/zip',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
};
