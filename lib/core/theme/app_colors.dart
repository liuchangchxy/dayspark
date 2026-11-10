import 'package:flutter/material.dart';

/// Design tokens for app colors. Matches v030-v2 OpenDesign & tokens.css.
/// Apple × Linear aesthetic: warm paper, ink, muted cobalt, semantic warm/warn/danger/success.
@immutable
abstract final class AppColors {
  // --- Brand & Sidebar (Desktop) ---
  static const Color sidebar = Color(0xFF151612);
  static const Color sidebarSelected = Color(0xFF22231F);
  static const Color sidebarInk = Color(0xFFECECE6);
  static const Color sidebarMuted = Color(0xFF8B8B82);
  static const Color brandWarm = Color(0xFF9C4A2F);

  // --- Light Mode (Warm Paper & Ink) ---
  static const Color lightBackground = Color(0xFFF3F3EF);
  static const Color lightSurface = Color(0xFFFDFDFB);
  static const Color lightSurfaceSecondary = Color(0xFFECECE6);
  static const Color lightSurfaceTertiary = Color(0xFFDEDED6);
  static const Color lightTextPrimary = Color(0xFF1B1B18);
  static const Color lightTextSecondary = Color(0xFF56564F);
  static const Color lightTextTertiary = Color(0xFF6F6F67);
  static const Color lightAccent = Color(0xFF2D4F7C);
  static const Color lightAccentHover = Color(0xFF233F63);
  static const Color lightAccentSoft = Color(0xFFE8EDF4);
  static const Color lightSeparator = Color(0xFFE3E3DC);
  static const Color lightSeparatorSoft = Color(0xFFECECE6);
  static const Color lightSuccess = Color(0xFF3D6B54);
  static const Color lightSuccessSoft = Color(0xFFE6EFE9);
  static const Color lightWarning = Color(0xFF7D5416);
  static const Color lightWarningSoft = Color(0xFFF4ECDD);
  static const Color lightError = Color(0xFFA03A32);
  static const Color lightErrorSoft = Color(0xFFF5E7E4);
  static const Color lightWarm = Color(0xFF9C4A2F);
  static const Color lightWarmSoft = Color(0xFFF3E8E2);

  // --- Dark Mode (Warm Black & Muted Accents) ---
  static const Color darkBackground = Color(0xFF121310);
  static const Color darkSurface = Color(0xFF191A17);
  static const Color darkSurfaceSecondary = Color(0xFF22231F);
  static const Color darkSurfaceTertiary = Color(0xFF2D2E28);
  static const Color darkTextPrimary = Color(0xFFECECE6);
  static const Color darkTextSecondary = Color(0xFFB3B3AA);
  static const Color darkTextTertiary = Color(0xFF8B8B82);
  static const Color darkAccent = Color(0xFF8FB0D9);
  static const Color darkAccentHover = Color(0xFFA9C5E8);
  static const Color darkAccentSoft = Color(0xFF1E2A38);
  static const Color darkSeparator = Color(0xFF2E2F29);
  static const Color darkSeparatorSoft = Color(0xFF242520);
  static const Color darkSuccess = Color(0xFF7FB397);
  static const Color darkSuccessSoft = Color(0xFF172B21);
  static const Color darkWarning = Color(0xFFD6AD6A);
  static const Color darkWarningSoft = Color(0xFF322817);
  static const Color darkError = Color(0xFFD6786E);
  static const Color darkErrorSoft = Color(0xFF351D1A);
  static const Color darkWarm = Color(0xFFD08A6B);
  static const Color darkWarmSoft = Color(0xFF33221B);

  // --- Aliases kept for existing call sites ---
  static const Color lightBorder = lightSeparator;
  static const Color darkBorder = darkSeparator;
  static const Color lightDisabled = lightTextTertiary;
  static const Color darkDisabled = darkTextTertiary;
  static const Color lightSurfaceContainerHighest = lightSurfaceSecondary;
  static const Color darkSurfaceContainerHighest = darkSurfaceSecondary;

  /// Calendar event colors, muted per v030 tokens
  static const Color eventWork = Color(0xFF6F5D7E);
  static const Color eventLife = Color(0xFF9A6248);
  static const Color eventProduct = Color(0xFF4F6D8C);
  static const Color eventStudy = Color(0xFF4F7368);
  static const Color eventRose = Color(0xFF8F5A68);
  static const Color eventOlive = Color(0xFF6B7048);
  static const Color eventReminder = lightWarning;

  static const Color darkEventWork = Color(0xFF8E7A9F);
  static const Color darkEventLife = Color(0xFFB87C5E);
  static const Color darkEventProduct = Color(0xFF6D90B8);
  static const Color darkEventStudy = Color(0xFF6F998C);
  static const Color darkEventRose = Color(0xFFAF7485);
  static const Color darkEventOlive = Color(0xFF8A9060);
  static const Color darkEventReminder = darkWarning;
}
