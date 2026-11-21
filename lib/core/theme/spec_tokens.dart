import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_typography.dart';

@immutable
abstract final class SpecTokens {
  static const Color ink = Color(0xFF191918);
  static const Color ink2 = Color(0xFF45453F);
  static const Color muted = Color(0xFF6E6E66);
  static const Color faint = Color(0xFF8B8B82);
  static const Color hair = Color(0xFFECECE6);
  static const Color hair2 = Color(0xFFDEDED7);
  static const Color wash = Color(0xFFF7F7F4);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color work = Color(0xFF5F7183);
  static const Color workSoft = Color(0xFFF1F3F4);
  static const Color amber = Color(0xFF9A6A18);
  static const Color amberSoft = Color(0xFFF7EEDB);
  static const Color red = Color(0xFFC92A1E);
  static const Color redSoft = Color(0xFFFDF3F1);
  static const Color scheduleBlue = Color(0xFF4F7BBF);
  static const Color scheduleBlueSoft = Color(0xFFDCE7F7);

  static const TextStyle t26 = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.01,
    color: ink,
    fontFamilyFallback: AppTypography.fallback,
  );

  static const TextStyle t20 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.005,
    color: ink,
    fontFamilyFallback: AppTypography.fallback,
  );

  static const TextStyle t15 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: ink,
    fontFamilyFallback: AppTypography.fallback,
  );

  static const TextStyle t13 = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: ink,
    fontFamilyFallback: AppTypography.fallback,
  );

  static const TextStyle t11 = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: muted,
    fontFamilyFallback: AppTypography.fallback,
  );

  static const TextStyle t95 = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.04,
    color: muted,
    fontFamilyFallback: AppTypography.fallback,
  );

  static const double r6 = 6.0;
  static const double r8 = 8.0;
  static const double r12 = 12.0;

  static const Radius radius6 = Radius.circular(6.0);
  static const Radius radius8 = Radius.circular(8.0);
  static const Radius radius12 = Radius.circular(12.0);

  static const BorderRadius borderRadius6 = BorderRadius.all(Radius.circular(6.0));
  static const BorderRadius borderRadius8 = BorderRadius.all(Radius.circular(8.0));
  static const BorderRadius borderRadius12 = BorderRadius.all(Radius.circular(12.0));

  static const double hairlineWidth = 1.0;
  static const BorderSide hairline = BorderSide(color: hair, width: 1.0);
  static const BorderSide hairline2 = BorderSide(color: hair2, width: 1.0);

  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color.fromRGBO(24, 24, 22, 0.10),
      blurRadius: 50.0,
      offset: Offset(0, 18.0),
    ),
  ];

  static const List<BoxShadow> captureShadow = [
    BoxShadow(
      color: Color.fromRGBO(25, 25, 24, 0.10),
      blurRadius: 26.0,
      offset: Offset(0, 8.0),
    ),
  ];
}
