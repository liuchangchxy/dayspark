import 'package:flutter/material.dart';

/// Direction C · Time-first palette: warm paper, near-black ink, one rust accent.
///
/// Two independent palettes — dark is not a tint of light. Do not use raw
/// Color values elsewhere; import from here or read `context.ds`.
@immutable
abstract final class AppColors {
  // ---- light ----
  static const Color lightBackground = Color(0xFFFCFCFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFF7F7F2);
  static const Color lightSurfaceTertiary = Color(0xFFF0EFE9);
  static const Color lightFree = Color(0xFFF5F4EE);
  static const Color lightTextPrimary = Color(0xFF191A17);
  static const Color lightTextSecondary = Color(0xFF3F413A);
  // Secondary and tertiary text carry real copy, so both clear WCAG AA on every
  // surface they land on: tertiary was #787B72, which measured 4.19:1 on the
  // page, 4.01:1 on the secondary surface and 3.74:1 on the tertiary one.
  static const Color lightTextTertiary = Color(0xFF6A6D64);
  // Faint is for placeholders and disabled marks rather than body copy, so it
  // holds the 3:1 non-text threshold instead of the 4.5:1 one.
  static const Color lightTextFaint = Color(0xFF85887D);
  static const Color lightSeparator = Color(0xFFE8E7E1);
  static const Color lightSeparatorSoft = Color(0xFFF0EFE9);
  static const Color lightAccent = Color(0xFFC2410C);
  static const Color lightAccentHover = Color(0xFF9A330A);
  static const Color lightAccentSoft = Color(0xFFFBEEE7);
  static const Color lightAccentTint = Color(0xFFFDF4EF);
  static const Color lightWarm = Color(0xFF8A7B5F);
  static const Color lightWarmSoft = Color(0xFFF8F5EE);
  static const Color lightSuccess = Color(0xFF5E7A64);
  static const Color lightSuccessSoft = Color(0xFFF1F5F1);
  static const Color lightWarning = Color(0xFF7D5416);
  static const Color lightWarningSoft = Color(0xFFF4ECDD);
  static const Color lightError = Color(0xFFA8481E);
  static const Color lightErrorSoft = Color(0xFFFBF1EB);
  static const Color lightNavBg = Color(0xFFFCFCFA);
  static const Color lightNavActive = Color(0xFFFBEEE7);
  static const Color lightScrim = Color(0x66191A17);
  static const Color lightWork = Color(0xFF5F7183);
  static const Color lightWorkBg = Color(0xFFF3F5F6);
  static const Color lightDoneInk = Color(0xFFA5A79D);
  static const Color lightDoneBg = Color(0xFFF7F7F2);
  static const Color lightDoneLine = Color(0xFFDEDDD5);

  // ---- dark ----
  static const Color darkBackground = Color(0xFF131311);
  static const Color darkSurface = Color(0xFF1A1B18);
  static const Color darkSurfaceSecondary = Color(0xFF1D1E1A);
  static const Color darkSurfaceTertiary = Color(0xFF232420);
  static const Color darkFree = Color(0xFF20211C);
  static const Color darkTextPrimary = Color(0xFFECECE6);
  static const Color darkTextSecondary = Color(0xFFB9BAB1);
  static const Color darkTextTertiary = Color(0xFF8E9087);
  static const Color darkTextFaint = Color(0xFF6E7069);
  static const Color darkSeparator = Color(0xFF2C2D28);
  static const Color darkSeparatorSoft = Color(0xFF232420);
  static const Color darkAccent = Color(0xFFE0703C);
  static const Color darkAccentHover = Color(0xFFF08A55);
  static const Color darkAccentSoft = Color(0xFF33211A);
  static const Color darkAccentTint = Color(0xFF2A1C15);
  static const Color darkWarm = Color(0xFFBFAE8D);
  static const Color darkWarmSoft = Color(0xFF24211A);
  static const Color darkSuccess = Color(0xFF8FAE96);
  static const Color darkSuccessSoft = Color(0xFF1B221C);
  static const Color darkWarning = Color(0xFFD6AD6A);
  static const Color darkWarningSoft = Color(0xFF322817);
  static const Color darkError = Color(0xFFD97B52);
  static const Color darkErrorSoft = Color(0xFF33201A);
  static const Color darkNavBg = Color(0xFF131311);
  static const Color darkNavActive = Color(0xFF33211A);
  static const Color darkScrim = Color(0xB3000000);
  static const Color darkWork = Color(0xFF8FA2B5);
  static const Color darkWorkBg = Color(0xFF1C2024);
  static const Color darkDoneInk = Color(0xFF6E7069);
  static const Color darkDoneBg = Color(0xFF1D1E1A);
  static const Color darkDoneLine = Color(0xFF34352F);

  static Color onPrimary(Brightness brightness) => Colors.white;

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

  static const Color eventWork = lightWork;
  static const Color eventLife = lightSuccess;
  static const Color eventProduct = Color(0xFF8A7B5F);
  static const Color eventReminder = lightWarm;

  static const Color darkEventWork = darkWork;
  static const Color darkEventLife = darkSuccess;
  static const Color darkEventProduct = Color(0xFFBFAE8D);
  static const Color darkEventReminder = darkWarm;
}

/// The full Direction C token set as a ThemeExtension, so both new UI and any
/// leftover call sites read the same palette.
@immutable
class DsColors extends ThemeExtension<DsColors> {
  const DsColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.free,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.faint,
    required this.line,
    required this.lineSoft,
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.primaryTint,
    required this.onPrimary,
    required this.warm,
    required this.warmSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.successSoft,
    required this.work,
    required this.workBg,
    required this.doneInk,
    required this.doneBg,
    required this.doneLine,
    required this.navBg,
    required this.navActive,
    required this.scrim,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color free;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color faint;
  final Color line;
  final Color lineSoft;
  final Color primary;
  final Color primaryHover;
  final Color primarySoft;
  final Color primaryTint;
  final Color onPrimary;
  final Color warm;
  final Color warmSoft;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;
  final Color success;
  final Color successSoft;
  final Color work;
  final Color workBg;
  final Color doneInk;
  final Color doneBg;
  final Color doneLine;
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
    free: AppColors.lightFree,
    ink: AppColors.lightTextPrimary,
    ink2: AppColors.lightTextSecondary,
    ink3: AppColors.lightTextTertiary,
    faint: AppColors.lightTextFaint,
    line: AppColors.lightSeparator,
    lineSoft: AppColors.lightSeparatorSoft,
    primary: AppColors.lightAccent,
    primaryHover: AppColors.lightAccentHover,
    primarySoft: AppColors.lightAccentSoft,
    primaryTint: AppColors.lightAccentTint,
    onPrimary: Colors.white,
    warm: AppColors.lightWarm,
    warmSoft: AppColors.lightWarmSoft,
    warn: AppColors.lightWarning,
    warnSoft: AppColors.lightWarningSoft,
    danger: AppColors.lightError,
    dangerSoft: AppColors.lightErrorSoft,
    success: AppColors.lightSuccess,
    successSoft: AppColors.lightSuccessSoft,
    work: AppColors.lightWork,
    workBg: AppColors.lightWorkBg,
    doneInk: AppColors.lightDoneInk,
    doneBg: AppColors.lightDoneBg,
    doneLine: AppColors.lightDoneLine,
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
    free: AppColors.darkFree,
    ink: AppColors.darkTextPrimary,
    ink2: AppColors.darkTextSecondary,
    ink3: AppColors.darkTextTertiary,
    faint: AppColors.darkTextFaint,
    line: AppColors.darkSeparator,
    lineSoft: AppColors.darkSeparatorSoft,
    primary: AppColors.darkAccent,
    primaryHover: AppColors.darkAccentHover,
    primarySoft: AppColors.darkAccentSoft,
    primaryTint: AppColors.darkAccentTint,
    onPrimary: Colors.white,
    warm: AppColors.darkWarm,
    warmSoft: AppColors.darkWarmSoft,
    warn: AppColors.darkWarning,
    warnSoft: AppColors.darkWarningSoft,
    danger: AppColors.darkError,
    dangerSoft: AppColors.darkErrorSoft,
    success: AppColors.darkSuccess,
    successSoft: AppColors.darkSuccessSoft,
    work: AppColors.darkWork,
    workBg: AppColors.darkWorkBg,
    doneInk: AppColors.darkDoneInk,
    doneBg: AppColors.darkDoneBg,
    doneLine: AppColors.darkDoneLine,
    navBg: AppColors.darkNavBg,
    navActive: AppColors.darkNavActive,
    scrim: AppColors.darkScrim,
  );

  /// A calendar colour laid over the surface at the design's 10% / 16% mix.
  Color tint(Color calendarColor) => Color.alphaBlend(
    calendarColor.withValues(alpha: isDark ? 0.16 : 0.10),
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
    Color? free,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? faint,
    Color? line,
    Color? lineSoft,
    Color? primary,
    Color? primaryHover,
    Color? primarySoft,
    Color? primaryTint,
    Color? onPrimary,
    Color? warm,
    Color? warmSoft,
    Color? warn,
    Color? warnSoft,
    Color? danger,
    Color? dangerSoft,
    Color? success,
    Color? successSoft,
    Color? work,
    Color? workBg,
    Color? doneInk,
    Color? doneBg,
    Color? doneLine,
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
      free: free ?? this.free,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      faint: faint ?? this.faint,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryTint: primaryTint ?? this.primaryTint,
      onPrimary: onPrimary ?? this.onPrimary,
      warm: warm ?? this.warm,
      warmSoft: warmSoft ?? this.warmSoft,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      work: work ?? this.work,
      workBg: workBg ?? this.workBg,
      doneInk: doneInk ?? this.doneInk,
      doneBg: doneBg ?? this.doneBg,
      doneLine: doneLine ?? this.doneLine,
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
    primaryTint: Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.14 : 0.06),
      surface,
    ),
    onPrimary: accent.computeLuminance() > 0.5
        ? const Color(0xFF14140F)
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
      free: l(free, other.free),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      ink3: l(ink3, other.ink3),
      faint: l(faint, other.faint),
      line: l(line, other.line),
      lineSoft: l(lineSoft, other.lineSoft),
      primary: l(primary, other.primary),
      primaryHover: l(primaryHover, other.primaryHover),
      primarySoft: l(primarySoft, other.primarySoft),
      primaryTint: l(primaryTint, other.primaryTint),
      onPrimary: l(onPrimary, other.onPrimary),
      warm: l(warm, other.warm),
      warmSoft: l(warmSoft, other.warmSoft),
      warn: l(warn, other.warn),
      warnSoft: l(warnSoft, other.warnSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      work: l(work, other.work),
      workBg: l(workBg, other.workBg),
      doneInk: l(doneInk, other.doneInk),
      doneBg: l(doneBg, other.doneBg),
      doneLine: l(doneLine, other.doneLine),
      navBg: l(navBg, other.navBg),
      navActive: l(navActive, other.navActive),
      scrim: l(scrim, other.scrim),
    );
  }
}
