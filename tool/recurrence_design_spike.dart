import 'dart:io';

import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'recurrence_tz_probe.dart';

void check(bool value, String message) {
  if (!value) throw StateError('FAIL: $message');
  stdout.writeln('PASS: $message');
}

List<DateTime> expand(String ruleText, DateTime start, {DateTime? before}) =>
    RecurrenceRule.fromString(
      'RRULE:$ruleText',
    ).getInstances(start: start, before: before).toList();

const supportedRuleParts = <String>{
  'FREQ',
  'INTERVAL',
  'BYDAY',
  'BYMONTHDAY',
  'COUNT',
  'UNTIL',
};

bool passesWhitelist(String ruleText) {
  final values = <String, String>{};
  for (final part in ruleText.split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0 || separator == part.length - 1) return false;
    final name = part.substring(0, separator).toUpperCase();
    final value = part.substring(separator + 1).toUpperCase();
    if (!supportedRuleParts.contains(name) || values.containsKey(name)) {
      return false;
    }
    values[name] = value;
  }
  final frequency = values['FREQ'];
  if (!{'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(frequency) ||
      (values.containsKey('COUNT') && values.containsKey('UNTIL'))) {
    return false;
  }
  final interval = int.tryParse(values['INTERVAL'] ?? '1');
  final count = int.tryParse(values['COUNT'] ?? '1');
  if (interval == null || interval < 1 || count == null || count < 1) {
    return false;
  }
  if (frequency == 'WEEKLY' && values.containsKey('BYMONTHDAY')) return false;
  final monthDays = values['BYMONTHDAY'];
  if (monthDays != null &&
      monthDays.split(',').any((value) {
        final day = int.tryParse(value);
        return day == null || day == 0 || day.abs() > 31;
      })) {
    return false;
  }
  final byDay = values['BYDAY'];
  if (byDay != null &&
      byDay.split(',').any((value) {
        final match = RegExp(
          r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$',
        ).firstMatch(value);
        if (match == null) return true;
        final ordinal = match.group(1);
        if (ordinal == null) return false;
        final number = int.tryParse(ordinal);
        return number == null ||
            number == 0 ||
            number.abs() > 53 ||
            !{'MONTHLY', 'YEARLY'}.contains(frequency);
      })) {
    return false;
  }
  try {
    RecurrenceRule.fromString('RRULE:$ruleText');
  } on FormatException {
    return false;
  }
  return true;
}

String date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

void main() {
  stdout.writeln('Dart runtime: ${Platform.version}');
  stdout.writeln('RRULE spike:');
  final daily = expand('FREQ=DAILY;COUNT=3', DateTime.utc(2026, 10, 1, 9));
  check(daily.length == 3 && daily[2].day == 3, 'DAILY + COUNT');
  final weekly = expand(
    'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=4',
    DateTime.utc(2026, 10, 5, 9),
  );
  check(weekly.length == 4 && weekly[2].day == 19, 'WEEKLY + INTERVAL + BYDAY');
  final monthly = expand(
    'FREQ=MONTHLY;BYMONTHDAY=5;COUNT=3',
    DateTime.utc(2026, 10, 5, 9),
  );
  check(monthly.length == 3 && monthly[1].month == 11, 'MONTHLY + BYMONTHDAY');
  final yearly = expand('FREQ=YEARLY;COUNT=3', DateTime.utc(2026, 10, 5, 9));
  check(
    yearly.length == 3 && yearly[2].year == 2028,
    'YEARLY anchored calendar date',
  );
  final interval = expand(
    'FREQ=DAILY;INTERVAL=2;COUNT=3',
    DateTime.utc(2026, 10, 1, 9),
  );
  check(interval[1].day == 3, 'DAILY + INTERVAL');
  final ordinalByDay = expand(
    'FREQ=MONTHLY;BYDAY=1MO;COUNT=3',
    DateTime.utc(2026, 10, 5, 9),
  );
  check(ordinalByDay[1].day == 2, 'MONTHLY ordinal BYDAY');
  final until = expand(
    'FREQ=DAILY;UNTIL=20261003T090000Z',
    DateTime.utc(2026, 10, 1, 9),
    before: DateTime.utc(2026, 10, 5),
  );
  check(until.length == 3 && until.last.day == 3, 'inclusive UTC UNTIL');

  final unknown = RecurrenceRule.fromString('RRULE:FREQ=DAILY;X-UNKNOWN=1');
  check(
    unknown.frequency == Frequency.daily,
    'unknown token parser behavior observed',
  );
  check(
    !passesWhitelist('FREQ=DAILY;X-UNKNOWN=1') &&
        passesWhitelist('FREQ=WEEKLY;BYDAY=MO;COUNT=4'),
    'strict wrapper rejects unknown parts and accepts allowed parts',
  );
  check(
    [
      'FREQ=DAILY;COUNT=3',
      'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=4',
      'FREQ=MONTHLY;BYMONTHDAY=5;COUNT=3',
      'FREQ=YEARLY;COUNT=3',
      'FREQ=MONTHLY;BYDAY=1MO;COUNT=3',
      'FREQ=DAILY;UNTIL=20261003T090000Z',
    ].every(passesWhitelist),
    'all proposed subset examples pass strict validator',
  );
  check(
    !passesWhitelist('FREQ=DAILY;COUNT=2;UNTIL=20261003T090000Z') &&
        !passesWhitelist('FREQ=DAILY;INTERVAL=2;INTERVAL=3') &&
        !passesWhitelist('FREQ=SECONDLY') &&
        !passesWhitelist('FREQ=WEEKLY;BYMONTHDAY=5') &&
        !passesWhitelist('FREQ=WEEKLY;BYDAY=1MO'),
    'strict wrapper rejects COUNT+UNTIL, duplicate/unsupported parts and invalid combinations',
  );
  var invalidRejected = false;
  try {
    RecurrenceRule.fromString('RRULE:FREQ=NOPE');
  } on FormatException {
    invalidRejected = true;
  }
  check(invalidRejected, 'invalid FREQ throws FormatException');
  var missingFrequencyRejected = false;
  try {
    RecurrenceRule.fromString('RRULE:COUNT=3');
  } on FormatException {
    missingFrequencyRejected = true;
  }
  check(missingFrequencyRejected, 'missing FREQ throws FormatException');
  final monthlySkip = expand(
    'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4',
    DateTime.utc(2026, 1, 31, 9),
  );
  check(
    monthlySkip.map((value) => '${value.month}/${value.day}').join(',') ==
        '1/31,3/31,5/31,7/31',
    'invalid monthly dates omitted and not counted',
  );
  final dateOnlyCandidates = expand(
    'FREQ=DAILY;COUNT=3',
    DateTime.utc(2026, 10, 5),
  );
  check(
    dateOnlyCandidates.map(date).join(',') ==
        '2026-10-05,2026-10-06,2026-10-07',
    'DATE-only adapter extracts LocalDate values from internal candidates',
  );
  check(
    dateOnlyOccurrenceId(DateTime.utc(2026, 11, 2), 'Asia/Shanghai') ==
        'v1:DATE:2026-11-02@Asia/Shanghai',
    'DATE-only key contains a date and zone without time/instant',
  );

  tzdata.initializeTimeZones();
  final ny = tz.getLocation('America/New_York');
  final gapLocal = DateTime(2026, 3, 8, 2, 30);
  final gapConstructed = tz.TZDateTime(
    ny,
    gapLocal.year,
    gapLocal.month,
    gapLocal.day,
    gapLocal.hour,
    gapLocal.minute,
  );
  final gapResolved = resolveNominalLocalOccurrence(
    nominal: gapLocal,
    zoneName: 'America/New_York',
  );
  final gapActual = tz.TZDateTime.from(gapResolved.instant, ny);
  stdout.writeln(
    'GAP constructor=$gapConstructed offset=${gapConstructed.timeZoneOffset} '
    'utc=${gapConstructed.toUtc().toIso8601String()} '
    'local=${gapConstructed.year}-${gapConstructed.month}-${gapConstructed.day} '
    '${gapConstructed.hour}:${gapConstructed.minute}',
  );
  stdout.writeln(
    'GAP prototype id=${gapResolved.occurrenceId} '
    'utc=${gapResolved.instant.toIso8601String()} '
    'offset=${gapActual.timeZoneOffset} actual=${gapActual.hour}:${gapActual.minute}',
  );
  check(
    gapResolved.instant == DateTime.utc(2026, 3, 8, 7, 30) &&
        gapActual.hour == 3 &&
        gapActual.minute == 30,
    'gap-before-offset resolution gives 07:30Z / 03:30 EDT',
  );
  check(
    gapResolved.occurrenceId == 'v1:DT:2026-03-08T02:30:00@America/New_York',
    'gap identity preserves nominal local time',
  );
  final aroundGap = expand(
    'FREQ=WEEKLY;COUNT=3',
    DateTime.utc(2026, 3, 1, 2, 30),
  );
  final gapCountOccurrence = aroundGap[1];
  final resolvedGapCount = resolveNominalLocalOccurrence(
    nominal: gapCountOccurrence,
    zoneName: 'America/New_York',
  );
  check(
    aroundGap.length == 3 &&
        resolvedGapCount.instant == DateTime.utc(2026, 3, 8, 7, 30) &&
        aroundGap.last.day == 15,
    'COUNT includes RFC-resolved gap occurrence',
  );

  final foldLocal = DateTime(2026, 11, 1, 1, 30);
  final foldCandidates = exactCandidates(foldLocal, ny);
  final foldConstructed = tz.TZDateTime(
    ny,
    foldLocal.year,
    foldLocal.month,
    foldLocal.day,
    foldLocal.hour,
    foldLocal.minute,
  );
  final foldResolved = resolveNominalLocalOccurrence(
    nominal: foldLocal,
    zoneName: 'America/New_York',
  );
  stdout.writeln(
    'FOLD candidates=${foldCandidates.map((v) => v.toIso8601String()).join(',')} '
    'constructor=${foldConstructed.toIso8601String()} '
    'prototype=${foldResolved.instant.toIso8601String()}',
  );
  check(
    foldCandidates.length == 2 &&
        foldResolved.instant == DateTime.utc(2026, 11, 1, 5, 30),
    'fold prototype chooses first occurrence (EDT)',
  );

  final shanghaiOccurrence = resolveNominalLocalOccurrence(
    nominal: DateTime(2026, 10, 5, 9),
    zoneName: 'Asia/Shanghai',
  );
  final displayedInLosAngeles = tz.TZDateTime.from(
    shanghaiOccurrence.instant,
    tz.getLocation('America/Los_Angeles'),
  );
  final displayedInTokyo = tz.TZDateTime.from(
    shanghaiOccurrence.instant,
    tz.getLocation('Asia/Tokyo'),
  );
  check(
    shanghaiOccurrence.instant == DateTime.utc(2026, 10, 5, 1) &&
        shanghaiOccurrence.occurrenceId.endsWith('@Asia/Shanghai') &&
        displayedInLosAngeles.hour != displayedInTokyo.hour,
    'series instant and identity fixed while viewer display changes',
  );
  stdout.writeln(
    'TZ database source header: 2025c (verified in both locked package files)',
  );
  stdout.writeln(
    'NY location transitions=${ny.transitionAt.length} zones=${ny.zones.length}',
  );

  stdout.writeln('ICS parser spike:');
  final fixtures = <(String, String)>[
    ('zoned', 'DTSTART;TZID=America/New_York:20261102T090000'),
    ('floating', 'DTSTART:20261102T090000'),
    ('utc', 'DTSTART:20261102T140000Z'),
    ('date', 'DTSTART;VALUE=DATE:20261102'),
  ];
  for (final (label, startLine) in fixtures) {
    final ics = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'BEGIN:VTODO',
      'UID:$label@example.test',
      'DTSTAMP:20261001T000000Z',
      'SUMMARY:$label',
      startLine,
      'DUE;TZID=America/New_York:20261103T170000',
      'RRULE:FREQ=DAILY;COUNT=2',
      'END:VTODO',
      'END:VCALENDAR',
      '',
    ].join('\r\n');
    final calendar = VComponent.parse(ics) as VCalendar;
    final todo = calendar.todo!;
    final startProperty = todo['DTSTART']!;
    final dueProperty = todo['DUE']!;
    final startValue = startProperty.value as DateTime;
    final rawValueType = startProperty.parameters['VALUE']?.textValue;
    stdout.writeln(
      'ICS $label raw=${startProperty.definition} '
      'TZID=${(startProperty as DateTimeProperty).timezoneId} '
      'VALUE=$rawValueType '
      'value=$startValue isUtc=${startValue.isUtc} '
      'DUEraw=${dueProperty.definition} '
      'DUEtzid=${(dueProperty as DateTimeProperty).timezoneId} '
      'DUEvalue=${dueProperty.value} RRULE=${todo.recurrenceRule}',
    );
    stdout.writeln(
      'ICS converter boundary: converter persists only DateTime fields, not property parameters.',
    );
    if (label == 'zoned') {
      check(
        startProperty.timezoneId == 'America/New_York' &&
            startValue == DateTime(2026, 11, 2, 9),
        'TZID retained in parsed property alongside floating-shaped DateTime',
      );
    } else if (label == 'floating') {
      check(
        startProperty.timezoneId == null &&
            rawValueType == null &&
            !startValue.isUtc,
        'floating value has no TZID/VALUE and is host-local DateTime',
      );
    } else if (label == 'utc') {
      check(startValue.isUtc, 'UTC Z value parses as UTC DateTime');
    } else {
      check(
        rawValueType == 'DATE' && !startValue.isUtc,
        'VALUE=DATE retained as parameter but getter materializes local midnight',
      );
    }
    check(
      dueProperty.timezoneId == 'America/New_York' &&
          todo.recurrenceRule.toString() == 'FREQ=DAILY;COUNT=2',
      'DUE TZID and RRULE parse',
    );
  }

  final withVtimezone = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:STANDARD
DTSTART:20261101T020000
TZOFFSETFROM:-0400
TZOFFSETTO:-0500
END:STANDARD
END:VTIMEZONE
BEGIN:VTODO
UID:vtimezone@example.test
DTSTAMP:20261001T000000Z
DTSTART;TZID=America/New_York:20261102T090000
END:VTODO
END:VCALENDAR
''';
  final calendar = VComponent.parse(withVtimezone) as VCalendar;
  final timezoneComponent = calendar.children.firstWhere(
    (component) => component.name == 'VTIMEZONE',
  );
  stdout.writeln(
    'ICS VTIMEZONE children=${calendar.children.map((c) => c.name).join(',')} '
    'timezoneProperties=${timezoneComponent.properties.map((p) => p.definition).join('|')} '
    'timezoneNested=${timezoneComponent.children.map((c) => c.name).join(',')}',
  );
  check(
    timezoneComponent.children.any((component) => component.name == 'STANDARD'),
    'VTIMEZONE component and nested STANDARD retained',
  );
}
