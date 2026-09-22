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
  static String formatShortDate(DateTime dt) =>
      '${dt.month}/${dt.day}';
}
