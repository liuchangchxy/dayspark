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

    test('light tokens match the frozen spec', () {
      expect(AppColors.lightBackground, const Color(0xFFFFFFFF));
      expect(AppColors.lightSurface, const Color(0xFFFFFFFF));
      expect(AppColors.lightSurfaceSecondary, const Color(0xFFF7F7F4));
      expect(AppColors.lightFree, const Color(0xFFF7F7F4));
      expect(AppColors.lightTextPrimary, const Color(0xFF191918));
      expect(AppColors.lightTextSecondary, const Color(0xFF45453F));
      expect(AppColors.lightTextTertiary, const Color(0xFF6E6E66));
      expect(AppColors.lightTextFaint, const Color(0xFF8B8B82));
      expect(AppColors.lightSeparator, const Color(0xFFECECE6));
      expect(AppColors.lightAccent, const Color(0xFFC92A1E));
      expect(AppColors.lightAccentHover, const Color(0xFFA82318));
      expect(AppColors.lightAccentSoft, const Color(0xFFFDF3F1));
      expect(AppColors.lightAccentTint, const Color(0xFFFDF3F1));
      expect(AppColors.lightWarning, const Color(0xFF9A6A18));
      expect(AppColors.lightWarningSoft, const Color(0xFFF7EEDB));
      expect(AppColors.lightError, const Color(0xFFC92A1E));
      expect(AppColors.lightErrorSoft, const Color(0xFFFDF3F1));
      expect(AppColors.lightNavBg, const Color(0xFFFFFFFF));
      expect(AppColors.lightNavActive, const Color(0xFFF7F7F4));
      expect(AppColors.lightScrim, const Color(0x66191918));
      expect(AppColors.lightWorkBg, const Color(0xFFF1F3F4));
      expect(AppColors.lightDoneInk, const Color(0xFF8B8B82));
      expect(AppColors.lightDoneBg, const Color(0xFFF7F7F4));
      expect(AppColors.lightDoneLine, const Color(0xFFDEDED7));
    });

    test('light DsColors paints actions and selections in ink, red for danger', () {
      expect(DsColors.light.primary, AppColors.lightTextPrimary);
      expect(DsColors.light.primaryHover, AppColors.lightTextSecondary);
      expect(DsColors.light.primarySoft, AppColors.lightSurfaceSecondary);
      expect(DsColors.light.primaryTint, AppColors.lightSurfaceSecondary);
      expect(DsColors.light.onPrimary, const Color(0xFFFFFFFF));
      expect(DsColors.light.danger, AppColors.lightError);
      expect(DsColors.light.dangerSoft, AppColors.lightErrorSoft);
      expect(DsColors.light.warn, AppColors.lightWarning);
      expect(DsColors.light.warm, AppColors.lightWarning);
    });

    test('dark accent stays on its own table', () {
      expect(AppColors.darkAccent, const Color(0xFFE0703C));
    });

    test('the default presets are the spec palette', () {
      expect(AppAccent.terracotta.light, const Color(0xFFC92A1E));
      expect(AppAccent.terracotta.dark, const Color(0xFFE8695B));
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
