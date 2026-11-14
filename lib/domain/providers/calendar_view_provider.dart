import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

const _keyCalendarViewMode = 'calendar_view_mode';

final calendarViewModeProvider =
    StateNotifierProvider<CalendarViewModeNotifier, CalendarViewMode>(
  (ref) => CalendarViewModeNotifier(),
);

class CalendarViewModeNotifier extends StateNotifier<CalendarViewMode> {
  CalendarViewModeNotifier() : super(CalendarViewMode.week) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyCalendarViewMode);
    if (saved != null) {
      final mode = CalendarViewMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => CalendarViewMode.week,
      );
      if (mounted) state = mode;
    }
  }

  Future<void> setViewMode(CalendarViewMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCalendarViewMode, mode.name);
  }
}
