import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

/// App-wide theme configuration. Read DESIGN.md for design rationale.
@immutable
abstract final class AppTheme {
  static ThemeData light({Color? seedColor}) =>
      _buildTheme(Brightness.light, seedColor);
  static ThemeData dark({Color? seedColor}) =>
      _buildTheme(Brightness.dark, seedColor);

  static ThemeData _buildTheme(Brightness brightness, [Color? seedColor]) {
    final isLight = brightness == Brightness.light;
    final bg = isLight ? AppColors.lightBackground : AppColors.darkBackground;
    final surface = isLight ? AppColors.lightSurface : AppColors.darkSurface;
    final textPrimary = isLight
        ? AppColors.lightTextPrimary
        : AppColors.darkTextPrimary;
    final textSecondary = isLight
        ? AppColors.lightTextSecondary
        : AppColors.darkTextSecondary;
    final accent = isLight ? AppColors.lightAccent : AppColors.darkAccent;
    final border = isLight ? AppColors.lightBorder : AppColors.darkBorder;
    final error = isLight ? AppColors.lightError : AppColors.darkError;

    final ColorScheme colorScheme;
    if (seedColor != null) {
      // Seed replaces accent only; semantic tokens stay (DESIGN 自定义主题色条款).
      colorScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ).copyWith(
        error: error,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: isLight
            ? AppColors.lightSurfaceContainerHighest
            : AppColors.darkSurfaceContainerHighest,
      );
    } else {
      colorScheme = ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: isLight
            ? AppColors.lightSurfaceContainerHighest
            : AppColors.darkSurfaceContainerHighest,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      textTheme: AppTypography.textTheme().apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: 1),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: textSecondary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(headerForegroundColor: Colors.white),
    );
  }
}
