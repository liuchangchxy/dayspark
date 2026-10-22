import 'package:flutter/material.dart';

/// Design tokens for app colors. Matches DESIGN.md.
/// Palette is the iOS system color set, so the app never fights system chrome.
/// Do not use raw Color() values elsewhere — import from here.
@immutable
abstract final class AppColors {
  static const Color sidebar = Color(0xFF191C22);
  static const Color sidebarSelected = Color(0xFF242933);
  static const Color sidebarInk = Color(0xFFE9ECF1);
  static const Color sidebarMuted = Color(0xFFADB5C3);
  static const Color brandWarm = Color(0xFFC2410C);

  // --- Light Mode ---
  static const Color lightBackground = Color(0xFFF5F6F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFE3E6EB);
  static const Color lightTextPrimary = Color(0xFF171A20);
  static const Color lightTextSecondary = Color(0xFF667080);
  static const Color lightTextTertiary = Color(0xFF667080);
  static const Color lightAccent = Color(0xFF2457D6);
  static const Color lightAccentHover = Color(0xFF1947BA);
  static const Color lightSeparator = Color(0xFFE3E6EB);
  static const Color lightSeparatorSoft = Color(0xFFEEF0F3);
  static const Color lightSuccess = Color(0xFF2F7D5A);
  static const Color lightWarning = Color(0xFFA95D08);
  static const Color lightError = Color(0xFFBF3A32);

  // --- Dark Mode ---
  static const Color darkBackground = Color(0xFF0A0A0C);
  static const Color darkSurface = Color(0xFF171A20);
  static const Color darkSurfaceSecondary = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFADB5C3);
  static const Color darkTextTertiary = Color(0xFF858F9F);
  static const Color darkAccent = Color(0xFF0A84FF);
  static const Color darkAccentHover = Color(0xFF409CFF);
  static const Color darkSeparator = Color(0xFF38383A);
  static const Color darkSeparatorSoft = Color(0xFF2A2A2C);
  static const Color darkSuccess = Color(0xFF30D158);
  static const Color darkWarning = Color(0xFFFF9F0A);
  static const Color darkError = Color(0xFFFF453A);

  // --- Aliases kept for existing call sites ---
  static const Color lightBorder = lightSeparator;
  static const Color darkBorder = darkSeparator;
  static const Color lightDisabled = lightTextTertiary;
  static const Color darkDisabled = darkTextTertiary;
  static const Color lightSurfaceContainerHighest = lightSurfaceSecondary;
  static const Color darkSurfaceContainerHighest = darkSurfaceSecondary;

  /// Calendar event colors, keyed by category.
  static const Color eventWork = lightAccent;
  static const Color eventLife = lightSuccess;
  static const Color eventProduct = Color(0xFFAF52DE);
  static const Color eventReminder = lightWarning;

  static const Color darkEventWork = darkAccent;
  static const Color darkEventLife = darkSuccess;
  static const Color darkEventProduct = Color(0xFFBF5AF2);
  static const Color darkEventReminder = darkWarning;
}
