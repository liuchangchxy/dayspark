import 'package:flutter/material.dart';

/// Design tokens for app colors. Matches DESIGN.md.
/// Palette is the iOS system color set, so the app never fights system chrome.
/// Do not use raw Color() values elsewhere — import from here.
@immutable
abstract final class AppColors {
  // --- Light Mode ---
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFE5E5EA);
  static const Color lightTextPrimary = Color(0xFF1C1C1E);
  static const Color lightTextSecondary = Color(0xFF8A8A8E);
  static const Color lightTextTertiary = Color(0xFFC7C7CC);
  static const Color lightAccent = Color(0xFF007AFF);
  static const Color lightAccentHover = Color(0xFF0062CC);
  static const Color lightSeparator = Color(0xFFE5E5EA);
  static const Color lightSeparatorSoft = Color(0xFFF0F0F3);
  static const Color lightSuccess = Color(0xFF34C759);
  static const Color lightWarning = Color(0xFFFF9500);
  static const Color lightError = Color(0xFFFF3B30);

  // --- Dark Mode ---
  static const Color darkBackground = Color(0xFF0A0A0C);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceSecondary = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF98989D);
  static const Color darkTextTertiary = Color(0xFF48484A);
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
