part of '../dayspark_recurrence.dart';

enum RecurrenceAnchorSource { start, due }

enum RecurrenceValueType { date, dateTime }

sealed class RecurrenceLocalValue {
  const RecurrenceLocalValue();

  RecurrenceValueType get valueType;

  String get canonical;

  DateTime get _calendarCandidate;
}

final class LocalDate extends RecurrenceLocalValue
    implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    final value = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        value.year != year ||
        value.month != month ||
        value.day != day) {
      throw ArgumentError('Invalid LocalDate: $year-$month-$day');
    }
  }

  final int year;
  final int month;
  final int day;

  @override
  RecurrenceValueType get valueType => RecurrenceValueType.date;

  @override
  String get canonical =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  DateTime get _calendarCandidate => DateTime.utc(year, month, day);

  LocalDate addDays(int days) {
    final value = _calendarCandidate.add(Duration(days: days));
    return LocalDate(value.year, value.month, value.day);
  }

  @override
  int compareTo(LocalDate other) =>
      _calendarCandidate.compareTo(other._calendarCandidate);

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => canonical;
}

final class LocalDateTime extends RecurrenceLocalValue
    implements Comparable<LocalDateTime> {
  LocalDateTime(
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.second,
  ) {
    final value = DateTime.utc(year, month, day, hour, minute, second);
    if (year < 1 ||
        year > 9999 ||
        value.year != year ||
        value.month != month ||
        value.day != day ||
        value.hour != hour ||
        value.minute != minute ||
        value.second != second) {
      throw ArgumentError('Invalid LocalDateTime: $year-$month-$day');
    }
  }

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;

  @override
  RecurrenceValueType get valueType => RecurrenceValueType.dateTime;

  LocalDate get date => LocalDate(year, month, day);

  @override
  String get canonical =>
      '${date.canonical}T'
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}';

  @override
  DateTime get _calendarCandidate =>
      DateTime.utc(year, month, day, hour, minute, second);

  LocalDateTime addCalendarDays(int days) {
    final value = _calendarCandidate.add(Duration(days: days));
    return LocalDateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }

  @override
  int compareTo(LocalDateTime other) =>
      _calendarCandidate.compareTo(other._calendarCandidate);

  @override
  bool operator ==(Object other) =>
      other is LocalDateTime &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute, second);

  @override
  String toString() => canonical;
}

final class RecurrenceAnchor {
  const RecurrenceAnchor({required this.source, required this.value});

  final RecurrenceAnchorSource source;
  final RecurrenceLocalValue value;

  RecurrenceValueType get valueType => value.valueType;
}

RecurrenceAnchor? selectRecurrenceAnchor({
  RecurrenceLocalValue? start,
  RecurrenceLocalValue? due,
}) {
  if (start != null) {
    return RecurrenceAnchor(source: RecurrenceAnchorSource.start, value: start);
  }
  if (due != null) {
    return RecurrenceAnchor(source: RecurrenceAnchorSource.due, value: due);
  }
  return null;
}

final class RecurrenceSpec {
  RecurrenceSpec({
    required this.anchor,
    required this.timeZone,
    required this.rule,
  }) {
    IanaTimeZone.validateSyntax(timeZone);
    if (rule.valueType != anchor.valueType) {
      throw ArgumentError('RRULE value type does not match its anchor.');
    }
  }

  factory RecurrenceSpec.parse({
    required RecurrenceAnchor anchor,
    required String timeZone,
    required String rrule,
  }) => RecurrenceSpec(
    anchor: anchor,
    timeZone: timeZone,
    rule: ValidatedRRule.parse(rrule, valueType: anchor.valueType),
  );

  final RecurrenceAnchor anchor;
  final String timeZone;
  final ValidatedRRule rule;
}

sealed class RecurrenceWindow {
  const RecurrenceWindow();
}

final class InstantWindow extends RecurrenceWindow {
  InstantWindow({required this.startInclusive, required this.endExclusive}) {
    if (!startInclusive.isUtc ||
        !endExclusive.isUtc ||
        !startInclusive.isBefore(endExclusive)) {
      throw ArgumentError('Instant window must be a non-empty UTC range.');
    }
  }

  final DateTime startInclusive;
  final DateTime endExclusive;
}

final class LocalDateWindow extends RecurrenceWindow {
  LocalDateWindow({required this.startInclusive, required this.endExclusive}) {
    if (startInclusive.compareTo(endExclusive) >= 0) {
      throw ArgumentError('DATE window must be a non-empty range.');
    }
  }

  final LocalDate startInclusive;
  final LocalDate endExclusive;
}

final class RecurrenceOccurrence {
  const RecurrenceOccurrence({
    required this.nominal,
    required this.occurrenceId,
    required this.resolvedInstant,
  });

  final RecurrenceLocalValue nominal;
  final OccurrenceId occurrenceId;
  final DateTime? resolvedInstant;
}
