import 'package:flutter/material.dart';

/// v030 type scale: 11 / 12 / 13 / 15 / 17 / 20 / 24 / 26, three weights only.
///
/// The display-to-body ratio (26 / 15) carries the page hierarchy; weights
/// stop at 600 — 700 reads as marketing, not as an app.
@immutable
abstract final class AppTypography {
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Carried by every style, not only by the theme: a `ButtonStyle.textStyle`
  /// replaces the inherited style instead of merging with it, so a button
  /// given one of these styles would otherwise lose the chain and render
  /// Chinese as boxes on any platform whose default face has no CJK.
  static const List<String> fallback = [
    'Segoe UI',
    'SF Pro Text',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans SC',
  ];

  static const TextStyle display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0,
    fontFamilyFallback: fallback,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    fontFamilyFallback: fallback,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    fontFamilyFallback: fallback,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0,
    fontFamilyFallback: fallback,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    fontFamilyFallback: fallback,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.45,
    fontFamilyFallback: fallback,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    fontFamilyFallback: fallback,
  );

  static const TextStyle small = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    fontFamilyFallback: fallback,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.44,
    fontFamilyFallback: fallback,
  );

  static TextTheme textTheme() {
    return TextTheme(
      displaySmall: display,
      headlineSmall: headline,
      headlineMedium: pageTitle,
      titleLarge: title,
      titleMedium: bodyStrong,
      titleSmall: bodyStrong,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: bodyStrong,
      labelMedium: caption,
      labelSmall: overline,
    );
  }
}
