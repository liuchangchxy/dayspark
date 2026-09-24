import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/domain/services/chinese_calendar_service.dart';

void main() {
  group('ChineseCalendarService.solarTerm', () {
    test('2026-02-04 is Lichun (Spring Begins)', () {
      expect(
        ChineseCalendarService.solarTerm(DateTime(2026, 2, 4)),
        '立春',
      );
    });

    test('2026-12-22 is Dongzhi (Winter Solstice) per lunar 1.7.8', () {
      expect(
        ChineseCalendarService.solarTerm(DateTime(2026, 12, 22)),
        '冬至',
      );
    });

    test('day before a term is not a term day', () {
      expect(ChineseCalendarService.solarTerm(DateTime(2026, 12, 21)), isNull);
      expect(ChineseCalendarService.solarTerm(DateTime(2026, 1, 1)), isNull);
    });

    test('2026 mid-year terms resolve', () {
      expect(ChineseCalendarService.solarTerm(DateTime(2026, 5, 5)), '立夏');
      expect(ChineseCalendarService.solarTerm(DateTime(2026, 8, 7)), '立秋');
      expect(ChineseCalendarService.solarTerm(DateTime(2026, 3, 20)), '春分');
    });
  });

  group('ChineseCalendarService.holiday', () {
    test('2026-09-20 is a National Day makeup workday', () {
      final mark = ChineseCalendarService.holiday(DateTime(2026, 9, 20));
      expect(mark, isNotNull);
      expect(mark!.isWorkday, isTrue);
      expect(mark.name, '国庆节');
    });

    test('2026-10-01 is a statutory rest day', () {
      final mark = ChineseCalendarService.holiday(DateTime(2026, 10, 1));
      expect(mark, isNotNull);
      expect(mark!.isWorkday, isFalse);
    });

    test('2026-05-01 is Labour Day rest', () {
      final mark = ChineseCalendarService.holiday(DateTime(2026, 5, 1));
      expect(mark, isNotNull);
      expect(mark!.isWorkday, isFalse);
      expect(mark.name, '劳动节');
    });

    test('ordinary weekday has no holiday mark', () {
      expect(ChineseCalendarService.holiday(DateTime(2026, 3, 10)), isNull);
    });
  });
}
