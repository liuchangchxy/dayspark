import 'dart:ui';

/// Shared colour-parsing helpers.
class ColorUtils {
  ColorUtils._();

  static const Color _fallback = Color(0xFF2563EB);

  static Color parseHex(String hex) {
    final code = hex.replaceAll('#', '');
    if (code.length != 6) return _fallback;
    final value = int.tryParse('FF$code', radix: 16);
    if (value == null) return _fallback;
    return Color(value);
  }
}
