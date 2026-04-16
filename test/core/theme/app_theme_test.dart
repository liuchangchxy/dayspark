import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme is a valid ThemeData with light brightness', () {
      final theme = AppTheme.light;
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme is a valid ThemeData with dark brightness', () {
      final theme = AppTheme.dark;
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.dark);
    });

    test('light theme body font size is 14', () {
      expect(AppTheme.light.textTheme.bodyLarge?.fontSize, 14);
    });

    test('light theme headline font size is 20', () {
      expect(AppTheme.light.textTheme.headlineSmall?.fontSize, 20);
    });

    test('card border radius is 8px', () {
      final theme = AppTheme.light;
      final shape = theme.cardTheme.shape as RoundedRectangleBorder?;
      final borderRadius = shape?.borderRadius as BorderRadius?;
      expect(borderRadius?.topLeft.x, 8);
    });
  });
}
