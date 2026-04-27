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

  /// Returns a human-readable relative time string (e.g. "just now", "5m ago", "3h ago").
  /// Falls back to `M/D H:MM` for times older than 24 hours.
  static String formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${time.month}/${time.day} ${formatTime(time)}';
  }
}
