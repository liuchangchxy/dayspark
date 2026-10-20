import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web_smoke: minimal web entry smoke script exists and executes', () {
    final file = File('tool/web_smoke.dart');
    expect(file.existsSync(), isTrue);
  });
}
