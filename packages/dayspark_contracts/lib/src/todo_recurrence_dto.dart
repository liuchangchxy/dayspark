import 'package:dayspark_recurrence/dayspark_recurrence.dart';

enum RecurrenceLegacyState { knownZoned, unknownLegacy }

extension RecurrenceLegacyStateWireName on RecurrenceLegacyState {
  String get wireName => switch (this) {
    RecurrenceLegacyState.knownZoned => 'knownZoned',
    RecurrenceLegacyState.unknownLegacy => 'unknownLegacy',
  };
}

final class RecurrenceSpecDto {
  const RecurrenceSpecDto(this.value);

  factory RecurrenceSpecDto.fromJson(Map<String, dynamic> json) {
    _onlyKeys(json, const {'anchor', 'timeZone', 'rrule'});
    final rawAnchor = json['anchor'];
    if (rawAnchor is! Map) {
      throw const FormatException('invalid recurrence anchor');
    }
    final anchor = Map<String, dynamic>.from(rawAnchor);
    _onlyKeys(anchor, const {'source', 'valueType', 'value'});
    final source = switch (anchor['source']) {
      'start' => RecurrenceAnchorSource.start,
      'due' => RecurrenceAnchorSource.due,
      _ => throw const FormatException('invalid recurrence anchor source'),
    };
    final value = switch (anchor['valueType']) {
      'date' => _date(anchor['value']),
      'dateTime' => _dateTime(anchor['value']),
      _ => throw const FormatException('invalid recurrence value type'),
    };
    if (json['timeZone'] is! String || json['rrule'] is! String) {
      throw const FormatException('partial recurrence spec');
    }
    try {
      return RecurrenceSpecDto(
        RecurrenceSpec.parse(
          anchor: RecurrenceAnchor(source: source, value: value),
          timeZone: json['timeZone'] as String,
          rrule: json['rrule'] as String,
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException('invalid recurrence spec: $error');
    } on RecurrenceRuleException catch (error) {
      throw FormatException('invalid recurrence RRULE: $error');
    }
  }

  final RecurrenceSpec value;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'anchor': <String, dynamic>{
      'source': value.anchor.source.name,
      'valueType': value.anchor.valueType.name,
      'value': value.anchor.value.canonical,
    },
    'timeZone': value.timeZone,
    'rrule': value.rule.canonical,
  };
}

final class TodoRecurrenceDto {
  const TodoRecurrenceDto({
    required this.spec,
    required this.revision,
    required this.legacyState,
  });

  factory TodoRecurrenceDto.fromTodoPayload(Map<String, dynamic> payload) {
    const keys = {
      'recurrenceSpec',
      'recurrenceRevision',
      'recurrenceLegacyState',
    };
    if (!keys.any(payload.containsKey)) {
      return TodoRecurrenceDto(
        spec: null,
        revision: 0,
        legacyState: payload['rrule'] is String
            ? RecurrenceLegacyState.unknownLegacy
            : null,
      );
    }
    final rawSpec = payload['recurrenceSpec'];
    final rawRevision = payload['recurrenceRevision'];
    final rawState = payload['recurrenceLegacyState'];
    if (rawRevision is! int || rawRevision < 0) {
      throw const FormatException('invalid recurrence revision');
    }
    if (rawState == 'knownZoned' && rawSpec is Map && rawRevision > 0) {
      return TodoRecurrenceDto(
        spec: RecurrenceSpecDto.fromJson(
          Map<String, dynamic>.from(rawSpec),
        ).value,
        revision: rawRevision,
        legacyState: RecurrenceLegacyState.knownZoned,
      );
    }
    if (rawState == 'unknownLegacy' && rawSpec == null && rawRevision == 0) {
      if (payload['rrule'] is! String) {
        throw const FormatException('unknownLegacy requires old RRULE data');
      }
      return const TodoRecurrenceDto(
        spec: null,
        revision: 0,
        legacyState: RecurrenceLegacyState.unknownLegacy,
      );
    }
    if (rawState == null && rawSpec == null) {
      if (payload['rrule'] != null) {
        throw const FormatException(
          'non-recurring Todo cannot retain a legacy RRULE projection',
        );
      }
      return TodoRecurrenceDto(
        spec: null,
        revision: rawRevision,
        legacyState: null,
      );
    }
    throw const FormatException('invalid recurrence payload invariant');
  }

  final RecurrenceSpec? spec;
  final int revision;
  final RecurrenceLegacyState? legacyState;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'recurrenceSpec': spec == null ? null : RecurrenceSpecDto(spec!).toJson(),
    'recurrenceRevision': revision,
    'recurrenceLegacyState': legacyState?.wireName,
  };
}

LocalDate _date(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('invalid DATE recurrence anchor');
  }
  final fields = value.split('-').map(int.parse).toList();
  try {
    return LocalDate(fields[0], fields[1], fields[2]);
  } on ArgumentError {
    throw const FormatException('invalid DATE recurrence anchor');
  }
}

LocalDateTime _dateTime(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(value)) {
    throw const FormatException('invalid DATE-TIME recurrence anchor');
  }
  final parts = value.split('T');
  final date = parts[0].split('-').map(int.parse).toList();
  final time = parts[1].split(':').map(int.parse).toList();
  try {
    return LocalDateTime(date[0], date[1], date[2], time[0], time[1], time[2]);
  } on ArgumentError {
    throw const FormatException('invalid DATE-TIME recurrence anchor');
  }
}

void _onlyKeys(Map<String, dynamic> json, Set<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('unknown recurrence payload field');
  }
}
