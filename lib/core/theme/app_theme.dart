import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

/// App-wide theme configuration. Read DESIGN.md for design rationale.
@immutable
abstract final class AppTheme {
  static ThemeData light({Color? accent}) =>
      _buildTheme(Brightness.light, accent);
  static ThemeData dark({Color? accent}) =>
      _buildTheme(Brightness.dark, accent);

  static ThemeData _buildTheme(Brightness brightness, [Color? accentOverride]) {
    final isLight = brightness == Brightness.light;
    final bg = isLight ? AppColors.lightBackground : AppColors.darkBackground;
    final surface = isLight ? AppColors.lightSurface : AppColors.darkSurface;
    final surfaceSecondary = isLight
        ? AppColors.lightSurfaceSecondary
        : AppColors.darkSurfaceSecondary;
    final textPrimary = isLight
        ? AppColors.lightTextPrimary
        : AppColors.darkTextPrimary;
    final textSecondary = isLight
        ? AppColors.lightTextSecondary
        : AppColors.darkTextSecondary;
    final textTertiary = isLight
        ? AppColors.lightTextTertiary
        : AppColors.darkTextTertiary;
    final separator = isLight
        ? AppColors.lightSeparator
        : AppColors.darkSeparator;
    final error = isLight ? AppColors.lightError : AppColors.darkError;
    final success = isLight ? AppColors.lightSuccess : AppColors.darkSuccess;
    final warning = isLight ? AppColors.lightWarning : AppColors.darkWarning;

    // DESIGN 主题色条款: the preset only swaps the accent pair; every
    // semantic token is filled back from the palette. Never fromSeed.
    final accent =
        accentOverride ??
        (isLight ? AppColors.lightAccent : AppColors.darkAccent);
    final accentHover = isLight
        ? AppColors.lightAccentHover
        : AppColors.darkAccentHover;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceSecondary,
      surfaceContainerHigh: surfaceSecondary,
      outline: separator,
      outlineVariant: isLight
          ? AppColors.lightSeparatorSoft
          : AppColors.darkSeparatorSoft,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      textTheme: AppTypography.textTheme().apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      extensions: [
        AppSemanticColors(
          textSecondary: textSecondary,
          textTertiary: textTertiary,
          separator: separator,
          separatorSoft: isLight
              ? AppColors.lightSeparatorSoft
              : AppColors.darkSeparatorSoft,
          surfaceSecondary: surfaceSecondary,
          accentHover: accentHover,
          success: success,
          warning: warning,
        ),
      ],
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
      dividerTheme: DividerThemeData(color: separator, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Deliberately one step off the card surface: a field filled the same
        // colour as the card it sits in disappears.
        fillColor: surfaceSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        // Filled fields carry the shape; focus only rings them. A full-width
        // 2px accent outline on top of a filled ground reads as neon in dark
        // mode (autofocused fields land there on page open).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: accent.withValues(alpha: isLight ? 0.85 : 0.45),
            width: 1,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: textTertiary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(headerForegroundColor: Colors.white),
    );
  }
}

/// Tokens that Material's [ColorScheme] has no slot for.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.textSecondary,
    required this.textTertiary,
    required this.separator,
    required this.separatorSoft,
    required this.surfaceSecondary,
    required this.accentHover,
    required this.success,
    required this.warning,
  });

  final Color textSecondary;
  final Color textTertiary;
  final Color separator;
  final Color separatorSoft;
  final Color surfaceSecondary;
  final Color accentHover;
  final Color success;
  final Color warning;

  @override
  AppSemanticColors copyWith({
    Color? textSecondary,
    Color? textTertiary,
    Color? separator,
    Color? separatorSoft,
    Color? surfaceSecondary,
    Color? accentHover,
    Color? success,
    Color? warning,
  }) {
    return AppSemanticColors(
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      separator: separator ?? this.separator,
      separatorSoft: separatorSoft ?? this.separatorSoft,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      accentHover: accentHover ?? this.accentHover,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      separatorSoft: Color.lerp(separatorSoft, other.separatorSoft, t)!,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  /// Semantic tokens when the app theme is installed, otherwise a fallback
  /// derived from the ambient [ColorScheme] so widgets still render under a
  /// bare MaterialApp (widget tests, embedded previews).
  AppSemanticColors get semantic {
    final installed = Theme.of(this).extension<AppSemanticColors>();
    if (installed != null) return installed;
    final scheme = Theme.of(this).colorScheme;
    return AppSemanticColors(
      textSecondary: scheme.onSurfaceVariant,
      textTertiary: scheme.outline,
      separator: scheme.outlineVariant,
      separatorSoft: scheme.outlineVariant,
      surfaceSecondary: scheme.surfaceContainerHighest,
      accentHover: scheme.primary,
      success: scheme.primary,
      warning: scheme.error,
    );
  }
}
