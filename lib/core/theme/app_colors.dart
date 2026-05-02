import 'package:flutter/material.dart';

/// Design tokens for app colors. Matches DESIGN.md.
/// Do not use raw Color() values elsewhere — import from here.
@immutable
abstract final class AppColors {
  // --- Light Mode ---
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightAccent = Color(0xFF2563EB);
  static const Color lightAccentHover = Color(0xFF1D4ED8);
  static const Color lightSuccess = Color(0xFF16A34A);
  static const Color lightWarning = Color(0xFFEAB308);
  static const Color lightError = Color(0xFFDC2626);
  static const Color lightBorder = Color(0xFFE5E7EB);

  // --- Dark Mode ---
  static const Color darkBackground = Color(0xFF0F0F14);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkTextPrimary = Color(0xFFE4E4E7);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkAccent = Color(0xFF60A5FA);
  static const Color darkAccentHover = Color(0xFF93C5FD);
  static const Color darkSuccess = Color(0xFF22C55E);
  static const Color darkWarning = Color(0xFFFACC15);
  static const Color darkError = Color(0xFFEF4444);
  static const Color darkBorder = Color(0xFF2D2D3A);
}
