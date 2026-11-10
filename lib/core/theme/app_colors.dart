import 'package:flutter/material.dart';

/// v030 OpenDesign palette: warm paper, ink, one muted cobalt.
///
/// Two independent palettes — dark is not a tint of light. Do not use raw
/// Color values elsewhere; import from here or read `context.ds`.
@immutable
abstract final class AppColors {
  // ---- light ----
  static const Color lightBackground = Color(0xFFF3F3EF);
  static const Color lightSurface = Color(0xFFFDFDFB);
  static const Color lightSurfaceSecondary = Color(0xFFECECE6);
  static const Color lightSurfaceTertiary = Color(0xFFDEDED6);
  static const Color lightTextPrimary = Color(0xFF1B1B18);
  static const Color lightTextSecondary = Color(0xFF56564F);
  static const Color lightTextTertiary = Color(0xFF6F6F67);
  static const Color lightSeparator = Color(0xFFE3E3DC);
  static const Color lightSeparatorSoft = Color(0xFFECECE6);
  static const Color lightAccent = Color(0xFF2D4F7C);
  static const Color lightAccentHover = Color(0xFF233F63);
  static const Color lightAccentSoft = Color(0xFFE8EDF4);
  static const Color lightWarm = Color(0xFF9C4A2F);
  static const Color lightWarmSoft = Color(0xFFF3E8E2);
  static const Color lightSuccess = Color(0xFF3D6B54);
  static const Color lightSuccessSoft = Color(0xFFE6EFE9);
  static const Color lightWarning = Color(0xFF7D5416);
  static const Color lightWarningSoft = Color(0xFFF4ECDD);
  static const Color lightError = Color(0xFFA03A32);
  static const Color lightErrorSoft = Color(0xFFF5E7E4);
  static const Color lightNavBg = Color(0xFFFAFAF7);
  static const Color lightNavActive = Color(0xFFE8EDF4);
  static const Color lightScrim = Color(0x61141410);

  // ---- dark ----
  static const Color darkBackground = Color(0xFF121310);
  static const Color darkSurface = Color(0xFF191A17);
  static const Color darkSurfaceSecondary = Color(0xFF22231F);
  static const Color darkSurfaceTertiary = Color(0xFF2D2E28);
  static const Color darkTextPrimary = Color(0xFFECECE6);
  static const Color darkTextSecondary = Color(0xFFB3B3AA);
  static const Color darkTextTertiary = Color(0xFF8B8B82);
  static const Color darkSeparator = Color(0xFF2E2F29);
  static const Color darkSeparatorSoft = Color(0xFF242520);
  static const Color darkAccent = Color(0xFF8FB0D9);
  static const Color darkAccentHover = Color(0xFFA9C5E8);
  static const Color darkAccentSoft = Color(0xFF1E2A38);
  static const Color darkWarm = Color(0xFFD08A6B);
  static const Color darkWarmSoft = Color(0xFF33221B);
  static const Color darkSuccess = Color(0xFF7FB397);
  static const Color darkSuccessSoft = Color(0xFF172B21);
  static const Color darkWarning = Color(0xFFD6AD6A);
  static const Color darkWarningSoft = Color(0xFF322817);
  static const Color darkError = Color(0xFFD6786E);
  static const Color darkErrorSoft = Color(0xFF351D1A);
  static const Color darkNavBg = Color(0xFF151612);
  static const Color darkNavActive = Color(0xFF232A31);
  static const Color darkScrim = Color(0x99000000);

  static Color onPrimary(Brightness brightness) =>
      brightness == Brightness.light ? Colors.white : darkBackground;

  // ---- legacy aliases (kept so call sites compile during the rewrite) ----
  static const Color sidebar = lightNavBg;
  static const Color sidebarSelected = lightNavActive;
  static const Color sidebarInk = lightTextPrimary;
  static const Color sidebarMuted = lightTextSecondary;
  static const Color brandWarm = lightWarm;
  static const Color lightBorder = lightSeparator;
  static const Color darkBorder = darkSeparator;
  static const Color lightDisabled = lightTextTertiary;
  static const Color darkDisabled = darkTextTertiary;
  static const Color lightSurfaceContainerHighest = lightSurfaceSecondary;
  static const Color darkSurfaceContainerHighest = darkSurfaceSecondary;

  static const Color eventWork = lightAccent;
  static const Color eventLife = lightSuccess;
  static const Color eventProduct = Color(0xFF63556F);
  static const Color eventReminder = lightWarm;

  static const Color darkEventWork = darkAccent;
  static const Color darkEventLife = darkSuccess;
  static const Color darkEventProduct = Color(0xFFB7A5C6);
  static const Color darkEventReminder = darkWarm;
}

/// The full v030 token set as a ThemeExtension, so both new UI and any
/// leftover call sites read the same palette.
@immutable
class DsColors extends ThemeExtension<DsColors> {
  const DsColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.lineSoft,
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.onPrimary,
    required this.warm,
    required this.warmSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.successSoft,
    required this.navBg,
    required this.navActive,
    required this.scrim,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color lineSoft;
  final Color primary;
  final Color primaryHover;
  final Color primarySoft;
  final Color onPrimary;
  final Color warm;
  final Color warmSoft;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;
  final Color success;
  final Color successSoft;
  final Color navBg;
  final Color navActive;
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  static const DsColors light = DsColors(
    brightness: Brightness.light,
    bg: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surface2: AppColors.lightSurfaceSecondary,
    surface3: AppColors.lightSurfaceTertiary,
    ink: AppColors.lightTextPrimary,
    ink2: AppColors.lightTextSecondary,
    ink3: AppColors.lightTextTertiary,
    line: AppColors.lightSeparator,
    lineSoft: AppColors.lightSeparatorSoft,
    primary: AppColors.lightAccent,
    primaryHover: AppColors.lightAccentHover,
    primarySoft: AppColors.lightAccentSoft,
    onPrimary: Colors.white,
    warm: AppColors.lightWarm,
    warmSoft: AppColors.lightWarmSoft,
    warn: AppColors.lightWarning,
    warnSoft: AppColors.lightWarningSoft,
    danger: AppColors.lightError,
    dangerSoft: AppColors.lightErrorSoft,
    success: AppColors.lightSuccess,
    successSoft: AppColors.lightSuccessSoft,
    navBg: AppColors.lightNavBg,
    navActive: AppColors.lightNavActive,
    scrim: AppColors.lightScrim,
  );

  static const DsColors dark = DsColors(
    brightness: Brightness.dark,
    bg: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surface2: AppColors.darkSurfaceSecondary,
    surface3: AppColors.darkSurfaceTertiary,
    ink: AppColors.darkTextPrimary,
    ink2: AppColors.darkTextSecondary,
    ink3: AppColors.darkTextTertiary,
    line: AppColors.darkSeparator,
    lineSoft: AppColors.darkSeparatorSoft,
    primary: AppColors.darkAccent,
    primaryHover: AppColors.darkAccentHover,
    primarySoft: AppColors.darkAccentSoft,
    onPrimary: AppColors.darkBackground,
    warm: AppColors.darkWarm,
    warmSoft: AppColors.darkWarmSoft,
    warn: AppColors.darkWarning,
    warnSoft: AppColors.darkWarningSoft,
    danger: AppColors.darkError,
    dangerSoft: AppColors.darkErrorSoft,
    success: AppColors.darkSuccess,
    successSoft: AppColors.darkSuccessSoft,
    navBg: AppColors.darkNavBg,
    navActive: AppColors.darkNavActive,
    scrim: AppColors.darkScrim,
  );

  /// A calendar colour laid over the surface at the design's 11% / 17% mix.
  Color tint(Color calendarColor) => Color.alphaBlend(
    calendarColor.withValues(alpha: isDark ? 0.17 : 0.11),
    surface,
  );

  /// Dark mode lifts a calendar hue so it stays legible on a dark ground.
  Color eventAccent(Color calendarColor) => isDark
      ? Color.lerp(calendarColor, Colors.white, 0.42)!
      : calendarColor;

  @override
  DsColors copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? line,
    Color? lineSoft,
    Color? primary,
    Color? primaryHover,
    Color? primarySoft,
    Color? onPrimary,
    Color? warm,
    Color? warmSoft,
    Color? warn,
    Color? warnSoft,
    Color? danger,
    Color? dangerSoft,
    Color? success,
    Color? successSoft,
    Color? navBg,
    Color? navActive,
    Color? scrim,
  }) {
    return DsColors(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimary: onPrimary ?? this.onPrimary,
      warm: warm ?? this.warm,
      warmSoft: warmSoft ?? this.warmSoft,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      navBg: navBg ?? this.navBg,
      navActive: navActive ?? this.navActive,
      scrim: scrim ?? this.scrim,
    );
  }

  /// Preset accents swap only the accent pair; the rest stays paper + ink.
  DsColors withAccent(Color accent) => copyWith(
    primary: accent,
    primaryHover: Color.lerp(accent, isDark ? Colors.white : Colors.black, 0.14)!,
    primarySoft: Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.22 : 0.10),
      surface,
    ),
    onPrimary: accent.computeLuminance() > 0.5
        ? const Color(0xFF0D141D)
        : Colors.white,
    navActive: Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.22 : 0.10),
      navBg,
    ),
  );

  @override
  DsColors lerp(DsColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DsColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      ink3: l(ink3, other.ink3),
      line: l(line, other.line),
      lineSoft: l(lineSoft, other.lineSoft),
      primary: l(primary, other.primary),
      primaryHover: l(primaryHover, other.primaryHover),
      primarySoft: l(primarySoft, other.primarySoft),
      onPrimary: l(onPrimary, other.onPrimary),
      warm: l(warm, other.warm),
      warmSoft: l(warmSoft, other.warmSoft),
      warn: l(warn, other.warn),
      warnSoft: l(warnSoft, other.warnSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      navBg: l(navBg, other.navBg),
      navActive: l(navActive, other.navActive),
      scrim: l(scrim, other.scrim),
    );
  }
}
