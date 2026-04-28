import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyLunarCalendar = 'lunar_calendar';

final lunarCalendarProvider =
    StateNotifierProvider<LunarCalendarNotifier, bool>(
      (ref) => LunarCalendarNotifier(),
    );

class LunarCalendarNotifier extends StateNotifier<bool> {
  LunarCalendarNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_keyLunarCalendar) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLunarCalendar, enabled);
  }
}
