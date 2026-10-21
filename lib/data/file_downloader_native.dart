import 'dart:typed_data';

void downloadFileWeb({
  required String content,
  required String filename,
}) {
  throw UnsupportedError('downloadFileWeb is only supported on web');
}

void downloadBytesWeb({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  throw UnsupportedError('downloadBytesWeb is only supported on web');
}
