import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyDefaultTab = 'default_tab';

enum AppTab { action, calendar, todos }

final defaultTabProvider = StateNotifierProvider<DefaultTabNotifier, AppTab>(
  (ref) => DefaultTabNotifier(),
);

class DefaultTabNotifier extends StateNotifier<AppTab> {
  DefaultTabNotifier() : super(AppTab.action) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDefaultTab);
    if (mounted && saved != null) {
      state = AppTab.values.firstWhere(
        (t) => t.name == saved,
        orElse: () => AppTab.action,
      );
    }
  }

  Future<void> setDefaultTab(AppTab tab) async {
    state = tab;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultTab, tab.name);
  }
}
