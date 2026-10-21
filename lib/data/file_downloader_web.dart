import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void downloadFileWeb({
  required String content,
  required String filename,
}) {
  downloadBytesWeb(
    bytes: Uint8List.fromList(utf8.encode(content)),
    filename: filename,
    mimeType: 'text/calendar;charset=utf-8',
  );
}

void downloadBytesWeb({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
