import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';

/// Provider for the default calendar ID.
/// Stored in SharedPreferences under 'default_calendar_id'.
/// When null, the first calendar is used by convention.
final defaultCalendarIdProvider =
    StateNotifierProvider<DefaultCalendarNotifier, int?>((ref) {
      return DefaultCalendarNotifier();
    });

class DefaultCalendarNotifier extends StateNotifier<int?> {
  DefaultCalendarNotifier() : super(null) {
    _load();
  }

  static const _key = 'default_calendar_id';

  Future<int?> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_key);
    } on Exception catch (error) {
      // The preference is optional: an unavailable store just means the first
      // calendar is used.
      debugPrint('default calendar: preference read failed: $error');
      return null;
    }
  }

  Future<void> _load() async {
    final id = await _read();
    if (id != null) {
      state = id;
    }
  }

  Future<void> ensureLoaded() => _load();

  Future<void> setDefaultCalendarId(int id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, id);
  }

  /// Deletes the stored preference when it points at [id], so a removed
  /// calendar cannot stay the default.
  Future<void> clearDefaultCalendarId(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_key) != id && state != id) return;
      await prefs.remove(_key);
      state = null;
    } on Exception catch (error) {
      debugPrint('default calendar: preference clear failed: $error');
      if (state == id) state = null;
    }
  }
}

/// The one place that decides which calendar a new item lands in: the stored
/// preference while that calendar still exists, otherwise the first one.
int? resolveNewEntryCalendarId({
  required Iterable<Calendar> calendars,
  required int? preferredId,
}) {
  Calendar? first;
  for (final calendar in calendars) {
    first ??= calendar;
    if (calendar.id == preferredId) return calendar.id;
  }
  return first?.id;
}
