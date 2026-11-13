import 'package:flutter/material.dart';

/// v030 spacing: a 4 / 8 rhythm, eight steps.
///
/// Legacy aliases (xs…xxl) remain for call sites outside the rewritten
/// presentation; new code should use s1…s8.
@immutable
abstract final class AppSpacing {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
  static const double s8 = 40;

  static const double xs = s1;
  static const double sm = s2;
  static const double md = s3;
  static const double lg = s4;
  static const double xl = s6;
  static const double xxl = s7;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: s4);
  static const EdgeInsets desktopPage = EdgeInsets.symmetric(horizontal: s6);
}

/// v030 radii. Cards 10, fields/buttons 8, chips 6, sheets 18, dialogs 12.
@immutable
abstract final class AppRadii {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double sheet = 18;
  static const double pill = 999;

  static BorderRadius get chip => BorderRadius.circular(sm);
  static BorderRadius get control => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get dialog => BorderRadius.circular(xl);
  static BorderRadius get sheetTop => const BorderRadius.vertical(
    top: Radius.circular(AppRadii.sheet),
  );
}

/// Two shadows only: a hairline lift and an overlay.
@immutable
abstract final class AppShadows {
  static const List<BoxShadow> one = [
    BoxShadow(
      color: Color(0x0D141410),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static List<BoxShadow> two(Brightness brightness) => [
    BoxShadow(
      color: brightness == Brightness.dark
          ? const Color(0xBF000000)
          : const Color(0x66141410),
      blurRadius: brightness == Brightness.dark ? 40 : 48,
      spreadRadius: brightness == Brightness.dark ? -18 : -22,
      offset: Offset(0, 18),
    ),
  ];

  static List<BoxShadow> sheet(Brightness brightness) => [
    BoxShadow(
      color: brightness == Brightness.dark
          ? const Color(0xBF000000)
          : const Color(0x6B141410),
      blurRadius: brightness == Brightness.dark ? 36 : 32,
      spreadRadius: -20,
      offset: const Offset(0, -10),
    ),
  ];
}
