part of '../dayspark_recurrence.dart';

enum RecurrenceRuleErrorKind { invalid, unsupported }

final class RecurrenceRuleException implements Exception {
  const RecurrenceRuleException(this.kind, this.message);

  final RecurrenceRuleErrorKind kind;
  final String message;

  @override
  String toString() => '${kind.name}: $message';
}

final class ValidatedRRule {
  const ValidatedRRule._(
    this.valueType,
    this.canonical,
    this.frequency,
    this.interval,
    this.byDay,
    this.byMonthDay,
    this.count,
    this.until,
    this._untilDate,
  );

  static const maximumCount = 10000;
  static const maximumInterval = 1000000;
  static const _maximumInputLength = 512;
  static const _supportedParts = {
    'FREQ',
    'INTERVAL',
    'BYDAY',
    'BYMONTHDAY',
    'COUNT',
    'UNTIL',
  };
  static const _frequencies = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
  static const _weekdayOrder = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  final RecurrenceValueType valueType;
  final String canonical;
  final String frequency;
  final int interval;
  final List<String> byDay;
  final List<int> byMonthDay;
  final int? count;
  final DateTime? until;
  final LocalDate? _untilDate;

  factory ValidatedRRule.parse(
    String input, {
    required RecurrenceValueType valueType,
  }) {
    if (input.isEmpty ||
        input.length > _maximumInputLength ||
        input != input.trim() ||
        input.toUpperCase().startsWith('RRULE:')) {
      throw const RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'RRULE is empty, too long, or not a bare RRULE value.',
      );
    }

    final parts = <String, String>{};
    for (final component in input.split(';')) {
      final separator = component.indexOf('=');
      if (separator <= 0 ||
          separator != component.lastIndexOf('=') ||
          separator == component.length - 1) {
        throw const RecurrenceRuleException(
          RecurrenceRuleErrorKind.invalid,
          'Malformed RRULE component.',
        );
      }
      final name = component.substring(0, separator).toUpperCase();
      final value = component.substring(separator + 1).toUpperCase();
      if (!_supportedParts.contains(name)) {
        throw RecurrenceRuleException(
          RecurrenceRuleErrorKind.unsupported,
          'Unsupported RRULE component: $name.',
        );
      }
      if (parts.containsKey(name)) {
        throw RecurrenceRuleException(
          RecurrenceRuleErrorKind.invalid,
          'Duplicate RRULE component: $name.',
        );
      }
      parts[name] = value;
    }

    final frequency = parts['FREQ'];
    if (frequency == null) {
      throw const RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'FREQ is required.',
      );
    }
    if (!_frequencies.contains(frequency)) {
      throw RecurrenceRuleException(
        RecurrenceRuleErrorKind.unsupported,
        'Unsupported FREQ: $frequency.',
      );
    }
    if (parts.containsKey('COUNT') && parts.containsKey('UNTIL')) {
      throw const RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'COUNT and UNTIL cannot be combined.',
      );
    }

    final interval = _parseInt(
      parts['INTERVAL'] ?? '1',
      name: 'INTERVAL',
      minimum: 1,
      maximum: maximumInterval,
    );
    final count = parts.containsKey('COUNT')
        ? _parseInt(
            parts['COUNT']!,
            name: 'COUNT',
            minimum: 1,
            maximum: maximumCount,
          )
        : null;

    final monthDays = <int>[];
    if (parts.containsKey('BYMONTHDAY')) {
      for (final value in parts['BYMONTHDAY']!.split(',')) {
        final day = _parseInt(
          value,
          name: 'BYMONTHDAY',
          minimum: -31,
          maximum: 31,
          signed: true,
        );
        if (day == 0 || monthDays.contains(day)) {
          throw const RecurrenceRuleException(
            RecurrenceRuleErrorKind.invalid,
            'BYMONTHDAY values must be unique and non-zero.',
          );
        }
        monthDays.add(day);
      }
      if (frequency == 'WEEKLY') {
        throw const RecurrenceRuleException(
          RecurrenceRuleErrorKind.invalid,
          'BYMONTHDAY is not valid with WEEKLY.',
        );
      }
      monthDays.sort();
    }

    final days = <String>[];
    if (parts.containsKey('BYDAY')) {
      for (final token in parts['BYDAY']!.split(',')) {
        final match = RegExp(
          r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$',
        ).firstMatch(token);
        if (match == null) {
          throw const RecurrenceRuleException(
            RecurrenceRuleErrorKind.invalid,
            'BYDAY contains an invalid weekday entry.',
          );
        }
        final ordinalText = match.group(1);
        if (ordinalText != null) {
          final ordinal = int.parse(ordinalText);
          if (ordinal == 0 || ordinal.abs() > 53) {
            throw const RecurrenceRuleException(
              RecurrenceRuleErrorKind.invalid,
              'BYDAY ordinal must be between -53 and -1 or 1 and 53.',
            );
          }
          if (frequency != 'MONTHLY' && frequency != 'YEARLY') {
            throw const RecurrenceRuleException(
              RecurrenceRuleErrorKind.invalid,
              'Ordinal BYDAY is supported only with MONTHLY or YEARLY.',
            );
          }
        }
        final ordinal = ordinalText == null ? '' : '${int.parse(ordinalText)}';
        days.add('$ordinal${match.group(2)}');
      }
      if (days.toSet().length != days.length) {
        throw const RecurrenceRuleException(
          RecurrenceRuleErrorKind.invalid,
          'BYDAY values must be unique.',
        );
      }
      days.sort((left, right) {
        final leftDay = _weekdayOrder.indexOf(
          left.replaceAll(RegExp(r'^[-+]?\d+'), ''),
        );
        final rightDay = _weekdayOrder.indexOf(
          right.replaceAll(RegExp(r'^[-+]?\d+'), ''),
        );
        final weekday = leftDay.compareTo(rightDay);
        return weekday == 0 ? left.compareTo(right) : weekday;
      });
    }

    DateTime? until;
    LocalDate? untilDate;
    if (parts.containsKey('UNTIL')) {
      final raw = parts['UNTIL']!;
      if (valueType == RecurrenceValueType.date) {
        if (!RegExp(r'^\d{8}$').hasMatch(raw)) {
          throw const RecurrenceRuleException(
            RecurrenceRuleErrorKind.invalid,
            'DATE recurrence UNTIL must use YYYYMMDD.',
          );
        }
        untilDate = _parseDate(raw);
        until = untilDate._calendarCandidate;
      } else {
        if (!RegExp(r'^\d{8}T\d{6}Z$').hasMatch(raw)) {
          throw const RecurrenceRuleException(
            RecurrenceRuleErrorKind.invalid,
            'DATE-TIME recurrence UNTIL must be UTC and end with Z.',
          );
        }
        final fields = raw.substring(0, raw.length - 1);
        final dateTime = DateTime.utc(
          int.parse(fields.substring(0, 4)),
          int.parse(fields.substring(4, 6)),
          int.parse(fields.substring(6, 8)),
          int.parse(fields.substring(9, 11)),
          int.parse(fields.substring(11, 13)),
          int.parse(fields.substring(13, 15)),
        );
        if ('${dateTime.year.toString().padLeft(4, '0')}'
                '${dateTime.month.toString().padLeft(2, '0')}'
                '${dateTime.day.toString().padLeft(2, '0')}T'
                '${dateTime.hour.toString().padLeft(2, '0')}'
                '${dateTime.minute.toString().padLeft(2, '0')}'
                '${dateTime.second.toString().padLeft(2, '0')}Z' !=
            raw) {
          throw const RecurrenceRuleException(
            RecurrenceRuleErrorKind.invalid,
            'UNTIL is not a valid UTC date-time.',
          );
        }
        until = dateTime;
      }
    }

    final canonicalParts = <String>['FREQ=$frequency'];
    if (parts.containsKey('INTERVAL')) canonicalParts.add('INTERVAL=$interval');
    if (days.isNotEmpty) canonicalParts.add('BYDAY=${days.join(',')}');
    if (monthDays.isNotEmpty) {
      canonicalParts.add('BYMONTHDAY=${monthDays.join(',')}');
    }
    if (count != null) canonicalParts.add('COUNT=$count');
    if (parts.containsKey('UNTIL')) {
      canonicalParts.add('UNTIL=${parts['UNTIL']}');
    }

    final result = ValidatedRRule._(
      valueType,
      canonicalParts.join(';'),
      frequency,
      interval,
      List.unmodifiable(days),
      List.unmodifiable(monthDays),
      count,
      until,
      untilDate,
    );
    try {
      rrule.RecurrenceRule.fromString('RRULE:${result._libraryText}');
    } on FormatException catch (error) {
      throw RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        error.message,
      );
    } on RangeError catch (error) {
      throw RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        error.message.toString(),
      );
    }
    return result;
  }

  String get _libraryText {
    if (valueType == RecurrenceValueType.dateTime && until != null) {
      return canonical
          .split(';')
          .where((part) => !part.startsWith('UNTIL='))
          .join(';');
    }
    return canonical;
  }

  rrule.RecurrenceRule toLibraryRule() =>
      rrule.RecurrenceRule.fromString('RRULE:$_libraryText');

  static int _parseInt(
    String value, {
    required String name,
    required int minimum,
    required int maximum,
    bool signed = false,
  }) {
    final valid = RegExp(signed ? r'^-?\d+$' : r'^\d+$').hasMatch(value);
    final parsed = valid ? int.tryParse(value) : null;
    if (parsed == null || parsed < minimum || parsed > maximum) {
      throw RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        '$name is outside its supported range.',
      );
    }
    return parsed;
  }

  static LocalDate _parseDate(String value) {
    try {
      return LocalDate(
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
      );
    } on ArgumentError {
      throw const RecurrenceRuleException(
        RecurrenceRuleErrorKind.invalid,
        'UNTIL contains an invalid calendar date.',
      );
    }
  }
}
