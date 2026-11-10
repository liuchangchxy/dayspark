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
  blue('blue', '蓝', 'Blue', Color(0xFF2D4F7C), Color(0xFF8FB0D9)),
  teal('teal', '青', 'Teal', Color(0xFF3F6B68), Color(0xFF8FB8B2)),
  green('green', '绿', 'Green', Color(0xFF4C6B55), Color(0xFFA3C4A8)),
  orange('orange', '橙', 'Orange', Color(0xFF8A5237), Color(0xFFD9A184)),
  purple('purple', '紫', 'Purple', Color(0xFF63556F), Color(0xFFB7A5C6)),
  pink('pink', '玫红', 'Rose', Color(0xFF85525F), Color(0xFFC99AA5));

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
    const legacy = {
      0xFF007AFF: AppAccent.blue,
      0xFF5AC8FA: AppAccent.teal,
      0xFF34C759: AppAccent.green,
      0xFFFF9500: AppAccent.orange,
      0xFFAF52DE: AppAccent.purple,
      0xFFFF2D55: AppAccent.pink,
    };
    final mapped = legacy[argb];
    if (mapped != null) return mapped;
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
