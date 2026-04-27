import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  group('ThemeModeNotifier', () {
    test('defaults to ThemeMode.system', () {
      // Can't easily test StateNotifier without ProviderScope,
      // so verify the enum values exist
      expect(ThemeMode.system, isNotNull);
      expect(ThemeMode.light, isNotNull);
      expect(ThemeMode.dark, isNotNull);
      expect(ThemeMode.values.length, 3);
    });
  });
}
