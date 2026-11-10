import 'package:flutter/material.dart';

/// Typography design tokens. Matches DESIGN.md (2.3) and VISUAL_POLISH.md.
/// Apple × Linear utilitarian typography:
/// 3 weights (400, 500, 600), zero negative letter spacing for CJK, controlled line-heights.
@immutable
abstract final class AppTypography {
  static const TextStyle display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.6,
    letterSpacing: 0,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.3,
  );

  /// Build a TextTheme from our tokens for use in ThemeData.
  static TextTheme textTheme() {
    return const TextTheme(
      displaySmall: display,
      headlineSmall: headline,
      titleLarge: title,
      titleMedium: title,
      titleSmall: title,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: title,
      labelMedium: caption,
      labelSmall: overline,
    );
  }
}
