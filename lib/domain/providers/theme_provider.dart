import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyThemeMode = 'theme_mode';
const _keyThemeColor = 'theme_color';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyThemeMode);
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
    await prefs.setString(_keyThemeMode, mode.name);
  }
}

final themeColorProvider = StateNotifierProvider<ThemeColorNotifier, Color?>(
  (ref) => ThemeColorNotifier(),
);

class ThemeColorNotifier extends StateNotifier<Color?> {
  ThemeColorNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyThemeColor);
    if (value != null && mounted) {
      state = Color(value);
    }
  }

  Future<void> setColor(Color? color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_keyThemeColor, color.toARGB32());
    } else {
      await prefs.remove(_keyThemeColor);
    }
  }
}
