import 'package:lunar/lunar.dart';

class HolidayMark {
  final String name;
  // true = makeup workday (班), false = statutory rest day (休)
  final bool isWorkday;

  const HolidayMark({required this.name, required this.isWorkday});
}

// Pure-Dart wrapper over the lunar package: solar-term names + Chinese
// statutory holiday / makeup-workday marks. Results are memoized per day
// because the month grid re-queries the same dates on every rebuild.
class ChineseCalendarService {
  ChineseCalendarService._();

  static final Map<DateTime, String> _termCache = {};
  static final Map<DateTime, HolidayMark?> _holidayCache = {};

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  // Returns the Chinese solar-term name (立春, 冬至, ...) for the given
  // civil day, or null when the day is not a term day.
  static String? solarTerm(DateTime date) {
    final key = _day(date);
    final cached = _termCache[key];
    if (cached != null) return cached.isEmpty ? null : cached;
    final lunar = Lunar.fromDate(key);
    // 节 (getJie) and 气 (getQi) never fall on the same day; a term day
    // has exactly one of them set.
    var name = lunar.getJie();
    if (name.isEmpty) name = lunar.getQi();
    _termCache[key] = name;
    return name.isEmpty ? null : name;
  }

  // Returns the statutory-holiday mark for days inside an official holiday
  // block or makeup-workday set; regular days return null.
  static HolidayMark? holiday(DateTime date) {
    final key = _day(date);
    if (_holidayCache.containsKey(key)) return _holidayCache[key];
    final h = HolidayUtil.getHolidayByYmd(key.year, key.month, key.day);
    final mark = h == null
        ? null
        : HolidayMark(name: h.getName(), isWorkday: h.isWork());
    _holidayCache[key] = mark;
    return mark;
  }
}
