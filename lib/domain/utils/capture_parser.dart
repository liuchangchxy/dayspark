class CaptureDraft {
  const CaptureDraft({
    required this.title,
    required this.date,
    required this.start,
    required this.duration,
    required this.participants,
  });

  final String title;
  final DateTime? date;
  final DateTime? start;
  final Duration duration;
  final List<String> participants;

  DateTime? get end => start?.add(duration);

  bool get hasTimeSuggestion => start != null;
}

const CaptureDraft emptyCaptureDraft = CaptureDraft(
  title: '',
  date: null,
  start: null,
  duration: Duration(hours: 1),
  participants: [],
);

CaptureDraft parseCapture(String raw, DateTime now) {
  final text = raw.trim();
  if (text.isEmpty) return emptyCaptureDraft;

  var work = text;
  var duration = const Duration(hours: 1);

  final halfHour = RegExp('半个?小时').firstMatch(work);
  if (halfHour != null) {
    duration = const Duration(minutes: 30);
    work = work.replaceFirst(halfHour.group(0)!, ' ');
  } else {
    final hours = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:个)?\s*小时',
    ).firstMatch(work);
    if (hours != null) {
      final value = double.tryParse(hours.group(1) ?? '');
      if (value != null && value > 0) {
        duration = Duration(minutes: (value * 60).round());
      }
      work = work.replaceFirst(hours.group(0)!, ' ');
    } else {
      final minutes = RegExp(r'(\d+)\s*分钟').firstMatch(work);
      if (minutes != null) {
        final value = int.tryParse(minutes.group(1) ?? '');
        if (value != null && value > 0) {
          duration = Duration(minutes: value);
        }
        work = work.replaceFirst(minutes.group(0)!, ' ');
      }
    }
  }

  var date = DateTime(now.year, now.month, now.day);
  var hasDate = false;
  final explicitDate = RegExp(
    r'(\d{4})-(\d{1,2})-(\d{1,2})',
  ).firstMatch(work);
  if (explicitDate != null) {
    date = DateTime(
      int.parse(explicitDate.group(1)!),
      int.parse(explicitDate.group(2)!),
      int.parse(explicitDate.group(3)!),
    );
    hasDate = true;
    work = work.replaceFirst(explicitDate.group(0)!, ' ');
  } else {
    final monthDay = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(work);
    if (monthDay != null) {
      date = DateTime(
        now.year,
        int.parse(monthDay.group(1)!),
        int.parse(monthDay.group(2)!),
      );
      hasDate = true;
      work = work.replaceFirst(monthDay.group(0)!, ' ');
    } else if (work.contains('大后天')) {
      date = date.add(const Duration(days: 3));
      hasDate = true;
      work = work.replaceFirst('大后天', ' ');
    } else if (work.contains('后天')) {
      date = date.add(const Duration(days: 2));
      hasDate = true;
      work = work.replaceFirst('后天', ' ');
    } else if (work.contains('明天') || work.contains('明日')) {
      date = date.add(const Duration(days: 1));
      hasDate = true;
      work = work.replaceAll(RegExp('明天|明日'), ' ');
    } else if (work.contains('今天') || work.contains('今日')) {
      hasDate = true;
      work = work.replaceAll(RegExp('今天|今日'), ' ');
    } else {
      final weekday = RegExp(
        r'(下)?(?:周|星期)([一二三四五六日天])',
      ).firstMatch(work);
      if (weekday != null) {
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final target = names.indexOf(
              weekday.group(2) == '天' ? '日' : weekday.group(2)!,
            ) +
            1;
        var delta = (target - date.weekday + 7) % 7;
        if (weekday.group(1) != null) {
          delta = delta == 0 ? 7 : delta;
        }
        date = date.add(Duration(days: delta));
        hasDate = true;
        work = work.replaceFirst(weekday.group(0)!, ' ');
      }
    }
  }

  final period = RegExp('凌晨|早上|上午|中午|下午|傍晚|晚上').firstMatch(work);
  var hour = 0;
  var minute = 0;
  var hasTime = false;
  final colon = RegExp(r'(\d{1,2})[:：](\d{2})').firstMatch(work);
  if (colon != null) {
    hour = int.parse(colon.group(1)!);
    minute = int.parse(colon.group(2)!);
    hasTime = true;
    work = work.replaceFirst(colon.group(0)!, ' ');
  } else {
    final clock = RegExp(
      r'([零一二两三四五六七八九十\d]{1,3})(?:点|时)(半|[零一二三四五六七八九十\d]{1,3}分?)?',
    ).firstMatch(work);
    if (clock != null) {
      hour = _number(clock.group(1)!) ?? 0;
      final rest = clock.group(2);
      if (rest == '半') {
        minute = 30;
      } else if (rest != null && rest.isNotEmpty) {
        minute = _number(rest.replaceAll('分', '')) ?? 0;
      }
      hasTime = true;
      work = work.replaceFirst(clock.group(0)!, ' ');
    }
  }

  if (hasTime && period != null) {
    final label = period.group(0)!;
    if (label == '下午' || label == '傍晚' || label == '晚上') {
      if (hour < 12) hour += 12;
    } else if (label == '中午' && hour < 11) {
      hour += 12;
    } else if (label == '凌晨' && hour == 12) {
      hour = 0;
    }
    work = work.replaceFirst(label, ' ');
  }

  final participants = <String>[];
  for (final match in RegExp(
    r'(?:和|跟|与)([一-龥]{1,6})',
  ).allMatches(work)) {
    final rawName = match.group(1) ?? '';
    final name = rawName.replaceFirst(
      RegExp('(开会|吃饭|讨论|见面|电话|聊天|碰面|午餐|晚餐|散步|运动|出差)\$'),
      '',
    );
    if (name.isEmpty || name.length > 4) continue;
    if (RegExp('[点天日月号]').hasMatch(name)) continue;
    if (!participants.contains(name)) participants.add(name);
    final connector = match.group(0)!.substring(0, 1);
    work = work.replaceFirst('$connector$name', ' ');
  }

  if (hasTime) {
    minute = minute.clamp(0, 59);
    hour = hour.clamp(0, 23);
    date = DateTime(date.year, date.month, date.day, hour, minute);
  }

  var title = work
      .replaceAll(RegExp('提前\\s*\\d+\\s*(?:分钟|小时)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  title = title.replaceAll(RegExp(r'^[，,、。\s]+|[，,、。\s]+$'), '');
  if (title.isEmpty) title = text;

  return CaptureDraft(
    title: title,
    date: hasDate ? DateTime(date.year, date.month, date.day) : null,
    start: hasTime ? date : null,
    duration: duration,
    participants: participants,
  );
}

int? _number(String input) {
  final direct = int.tryParse(input);
  if (direct != null) return direct;
  const digits = {
    '零': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (input == '十') return 10;
  if (input.startsWith('十')) {
    return 10 + (digits[input.substring(1)] ?? 0);
  }
  final tenAt = input.indexOf('十');
  if (tenAt > 0) {
    final tens = digits[input.substring(0, tenAt)] ?? 0;
    final rest = input.substring(tenAt + 1);
    return tens * 10 + (rest.isEmpty ? 0 : digits[rest] ?? 0);
  }
  return digits[input];
}
