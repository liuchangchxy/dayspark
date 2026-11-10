import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themeModePrefKey = 'theme_mode';
const _keyThemeColor = 'theme_color';

/// The locked accent presets (DESIGN & VISUAL_POLISH.md 3.3).
///
/// Cobalt (#2D4F7C), Sage/Green (#4F7368), Warm/Orange (#9A6248), Purple/Work (#6F5D7E), Rose (#8F5A68), Olive (#6B7048)
enum AppAccent {
  blue('blue', '深钴蓝', 'Cobalt', Color(0xFF2D4F7C), Color(0xFF8FB0D9)),
  green('green', '灰绿', 'Sage', Color(0xFF4F7368), Color(0xFF6F998C)),
  orange('orange', '暖褐', 'Terracotta', Color(0xFF9A6248), Color(0xFFB87C5E)),
  purple('purple', '暮紫', 'Plum', Color(0xFF6F5D7E), Color(0xFF8E7A9F)),
  rose('rose', '玫红', 'Rose', Color(0xFF8F5A68), Color(0xFFAF7485)),
  olive('olive', '橄榄', 'Olive', Color(0xFF6B7048), Color(0xFF8A9060));

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
      if (mounted) state = AppAccent.fromId(saved);
      return;
    }
    final legacy = prefs.getInt(_keyThemeColor);
    if (legacy != null) {
      final migrated = AppAccent.fromLegacyColor(legacy);
      if (mounted) state = migrated;
      await prefs.setString(_keyThemeColor, migrated.id);
      await prefs.remove(_keyThemeColor);
    }
  }

  Future<void> setAccent(AppAccent accent) async {
    state = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeColor, accent.id);
  }
}
