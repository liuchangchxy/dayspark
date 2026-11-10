import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

/// App-wide theme configuration. Read DESIGN.md & VISUAL_POLISH.md for design rationale.
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
    final surfaceTertiary = isLight
        ? AppColors.lightSurfaceTertiary
        : AppColors.darkSurfaceTertiary;
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
    final separatorSoft = isLight
        ? AppColors.lightSeparatorSoft
        : AppColors.darkSeparatorSoft;
    final error = isLight ? AppColors.lightError : AppColors.darkError;
    final success = isLight ? AppColors.lightSuccess : AppColors.darkSuccess;
    final warning = isLight ? AppColors.lightWarning : AppColors.darkWarning;
    final warm = isLight ? AppColors.lightWarm : AppColors.darkWarm;

    final accent =
        accentOverride ??
        (isLight ? AppColors.lightAccent : AppColors.darkAccent);
    final accentHover = isLight
        ? AppColors.lightAccentHover
        : AppColors.darkAccentHover;
    final accentSoft = isLight
        ? AppColors.lightAccentSoft
        : AppColors.darkAccentSoft;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: isLight ? Colors.white : const Color(0xFF0D141D),
      secondary: accent,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceSecondary,
      surfaceContainerHigh: surfaceSecondary,
      surfaceContainer: surfaceSecondary,
      outline: separator,
      outlineVariant: separatorSoft,
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
          separatorSoft: separatorSoft,
          surfaceSecondary: surfaceSecondary,
          surfaceTertiary: surfaceTertiary,
          accentHover: accentHover,
          accentSoft: accentSoft,
          success: success,
          warning: warning,
          warm: warm,
        ),
      ],
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTypography.title.copyWith(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: isLight ? const Color(0xFFFAFAF7) : const Color(0xFF151612),
        indicatorColor: accentSoft,
        labelTextStyle: WidgetStatePropertyAll(AppTypography.overline),
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: textTertiary, width: 1.8),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: textSecondary,
        ),
      ),
      dividerTheme: DividerThemeData(color: separatorSoft, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isLight ? Colors.white : const Color(0xFF0D141D),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: textTertiary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: isLight ? Colors.white : const Color(0xFF0D141D),
        shape: const CircleBorder(),
        elevation: 2,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        expansionAnimationStyle: AnimationStyle.noAnimation,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: BorderSide(color: separator),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return surface;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return textPrimary;
            }
            return textSecondary;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
        },
      ),
      datePickerTheme: const DatePickerThemeData(headerForegroundColor: Colors.white),
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
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
    required this.surfaceTertiary,
    required this.accentHover,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.warm,
  });

  final Color textSecondary;
  final Color textTertiary;
  final Color separator;
  final Color separatorSoft;
  final Color surfaceSecondary;
  final Color surfaceTertiary;
  final Color accentHover;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color warm;

  @override
  AppSemanticColors copyWith({
    Color? textSecondary,
    Color? textTertiary,
    Color? separator,
    Color? separatorSoft,
    Color? surfaceSecondary,
    Color? surfaceTertiary,
    Color? accentHover,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? warm,
  }) {
    return AppSemanticColors(
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      separator: separator ?? this.separator,
      separatorSoft: separatorSoft ?? this.separatorSoft,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceTertiary: surfaceTertiary ?? this.surfaceTertiary,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warm: warm ?? this.warm,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      separatorSoft: Color.lerp(separatorSoft, other.separatorSoft, t)!,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      surfaceTertiary: Color.lerp(surfaceTertiary, other.surfaceTertiary, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>() ??
      const AppSemanticColors(
        textSecondary: AppColors.lightTextSecondary,
        textTertiary: AppColors.lightTextTertiary,
        separator: AppColors.lightSeparator,
        separatorSoft: AppColors.lightSeparatorSoft,
        surfaceSecondary: AppColors.lightSurfaceSecondary,
        surfaceTertiary: AppColors.lightSurfaceTertiary,
        accentHover: AppColors.lightAccentHover,
        accentSoft: AppColors.lightAccentSoft,
        success: AppColors.lightSuccess,
        warning: AppColors.lightWarning,
        warm: AppColors.lightWarm,
      );

  AppSemanticColors get semanticColors => semantic;
}
