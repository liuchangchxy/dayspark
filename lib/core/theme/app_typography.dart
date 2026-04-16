import 'package:flutter/material.dart';

/// Typography design tokens. Matches DESIGN.md.
@immutable
abstract final class AppTypography {
  static const TextStyle headline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.5,
  );

  /// Build a TextTheme from our tokens for use in ThemeData.
  static TextTheme textTheme() {
    return TextTheme(
      headlineSmall: headline,
      titleMedium: title,
      bodyLarge: body,
      bodyMedium: body.copyWith(fontSize: 14),
      labelLarge: title,
      labelMedium: caption,
      labelSmall: overline,
      bodySmall: caption,
    );
  }
}
