import 'dart:ui';

/// Shared colour-parsing helpers.
class ColorUtils {
  ColorUtils._();

  /// Parse a hex colour string like `#RRGGBB` or `RRGGBB` into a [Color].
  static Color parseHex(String hex) {
    final code = hex.replaceAll('#', '');
    return Color(int.parse('FF$code', radix: 16));
  }
}
