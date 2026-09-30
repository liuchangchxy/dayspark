import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

void main() {
  group('AppTheme', () {
    test('light theme is a valid ThemeData with light brightness', () {
      final theme = AppTheme.light();
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme is a valid ThemeData with dark brightness', () {
      final theme = AppTheme.dark();
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.dark);
    });

    test('light theme body font size matches the body token', () {
      expect(
        AppTheme.light().textTheme.bodyLarge?.fontSize,
        AppTypography.body.fontSize,
      );
    });

    test('light theme headline font size is 20', () {
      expect(AppTheme.light().textTheme.headlineSmall?.fontSize, 20);
    });

    test('display-to-body ratio stays at or above 1.7x', () {
      final ratio =
          AppTypography.display.fontSize! / AppTypography.body.fontSize!;
      expect(ratio, greaterThanOrEqualTo(1.7));
    });

    test('card border radius is 16px', () {
      final theme = AppTheme.light();
      final shape = theme.cardTheme.shape as RoundedRectangleBorder?;
      final borderRadius = shape?.borderRadius as BorderRadius?;
      expect(borderRadius?.topLeft.x, 16);
    });

    test('accent override replaces only the accent pair', () {
      final theme = AppTheme.light(accent: AppColors.lightSuccess);
      expect(theme.colorScheme.primary, AppColors.lightSuccess);
      // Semantic tokens stay on the palette rather than being derived.
      expect(theme.colorScheme.error, AppColors.lightError);
      expect(theme.colorScheme.surface, AppColors.lightSurface);
    });

    test('semantic extension is present on both themes', () {
      expect(AppTheme.light().extension<AppSemanticColors>(), isNotNull);
      expect(AppTheme.dark().extension<AppSemanticColors>(), isNotNull);
    });
  });
}
