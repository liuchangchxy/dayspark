import 'package:flutter/material.dart';

/// Design tokens for spacing and radii. Matches DESIGN.md:
/// base unit 4px / 8px rhythm.
@immutable
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  // Geometry tokens from DESIGN.md 2.2
  static const double rXs = 4;
  static const double rSm = 6;
  static const double rMd = 8;
  static const double rLg = 10;
  static const double rCard = 12;
  static const double rSheet = 18;
}
