import 'package:flutter/material.dart';

/// Typography design tokens. Matches DESIGN.md.
///
/// The display-to-body ratio (26 / 15) is what carries the page hierarchy;
/// keep it at 1.7x or more when changing these sizes.
@immutable
abstract final class AppTypography {
  static const TextStyle display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.12,
    letterSpacing: -0.5,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.3,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.2,
  );

  /// Build a TextTheme from our tokens for use in ThemeData.
  static TextTheme textTheme() {
    return TextTheme(
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
