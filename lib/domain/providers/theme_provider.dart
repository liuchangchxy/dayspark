import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themeModePrefKey = 'theme_mode';
const _keyThemeColor = 'theme_color';

/// The locked accent presets (DESIGN 主题色条款).
///
/// Each preset carries a matched light/dark pair from the iOS system palette.
/// Users pick a preset, never a raw color — a free picker lets one bad hue
/// drag the whole surface family off the token table.
enum AppAccent {
  blue('blue', '蓝', 'Blue', Color(0xFF007AFF), Color(0xFF0A84FF)),
  green('green', '绿', 'Green', Color(0xFF34C759), Color(0xFF30D158)),
  orange('orange', '橙', 'Orange', Color(0xFFFF9500), Color(0xFFFF9F0A)),
  purple('purple', '紫', 'Purple', Color(0xFFAF52DE), Color(0xFFBF5AF2)),
  pink('pink', '粉', 'Pink', Color(0xFFFF2D55), Color(0xFFFF375F));

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

  static AppAccent fromId(String? id) => values.firstWhere(
    (a) => a.id == id,
    orElse: () => AppAccent.blue,
  );

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
