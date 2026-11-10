import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themeModePrefKey = 'theme_mode';
const _keyThemeColor = 'theme_color';

/// The locked accent presets (DESIGN.md 2.4 / 2.5 and VISUAL_POLISH.md).
/// 6 presets matching the 6 natural calendar / brand hues.
enum AppAccent {
  blue('blue', '钴蓝', 'Blue', Color(0xFF2D4F7C), Color(0xFF8FB0D9)),
  green('green', '橄榄', 'Green', Color(0xFF4F7368), Color(0xFF7FB397)),
  orange('orange', '暖褐', 'Orange', Color(0xFF9A6248), Color(0xFFD08A6B)),
  purple('purple', '工作紫', 'Purple', Color(0xFF6F5D7E), Color(0xFFB5A4C4)),
  rose('rose', '玫红', 'Rose', Color(0xFF8F5A68), Color(0xFFD6786E)),
  study('study', '竹青', 'Teal', Color(0xFF3D6B54), Color(0xFF68B28C));

  const AppAccent(this.id, this.zhName, this.enName, this.light, this.dark);

  final String id;
  final String zhName;
  final String enName;
  final Color light;
  final Color dark;

  Color resolve(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  String nameFor(Locale locale) =>
      locale.languageCode == 'zh' ? zhName : enName;

  static AppAccent fromId(String? id) =>
      values.firstWhere((a) => a.id == id, orElse: () => AppAccent.blue);

  /// Maps a color stored by the old free-picker onto the nearest preset.
  static AppAccent fromLegacyColor(int? argb) {
    if (argb == null) return AppAccent.blue;
    final color = Color(argb);
    for (final accent in values) {
      if (accent.light == color || accent.dark == color) return accent;
    }
    return AppAccent.blue;
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(themeModePrefKey);
    if (saved != null) {
      state = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModePrefKey, mode.name);
  }
}

final themeColorProvider = StateNotifierProvider<ThemeColorNotifier, AppAccent>(
  (ref) => ThemeColorNotifier(),
);

class ThemeColorNotifier extends StateNotifier<AppAccent> {
  ThemeColorNotifier() : super(AppAccent.blue) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyThemeColor);
    if (saved != null) {
      state = AppAccent.fromId(saved);
    }
  }

  Future<void> setAccent(AppAccent accent) async {
    state = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeColor, accent.id);
  }
}
