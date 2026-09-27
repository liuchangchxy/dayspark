import 'package:flutter/material.dart';

/// Design tokens for spacing. Matches DESIGN.md: base unit 4px,
/// every spacing value is a multiple of 4.
/// Do not use raw EdgeInsets/SizedBox/Wrap-spacing values elsewhere — import from here.
@immutable
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
