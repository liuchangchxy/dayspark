import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

bool _recurrenceZoneDataReady = false;

void ensureTodoRecurrenceTimeZonesInitialized() {
  if (_recurrenceZoneDataReady) return;
  tzdata.initializeTimeZones();
  _recurrenceZoneDataReady = true;
}

enum TodoRecurrenceLegacyState { knownZoned, unknownLegacy }

extension TodoRecurrenceLegacyStateWire on TodoRecurrenceLegacyState {
  String get wireName => switch (this) {
    TodoRecurrenceLegacyState.knownZoned => 'knownZoned',
    TodoRecurrenceLegacyState.unknownLegacy => 'unknownLegacy',
  };
}

final class TodoRecurrence {
  TodoRecurrence._({
    required this.spec,
    required this.revision,
    required this.legacyState,
  }) {
    if (revision < 0) {
      throw const FormatException('recurrence revision must be non-negative');
    }
    if (spec == null && legacyState == TodoRecurrenceLegacyState.knownZoned) {
      throw const FormatException('knownZoned requires a complete recurrence');
    }
    if (spec != null &&
        (legacyState != TodoRecurrenceLegacyState.knownZoned || revision < 1)) {
      throw const FormatException('invalid knownZoned recurrence revision');
    }
    if (legacyState == TodoRecurrenceLegacyState.unknownLegacy &&
        (spec != null || revision != 0)) {
      throw const FormatException('invalid unknownLegacy recurrence');
    }
  }

  final RecurrenceSpec? spec;
  final int revision;
  final TodoRecurrenceLegacyState? legacyState;

  bool get isUnknownLegacy =>
      legacyState == TodoRecurrenceLegacyState.unknownLegacy;

  static TodoRecurrence none({int revision = 0}) =>
      TodoRecurrence._(spec: null, revision: revision, legacyState: null);

  static TodoRecurrence unknownLegacy() => TodoRecurrence._(
    spec: null,
    revision: 0,
    legacyState: TodoRecurrenceLegacyState.unknownLegacy,
  );

  static TodoRecurrence known(RecurrenceSpec spec, {required int revision}) =>
      _knownWithZoneCheck(spec, revision);

  static TodoRecurrence _knownWithZoneCheck(RecurrenceSpec spec, int revision) {
    _validateKnownZone(spec.timeZone);
    return TodoRecurrence._(
      spec: spec,
      revision: revision,
      legacyState: TodoRecurrenceLegacyState.knownZoned,
    );
  }

  static TodoRecurrence fromTodo(Todo todo) {
    final state = todo.recurrenceLegacyState;
    if (state == null) {
      if (todo.rrule != null ||
          todo.recurrenceAnchorSource != null ||
          todo.recurrenceValueType != null ||
          todo.recurrenceAnchorValue != null ||
          todo.recurrenceTimeZone != null ||
          todo.recurrenceRule != null) {
        throw const FormatException('partial recurrence persistence');
      }
      return none(revision: todo.recurrenceRevision);
    }
    if (state == 'unknownLegacy') {
      if (todo.rrule == null ||
          todo.recurrenceRevision != 0 ||
          todo.recurrenceAnchorSource != null ||
          todo.recurrenceValueType != null ||
          todo.recurrenceAnchorValue != null ||
          todo.recurrenceTimeZone != null ||
          todo.recurrenceRule != null) {
        throw const FormatException('invalid unknownLegacy persistence');
      }
      return unknownLegacy();
    }
    if (state != 'knownZoned') {
      throw const FormatException('invalid recurrence legacy state');
    }
    final source = switch (todo.recurrenceAnchorSource) {
      'start' => RecurrenceAnchorSource.start,
      'due' => RecurrenceAnchorSource.due,
      _ => throw const FormatException('invalid recurrence anchor source'),
    };
    final value = switch (todo.recurrenceValueType) {
      'date' => _parseDate(todo.recurrenceAnchorValue),
      'dateTime' => _parseDateTime(todo.recurrenceAnchorValue),
      _ => throw const FormatException('invalid recurrence value type'),
    };
    final zone = todo.recurrenceTimeZone;
    final rule = todo.recurrenceRule;
    final revision = todo.recurrenceRevision;
    if (zone == null || rule == null || revision < 1) {
      throw const FormatException('partial knownZoned recurrence');
    }
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(source: source, value: value),
      timeZone: zone,
      rrule: rule,
    );
    if (todo.rrule != spec.rule.canonical) {
      throw const FormatException('legacy RRULE projection differs from spec');
    }
    return known(spec, revision: revision);
  }

  TodosCompanion recurrenceColumns() => TodosCompanion(
    recurrenceAnchorSource: Value(spec?.anchor.source.name),
    recurrenceValueType: Value(spec?.anchor.valueType.name),
    recurrenceAnchorValue: Value(spec?.anchor.value.canonical),
    recurrenceTimeZone: Value(spec?.timeZone),
    recurrenceRule: Value(spec?.rule.canonical),
    recurrenceLegacyState: Value(legacyState?.wireName),
    recurrenceRevision: Value(revision),
  );

  TodosCompanion toCompanion() =>
      recurrenceColumns().copyWith(rrule: Value(spec?.rule.canonical));

  Map<String, Object?> toJson() => <String, Object?>{
    'recurrenceSpec': spec == null
        ? null
        : <String, Object?>{
            'anchor': <String, Object?>{
              'source': spec!.anchor.source.name,
              'valueType': spec!.anchor.valueType.name,
              'value': spec!.anchor.value.canonical,
            },
            'timeZone': spec!.timeZone,
            'rrule': spec!.rule.canonical,
          },
    'recurrenceRevision': revision,
    'recurrenceLegacyState': legacyState?.wireName,
  };

  static TodoRecurrence fromWire(Map<String, dynamic> json) {
    final rawSpec = json['recurrenceSpec'];
    final rawRevision = json['recurrenceRevision'];
    final rawState = json['recurrenceLegacyState'];
    if (rawState == null &&
        rawSpec == null &&
        rawRevision is int &&
        rawRevision >= 0) {
      return none(revision: rawRevision);
    }
    if (rawState == 'unknownLegacy' && rawSpec == null && rawRevision == 0) {
      return unknownLegacy();
    }
    if (rawState != 'knownZoned' ||
        rawRevision is! int ||
        rawRevision < 1 ||
        rawSpec is! Map) {
      throw const FormatException('invalid recurrence wire state');
    }
    final spec = Map<String, dynamic>.from(rawSpec);
    final anchorRaw = spec['anchor'];
    if (anchorRaw is! Map ||
        spec.keys.toSet().difference({
          'anchor',
          'timeZone',
          'rrule',
        }).isNotEmpty ||
        anchorRaw.keys.toSet().difference({
          'source',
          'valueType',
          'value',
        }).isNotEmpty) {
      throw const FormatException('invalid recurrence wire object');
    }
    final anchor = Map<String, dynamic>.from(anchorRaw);
    final source = switch (anchor['source']) {
      'start' => RecurrenceAnchorSource.start,
      'due' => RecurrenceAnchorSource.due,
      _ => throw const FormatException('invalid recurrence anchor source'),
    };
    final value = switch (anchor['valueType']) {
      'date' => _parseDate(anchor['value']),
      'dateTime' => _parseDateTime(anchor['value']),
      _ => throw const FormatException('invalid recurrence value type'),
    };
    if (spec['timeZone'] is! String || spec['rrule'] is! String) {
      throw const FormatException('partial recurrence spec');
    }
    return known(
      RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(source: source, value: value),
        timeZone: spec['timeZone'] as String,
        rrule: spec['rrule'] as String,
      ),
      revision: rawRevision,
    );
  }
}

void _validateKnownZone(String value) {
  ensureTodoRecurrenceTimeZonesInitialized();
  try {
    tz.getLocation(value);
  } on tz.LocationNotFoundException {
    throw FormatException('Unknown IANA timezone: $value.');
  }
}

RecurrenceSpec? recurrenceFromTodoFields({
  required DateTime? startDate,
  required DateTime? dueDate,
  required String? rrule,
}) {
  if (rrule == null) return null;
  final value = startDate ?? dueDate;
  if (value == null) {
    throw StateError('Recurring Todo requires startDate or dueDate.');
  }
  final local = value.toLocal();
  final rule = rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;
  return RecurrenceSpec.parse(
    anchor: RecurrenceAnchor(
      source: startDate == null
          ? RecurrenceAnchorSource.due
          : RecurrenceAnchorSource.start,
      value: LocalDateTime(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
        local.second,
      ),
    ),
    timeZone: tz.local.name,
    rrule: rule,
  );
}

LocalDate _parseDate(Object? raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    throw const FormatException('invalid DATE recurrence anchor');
  }
  final parts = raw.split('-').map(int.parse).toList();
  try {
    return LocalDate(parts[0], parts[1], parts[2]);
  } on ArgumentError {
    throw const FormatException('invalid DATE recurrence anchor');
  }
}

LocalDateTime _parseDateTime(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(raw)) {
    throw const FormatException('invalid DATE-TIME recurrence anchor');
  }
  final dateTime = raw.split('T');
  final date = dateTime[0].split('-').map(int.parse).toList();
  final time = dateTime[1].split(':').map(int.parse).toList();
  try {
    return LocalDateTime(date[0], date[1], date[2], time[0], time[1], time[2]);
  } on ArgumentError {
    throw const FormatException('invalid DATE-TIME recurrence anchor');
  }
}
