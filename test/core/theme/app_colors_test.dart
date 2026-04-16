import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';

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

    test('accent values match DESIGN.md', () {
      expect(AppColors.lightAccent, const Color(0xFF2563EB));
      expect(AppColors.darkAccent, const Color(0xFF3B82F6));
    });

    test('light background is #FAFAFA', () {
      expect(AppColors.lightBackground, const Color(0xFFFAFAFA));
    });

    test('dark background is #0F0F14', () {
      expect(AppColors.darkBackground, const Color(0xFF0F0F14));
    });
  });
}
