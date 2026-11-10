import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

/// App-wide theme configuration matching DESIGN.md and VISUAL_POLISH.md.
/// Apple × Linear aesthetic: paper & ink, restrained cobalt, hairline dividers.
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
      onPrimary: isLight ? Colors.white : AppColors.darkBackground,
      secondary: accent,
      onSecondary: isLight ? Colors.white : AppColors.darkBackground,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceSecondary,
      surfaceContainerHigh: surfaceSecondary,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rLg),
          side: BorderSide(color: separatorSoft, width: 1),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title.copyWith(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 54,
        backgroundColor: isLight ? AppColors.lightNavBg : AppColors.darkNavBg,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return AppTypography.overline.copyWith(
            color: isSelected ? accent : textTertiary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? accent : textTertiary,
          );
        }),
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: textTertiary, width: 1.5),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rMd),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: separatorSoft, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isLight ? Colors.white : AppColors.darkBackground,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: AppTypography.title.copyWith(fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rMd),
          borderSide: BorderSide(color: separator, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rMd),
          borderSide: BorderSide(color: separator, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rMd),
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
        foregroundColor: isLight ? Colors.white : AppColors.darkBackground,
        shape: const CircleBorder(),
        elevation: 2,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        expansionAnimationStyle: AnimationStyle.noAnimation,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          side: BorderSide(color: separatorSoft, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.rSheet)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isLight ? Colors.white : AppColors.darkBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rMd),
          ),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: separator, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rMd),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rMd)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return surface;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return textPrimary;
            return textSecondary;
          }),
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
      datePickerTheme: DatePickerThemeData(headerForegroundColor: Colors.white),
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
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
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
      surfaceTertiary: scheme.surfaceContainerHighest,
      accentHover: scheme.primary,
      accentSoft: scheme.primary.withValues(alpha: 0.12),
      success: scheme.primary,
      warning: scheme.error,
      warm: scheme.error,
    );
  }
}
