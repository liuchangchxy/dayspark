import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/core/utils/date_formatters.dart';

void main() {
  DateTime addEightHours(DateTime value) => value.add(const Duration(hours: 8));

  test('formats UTC instants as an injected viewer local wall time', () {
    expect(
      DateFormatters.formatTaskAllocationRange(
        DateTime.utc(2026, 10, 5, 8),
        DateTime.utc(2026, 10, 5, 9),
        toLocal: addEightHours,
      ),
      '2026-10-05  16:00 – 17:00',
    );
  });

  test('keeps same-day allocation summaries compact', () {
    expect(
      DateFormatters.formatTaskAllocationRange(
        DateTime.utc(2026, 10, 5, 8),
        DateTime.utc(2026, 10, 5, 9),
        includeDate: false,
        toLocal: addEightHours,
      ),
      '16:00 – 17:00',
    );
  });

  test('shows both dates for a cross-day allocation', () {
    expect(
      DateFormatters.formatTaskAllocationRange(
        DateTime.utc(2026, 10, 5, 8),
        DateTime.utc(2026, 10, 6, 8),
        toLocal: addEightHours,
        now: DateTime(2026, 10, 5),
      ),
      '10/5 16:00 – 10/6 16:00',
    );
  });

  test(
    'a date in another year keeps its year instead of reading as this year',
    () {
      expect(
        DateFormatters.formatShortDate(
          DateTime(2027, 1, 4),
          now: DateTime(2026, 12, 30),
        ),
        '2027/1/4',
      );
      expect(
        DateFormatters.formatShortDate(
          DateTime(2026, 12, 30),
          now: DateTime(2026, 12, 30),
        ),
        '12/30',
      );
    },
  );
}
