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

    test('accent values match DESIGN.md (iOS systemBlue)', () {
      expect(AppColors.lightAccent, const Color(0xFF007AFF));
      expect(AppColors.darkAccent, const Color(0xFF0A84FF));
    });

    test('light background is #F2F2F7', () {
      expect(AppColors.lightBackground, const Color(0xFFF2F2F7));
    });

    test('dark background is #0A0A0C', () {
      expect(AppColors.darkBackground, const Color(0xFF0A0A0C));
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
      // An unrecognized legacy color falls back to the default.
      expect(
        AppAccent.fromLegacyColor(const Color(0xFF123456).toARGB32()),
        AppAccent.blue,
      );
      expect(AppAccent.fromLegacyColor(null), AppAccent.blue);
    });

    test('fromId falls back to blue for unknown ids', () {
      expect(AppAccent.fromId('purple'), AppAccent.purple);
      expect(AppAccent.fromId('nope'), AppAccent.blue);
      expect(AppAccent.fromId(null), AppAccent.blue);
    });
  });
}
