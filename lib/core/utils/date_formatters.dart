import 'package:dayspark/l10n/app_localizations.dart';

/// Centralised date/time formatting helpers used across the app.
class DateFormatters {
  DateFormatters._();

  /// Returns `HH:MM` (24-hour, zero-padded).
  static String formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Returns `YYYY-MM-DD HH:MM`.
  static String formatDateTime(DateTime dt) =>
      '${formatDate(dt)} ${formatTime(dt)}';

  /// Returns `YYYY-MM-DD`.
  static String formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// Returns `M/D` (short locale-friendly date).
  static String formatShortDate(DateTime dt) => '${dt.month}/${dt.day}';

  /// Formats an absolute TaskAllocation interval in the viewer's local time.
  /// Dates are shown for the Todo summary and whenever the interval crosses
  /// midnight, so equal clock times cannot hide a 24-hour/multi-day range.
  static String formatTaskAllocationRange(
    DateTime startAt,
    DateTime endAt, {
    bool includeDate = true,
    DateTime Function(DateTime)? toLocal,
  }) {
    final localize = toLocal ?? (value) => value.toLocal();
    final start = localize(startAt);
    final end = localize(endAt);
    final startTime = formatTime(start);
    final endTime = formatTime(end);
    final sameDate =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDate) {
      final prefix = includeDate ? '${formatDate(start)}  ' : '';
      return '$prefix$startTime – $endTime';
    }
    return '${formatShortDate(start)} $startTime – '
        '${formatShortDate(end)} $endTime';
  }

  /// "just now" / "Nm ago" / "Nh ago", older falls back to `M/D HH:MM`.
  static String formatRelativeTime(DateTime time, AppLocalizations l) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return l.justNow;
    if (diff.inMinutes < 60) return l.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l.hoursAgo(diff.inHours);
    return '${formatShortDate(time)} ${formatTime(time)}';
  }
}
