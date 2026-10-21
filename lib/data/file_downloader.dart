import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_downloader_native.dart'
    if (dart.library.js_interop) 'file_downloader_web.dart' as impl;

typedef WebFileDownloader = void Function({
  required String content,
  required String filename,
});

/// Binary counterpart of [WebFileDownloader]: attachments are not text, so
/// routing them through a String would corrupt every non-UTF-8 byte.
typedef WebBytesDownloader = void Function({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
});

void downloadFileWeb({
  required String content,
  required String filename,
}) {
  impl.downloadFileWeb(content: content, filename: filename);
}

void downloadBytesWeb({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  impl.downloadBytesWeb(bytes: bytes, filename: filename, mimeType: mimeType);
}

final isWebProvider = Provider<bool>((ref) => kIsWeb);

final webFileDownloaderProvider = Provider<WebFileDownloader>(
  (ref) => downloadFileWeb,
);

final webBytesDownloaderProvider = Provider<WebBytesDownloader>(
  (ref) => downloadBytesWeb,
);
