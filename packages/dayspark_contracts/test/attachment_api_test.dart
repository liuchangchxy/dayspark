import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('AttachmentUploadResponse', () {
    test('roundtrips through JSON', () {
      const original = AttachmentUploadResponse(
        serverFileRef: 'ref-1',
        fileSize: 4096,
      );
      final restored = AttachmentUploadResponse.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.serverFileRef, 'ref-1');
      expect(restored.fileSize, 4096);
    });

    test('rejects a missing or empty ref', () {
      expect(
        () => AttachmentUploadResponse.fromJson(const {'fileSize': 1}),
        throwsFormatException,
      );
      expect(
        () => AttachmentUploadResponse.fromJson(const {
          'serverFileRef': '',
          'fileSize': 1,
        }),
        throwsFormatException,
      );
    });

    test('rejects a negative or non-int size', () {
      expect(
        () => AttachmentUploadResponse.fromJson(const {
          'serverFileRef': 'ref-1',
          'fileSize': -1,
        }),
        throwsFormatException,
      );
      expect(
        () => AttachmentUploadResponse.fromJson(const {
          'serverFileRef': 'ref-1',
          'fileSize': '1',
        }),
        throwsFormatException,
      );
    });

    test('accepts a zero-byte size', () {
      final restored = AttachmentUploadResponse.fromJson(const {
        'serverFileRef': 'ref-1',
        'fileSize': 0,
      });
      expect(restored.fileSize, 0);
    });
  });
}
