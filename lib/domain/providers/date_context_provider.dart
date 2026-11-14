import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The clock every date-sensitive surface reads. Tests pin it so a capture or
/// a midnight rollover does not drift with the machine clock.
final clockNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

DateTime dayOf(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// The one browsed date, shared by Todo's by-date list and the Calendar.
///
/// Today is deliberately not stored here: it is derived from [clockDayProvider]
/// on every read, so browsing another day can never relabel "today".
final browseDateProvider = StateProvider<DateTime>(
  (ref) => dayOf(ref.read(clockNowProvider)()),
);

/// The real today, refreshed by the day-check timer in the home shell.
final clockDayProvider = NotifierProvider<ClockDayNotifier, DateTime>(
  ClockDayNotifier.new,
);

class ClockDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dayOf(ref.read(clockNowProvider)());

  void refresh() {
    final next = dayOf(ref.read(clockNowProvider)());
    if (next != state) state = next;
  }
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isRealToday(DateTime value, DateTime now) => isSameDay(value, now);
