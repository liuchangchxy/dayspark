import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_downloader_native.dart'
    if (dart.library.js_interop) 'file_downloader_web.dart' as impl;

typedef WebFileDownloader = void Function({
  required String content,
  required String filename,
});

void downloadFileWeb({
  required String content,
  required String filename,
}) {
  impl.downloadFileWeb(content: content, filename: filename);
}

final isWebProvider = Provider<bool>((ref) => kIsWeb);

final webFileDownloaderProvider = Provider<WebFileDownloader>(
  (ref) => downloadFileWeb,
);
