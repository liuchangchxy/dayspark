import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyFirstDayOfWeek = 'first_day_of_week';
const _keyTimeFormat24 = 'time_format_24';

/// First day of week preference: 1 = Monday (周一), 7 = Sunday (周日).
final firstDayOfWeekProvider = StateNotifierProvider<FirstDayOfWeekNotifier, int>(
  (ref) => FirstDayOfWeekNotifier(),
);

class FirstDayOfWeekNotifier extends StateNotifier<int> {
  FirstDayOfWeekNotifier() : super(1) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_keyFirstDayOfWeek);
    if (mounted && saved != null) {
      state = saved;
    }
  }

  Future<void> setFirstDay(int day) async {
    state = day;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyFirstDayOfWeek, day);
  }
}

/// Time display format: true = 24-hour (14:30), false = 12-hour (2:30 PM).
final use24HourFormatProvider = StateNotifierProvider<TimeFormatNotifier, bool>(
  (ref) => TimeFormatNotifier(),
);

class TimeFormatNotifier extends StateNotifier<bool> {
  TimeFormatNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_keyTimeFormat24);
    if (mounted && saved != null) {
      state = saved;
    }
  }

  Future<void> set24Hour(bool is24) async {
    state = is24;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTimeFormat24, is24);
  }
}
