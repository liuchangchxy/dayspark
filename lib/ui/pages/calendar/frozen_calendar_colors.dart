import 'package:flutter/material.dart';

/// Authoritative 6 muted calendar & tag colors from docs/design/frozen/dayspark-spec.html:
/// CAL:
/// personal: color: '#8a8a82', bg: '#efefea', ink: '#3b3b33'
/// work:     color: '#4f7bbf', bg: '#dce7f7', ink: '#1e3557'
/// home:     color: '#a98b4f', bg: '#f2ebdd', ink: '#4a3c22'
/// health:   color: '#c4794a', bg: '#f7dcc8', ink: '#5e2f13'
/// life:     color: '#6a9464', bg: '#dcead8', ink: '#2a4029'
/// study:    color: '#6c6fa8', bg: '#e5e5f4', ink: '#33345a'
class FrozenPalette {
  const FrozenPalette._();

  static const List<String> hexColors = [
    '#4F7BBF', // work / blue
    '#6A9464', // life / green
    '#C4794A', // health / orange
    '#6C6FA8', // study / purple
    '#A98B4F', // home / amber-gold
    '#8A8A82', // personal / muted-gray
  ];

  static const Map<String, ({Color color, Color bg, Color ink})> definitions = {
    '#4F7BBF': (
      color: Color(0xFF4F7BBF),
      bg: Color(0xFFDCE7F7),
      ink: Color(0xFF1E3557),
    ),
    '#6A9464': (
      color: Color(0xFF6A9464),
      bg: Color(0xFFDCEAD8),
      ink: Color(0xFF2A4029),
    ),
    '#C4794A': (
      color: Color(0xFFC4794A),
      bg: Color(0xFFF7DCC8),
      ink: Color(0xFF5E2F13),
    ),
    '#6C6FA8': (
      color: Color(0xFF6C6FA8),
      bg: Color(0xFFE5E5F4),
      ink: Color(0xFF33345A),
    ),
    '#A98B4F': (
      color: Color(0xFFA98B4F),
      bg: Color(0xFFF2EBDD),
      ink: Color(0xFF4A3C22),
    ),
    '#8A8A82': (
      color: Color(0xFF8A8A82),
      bg: Color(0xFFEFEFEA),
      ink: Color(0xFF3B3B33),
    ),
  };
}
