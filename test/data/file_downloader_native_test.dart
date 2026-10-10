import 'package:dayspark/data/file_downloader_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloadFileWeb throws UnsupportedError on native platform', () {
    expect(
      () => downloadFileWeb(content: 'test', filename: 'test.ics'),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          'downloadFileWeb is only supported on web',
        ),
      ),
    );
  });
}
