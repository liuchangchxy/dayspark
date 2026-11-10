import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// App-wide theme built from the v030 design tokens.
///
/// Material chrome is a fallback here, not the design language: the product
/// surfaces (rows, chips, segments, sheets) are drawn by the widgets in
/// `lib/ui/design/`. What matters in this file is that every Material default
/// inherits paper, ink, one accent, 8px controls and 12px overlays.
@immutable
abstract final class AppTheme {
  static ThemeData light({Color? accent}) =>
      _buildTheme(DsColors.light, accent);

  static ThemeData dark({Color? accent}) =>
      _buildTheme(DsColors.dark, accent);

  static ThemeData _buildTheme(DsColors base, Color? accentOverride) {
    final ds = accentOverride == null ? base : base.withAccent(accentOverride);
    final scheme = ColorScheme(
      brightness: ds.brightness,
      primary: ds.primary,
      onPrimary: ds.onPrimary,
      primaryContainer: ds.primarySoft,
      onPrimaryContainer: ds.primary,
      secondary: ds.warm,
      onSecondary: ds.isDark ? ds.bg : Colors.white,
      secondaryContainer: ds.warmSoft,
      onSecondaryContainer: ds.warm,
      tertiary: ds.success,
      onTertiary: ds.isDark ? ds.bg : Colors.white,
      tertiaryContainer: ds.successSoft,
      onTertiaryContainer: ds.success,
      error: ds.danger,
      onError: ds.isDark ? ds.bg : Colors.white,
      errorContainer: ds.dangerSoft,
      onErrorContainer: ds.danger,
      surface: ds.surface,
      onSurface: ds.ink,
      onSurfaceVariant: ds.ink2,
      surfaceContainerLowest: ds.bg,
      surfaceContainerLow: ds.surface,
      surfaceContainer: ds.surface,
      surfaceContainerHigh: ds.surface2,
      surfaceContainerHighest: ds.surface2,
      outline: ds.line,
      outlineVariant: ds.lineSoft,
      shadow: const Color(0xFF141410),
      scrim: ds.scrim,
      inverseSurface: ds.ink,
      onInverseSurface: ds.bg,
    );

    final textTheme = AppTypography.textTheme().apply(
      bodyColor: ds.ink,
      displayColor: ds.ink,
      fontFamilyFallback: const [
        'Segoe UI',
        'SF Pro Text',
        'PingFang SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        'Noto Sans SC',
      ],
    );

    return ThemeData(
      useMaterial3: true,
      brightness: ds.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ds.bg,
      canvasColor: ds.surface,
      textTheme: textTheme,
      fontFamilyFallback: const [
        'Segoe UI',
        'SF Pro Text',
        'PingFang SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        'Noto Sans SC',
      ],
      splashFactory: InkSparkle.splashFactory,
      extensions: [ds, AppSemanticColors.fromDs(ds)],
      cardTheme: CardThemeData(
        color: ds.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.card),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ds.bg,
        foregroundColor: ds.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 54,
        titleTextStyle: AppTypography.headline.copyWith(color: ds.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        backgroundColor: ds.navBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          AppTypography.overline.copyWith(letterSpacing: 0),
        ),
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: ds.ink3, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ds.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(ds.onPrimary),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.compact,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          foregroundColor: ds.ink2,
        ),
      ),
      dividerTheme: DividerThemeData(color: ds.lineSoft, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: ds.ink2,
        textColor: ds.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        minVerticalPadding: AppSpacing.s2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ds.primary,
          foregroundColor: ds.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
          textStyle: AppTypography.bodyStrong,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ds.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: ds.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: ds.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: ds.primary),
        ),
        hintStyle: AppTypography.body.copyWith(color: ds.ink3),
        labelStyle: AppTypography.caption.copyWith(color: ds.ink2),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ds.primary,
        foregroundColor: ds.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        expansionAnimationStyle: AnimationStyle.noAnimation,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        shape: Border(),
        collapsedShape: Border(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ds.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.dialog),
        titleTextStyle: AppTypography.title.copyWith(color: ds.ink),
        contentTextStyle: AppTypography.body.copyWith(color: ds.ink2),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: ds.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: ds.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.sheetTop,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ds.primary,
          foregroundColor: ds.onPrimary,
          disabledBackgroundColor: ds.primary.withValues(alpha: 0.45),
          disabledForegroundColor: ds.onPrimary.withValues(alpha: 0.7),
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
          textStyle: AppTypography.bodyStrong,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ds.primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
          textStyle: AppTypography.bodyStrong,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ds.ink,
          side: BorderSide(color: ds.line),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
          textStyle: AppTypography.bodyStrong,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.control),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: ds.line)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ds.surface,
        selectedColor: ds.primarySoft,
        side: BorderSide(color: ds.line),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.chip),
        labelStyle: AppTypography.caption.copyWith(color: ds.ink2),
        secondaryLabelStyle: AppTypography.caption.copyWith(color: ds.primary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        elevation: 0,
        pressElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: ds.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.control,
          side: BorderSide(color: ds.line),
        ),
        textStyle: AppTypography.body.copyWith(color: ds.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ds.ink,
        contentTextStyle: AppTypography.caption.copyWith(color: ds.bg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ds.ink,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: AppTypography.small.copyWith(color: ds.bg),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ds.primary),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
        },
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: ds.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: ds.primary,
        headerForegroundColor: ds.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.dialog),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: ds.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.dialog),
      ),
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

/// Legacy token slots Material's [ColorScheme] has no home for. Populated from
/// [DsColors] so a call site written before the rewrite keeps matching the new
/// palette.
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

  factory AppSemanticColors.fromDs(DsColors ds) => AppSemanticColors(
    textSecondary: ds.ink2,
    textTertiary: ds.ink3,
    separator: ds.line,
    separatorSoft: ds.lineSoft,
    surfaceSecondary: ds.surface2,
    accentHover: ds.primaryHover,
    success: ds.success,
    warning: ds.warn,
  );

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
      surfaceSecondary: Color.lerp(
        surfaceSecondary,
        other.surfaceSecondary,
        t,
      )!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  /// The v030 token set. Falls back to the light palette under a bare
  /// MaterialApp (widget tests, embedded previews).
  DsColors get ds => Theme.of(this).extension<DsColors>() ?? DsColors.light;

  AppSemanticColors get semantic {
    final installed = Theme.of(this).extension<AppSemanticColors>();
    if (installed != null) return installed;
    return AppSemanticColors.fromDs(ds);
  }
}
