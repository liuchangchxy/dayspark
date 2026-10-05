part of '../dayspark_recurrence.dart';

final class IanaTimeZone {
  IanaTimeZone._(this.id);

  final String id;

  factory IanaTimeZone(String id) {
    validateSyntax(id);
    return IanaTimeZone._(id);
  }

  static void validateSyntax(String id) {
    if (!RegExp(r'^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'timeZone', 'Must be an IANA TZID.');
    }
  }

  @override
  bool operator ==(Object other) => other is IanaTimeZone && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

final class OccurrenceId {
  OccurrenceId._(this.nominal, this.timeZone, this.value);

  final RecurrenceLocalValue nominal;
  final IanaTimeZone? timeZone;
  final String value;

  factory OccurrenceId.forNominal(
    RecurrenceLocalValue nominal,
    String timeZone,
  ) {
    final zone = IanaTimeZone(timeZone);
    if (nominal.valueType == RecurrenceValueType.date) {
      return OccurrenceId._(nominal, null, 'v2:DATE:${nominal.canonical}');
    }
    const prefix = 'v1:DT:';
    return OccurrenceId._(
      nominal,
      zone,
      '$prefix${nominal.canonical}@${zone.id}',
    );
  }

  factory OccurrenceId.parse(String value) {
    final dateOnly = RegExp(r'^v2:DATE:(\d{4}-\d{2}-\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      final nominal = _parseDate(dateOnly.group(1)!);
      return OccurrenceId._(nominal, null, value);
    }
    final match = RegExp(
      r'^v1:(DATE|DT):([^@]+)@([A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*)$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid occurrenceId: $value');
    }
    final nominal = switch (match.group(1)) {
      'DATE' => _parseDate(match.group(2)!),
      'DT' => _parseDateTime(match.group(2)!),
      _ => throw FormatException('Unknown occurrenceId value type: $value'),
    };
    final legacyDate = match.group(1) == 'DATE';
    final result = legacyDate
        ? OccurrenceId._(nominal, IanaTimeZone(match.group(3)!), value)
        : OccurrenceId.forNominal(nominal, match.group(3)!);
    if (result.value != value) {
      throw FormatException('Non-canonical occurrenceId: $value');
    }
    return result;
  }

  static LocalDate _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw FormatException('Invalid DATE occurrenceId.');
    try {
      return LocalDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } on ArgumentError {
      throw FormatException('Invalid DATE occurrenceId.');
    }
  }

  static LocalDateTime _parseDateTime(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(value);
    if (match == null) throw FormatException('Invalid DATE-TIME occurrenceId.');
    try {
      return LocalDateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } on ArgumentError {
      throw FormatException('Invalid DATE-TIME occurrenceId.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is OccurrenceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
