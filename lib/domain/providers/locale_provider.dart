import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the user-selected language code. Also read by
/// notification scheduling, which cannot take a BuildContext.
const appLocalePrefKey = 'app_locale';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(appLocalePrefKey);
    if (code != null) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(appLocalePrefKey);
    } else {
      await prefs.setString(appLocalePrefKey, locale.languageCode);
    }
    state = locale;
  }
}
