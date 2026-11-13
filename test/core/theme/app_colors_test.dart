import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';

void main() {
  group('AppColors', () {
    test('light color tokens are non-null Color instances', () {
      expect(AppColors.lightBackground, isA<Color>());
      expect(AppColors.lightSurface, isA<Color>());
      expect(AppColors.lightTextPrimary, isA<Color>());
      expect(AppColors.lightTextSecondary, isA<Color>());
      expect(AppColors.lightAccent, isA<Color>());
      expect(AppColors.lightSuccess, isA<Color>());
      expect(AppColors.lightWarning, isA<Color>());
      expect(AppColors.lightError, isA<Color>());
      expect(AppColors.lightBorder, isA<Color>());
    });

    test('dark color tokens are non-null Color instances', () {
      expect(AppColors.darkBackground, isA<Color>());
      expect(AppColors.darkSurface, isA<Color>());
      expect(AppColors.darkTextPrimary, isA<Color>());
      expect(AppColors.darkTextSecondary, isA<Color>());
      expect(AppColors.darkAccent, isA<Color>());
      expect(AppColors.darkBorder, isA<Color>());
    });

    test('accent values match the Direction C ember', () {
      expect(AppColors.lightAccent, const Color(0xFFC2410C));
      expect(AppColors.darkAccent, const Color(0xFFE0703C));
    });

    test('light background matches Direction C #FCFCFA', () {
      expect(AppColors.lightBackground, const Color(0xFFFCFCFA));
    });

    test('dark background is #131311', () {
      expect(AppColors.darkBackground, const Color(0xFF131311));
    });
  });

  group('AppAccent presets', () {
    test('every preset carries a distinct light/dark pair', () {
      final lights = AppAccent.values.map((a) => a.light).toSet();
      final darks = AppAccent.values.map((a) => a.dark).toSet();
      expect(lights.length, AppAccent.values.length);
      expect(darks.length, AppAccent.values.length);
      for (final accent in AppAccent.values) {
        expect(accent.light, isNot(accent.dark));
      }
    });

    test('resolve follows brightness', () {
      expect(AppAccent.blue.resolve(Brightness.light), AppAccent.blue.light);
      expect(AppAccent.blue.resolve(Brightness.dark), AppAccent.blue.dark);
    });

    test('fromLegacyColor maps stored colors onto the nearest preset', () {
      expect(
        AppAccent.fromLegacyColor(const Color(0xFF007AFF).toARGB32()),
        AppAccent.blue,
      );
      expect(
        AppAccent.fromLegacyColor(const Color(0xFF34C759).toARGB32()),
        AppAccent.green,
      );
      // An unrecognized legacy color falls back to the app's own accent.
      expect(
        AppAccent.fromLegacyColor(const Color(0xFF123456).toARGB32()),
        AppAccent.terracotta,
      );
      expect(AppAccent.fromLegacyColor(null), AppAccent.terracotta);
    });

    test('fromId falls back to the app accent for unknown ids', () {
      expect(AppAccent.fromId('purple'), AppAccent.purple);
      expect(AppAccent.fromId('nope'), AppAccent.terracotta);
      expect(AppAccent.fromId(null), AppAccent.terracotta);
    });
  });
}
