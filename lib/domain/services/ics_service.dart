import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database/app_database.dart';
import '../records/record_scope.dart';
import '../records/todo_recurrence.dart';
import '../records/writers/event_writer.dart';
import '../records/writers/todo_writer.dart';
import 'ical/ical_converter.dart';

/// Import/export .ics files.
class IcsService {
  final AppDatabase _db;
  final IcalConverter _converter = IcalConverter();

  IcsService(this._db);

  /// Export all events from a calendar to a .ics file.
  Future<String> exportCalendar(int calendarId) async {
    final events =
        await (_db.select(_db.events)..where(
              (t) => t.calendarId.equals(calendarId) & t.deletedAt.isNull(),
            ))
            .get();
    final todos =
        await (_db.select(_db.todos)..where(
              (t) => t.calendarId.equals(calendarId) & t.deletedAt.isNull(),
            ))
            .get();

    final cal = VCalendar();
    cal.productId = '-//CalendarTodoApp//EN';
    cal.version = '2.0';

    for (final event in events) {
      final vevent = VEvent();
      // Events have no uid column since schema v8; synthesize a stable UID for export.
      vevent.uid = 'dayspark-event-${event.id}@dayspark';
      vevent.summary = event.summary;
      vevent.start = event.startDt;
      vevent.end = event.endDt;
      vevent.timeStamp = event.updatedAt;
      if (event.description != null) vevent.description = event.description;
      if (event.location != null) vevent.location = event.location;
      if (event.rrule != null && event.rrule!.isNotEmpty) {
        vevent.recurrenceRule = Recurrence.parse(event.rrule!);
      }
      cal.children.add(vevent);
    }

    for (final todo in todos) {
      final vtodo = VTodo();
      // Todos have no uid column since schema v8; synthesize a stable UID for export.
      vtodo.uid = 'dayspark-todo-${todo.id}@dayspark';
      vtodo.summary = todo.summary;
      vtodo.timeStamp = todo.updatedAt;
      final recurrence = TodoRecurrence.fromTodo(todo);
      final spec = recurrence.spec;
      if (todo.dueDate != null) {
        if (spec != null &&
            spec.anchor.valueType == RecurrenceValueType.dateTime) {
          final due = todo.dueDate!;
          vtodo.setProperty(
            DateTimeProperty(
              'DUE;TZID=${spec.timeZone}:${_icsDateTime(LocalDateTime(due.year, due.month, due.day, due.hour, due.minute, due.second))}',
            ),
          );
        } else {
          vtodo.due = todo.dueDate;
        }
      }
      if (todo.startDate != null) vtodo.start = todo.startDate;
      if (todo.description != null) vtodo.description = todo.description;
      if (todo.priority > 0) vtodo.priorityInt = todo.priority;
      vtodo.status = _converter.mapTodoStatus(todo.status);
      if (todo.rrule != null && todo.rrule!.isNotEmpty) {
        vtodo.recurrenceRule = Recurrence.parse(todo.rrule!);
      }
      if (spec != null) {
        final anchor = spec.anchor.value;
        final propertyName = spec.anchor.source == RecurrenceAnchorSource.start
            ? 'DTSTART'
            : 'DUE';
        final property = anchor is LocalDate
            ? DateTimeProperty(
                '$propertyName;VALUE=DATE:${anchor.year.toString().padLeft(4, '0')}'
                '${anchor.month.toString().padLeft(2, '0')}'
                '${anchor.day.toString().padLeft(2, '0')}',
              )
            : DateTimeProperty(
                '$propertyName;TZID=${spec.timeZone}:${_icsDateTime(anchor as LocalDateTime)}',
              );
        vtodo.setProperty(property);
        vtodo.setProperty(TextProperty('RRULE:${spec.rule.canonical}'));
      }
      cal.children.add(vtodo);
    }

    return cal.toString();
  }

  /// Save .ics content to a file, returns the file path.
  Future<String> saveIcsToFile(String content, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    return file.path;
  }

  /// Import events/todos from an .ics string into a calendar.
  Future<({int events, int todos})> importIcs(
    String icsContent,
    int calendarId,
  ) async {
    final component = VComponent.parse(icsContent);
    if (component is! VCalendar) {
      throw FormatException('Not a valid VCALENDAR');
    }

    var events = 0;
    var todos = 0;

    // 一批导入 = 一个事务 = 一个事件批；畸形行在 catch 里被吞掉，不登记
    // （没落库的行不该让派生态去重读）。
    await RecordScope.run(_db, (tx) async {
      for (final child in component.children) {
        if (child is VEvent) {
          try {
            final childCal = VCalendar();
            childCal.productId = '-//CalendarTodoApp//EN';
            childCal.children.add(child);
            final companion = _converter.icalToEventCompanion(
              childCal.toString(),
              calendarId,
            );
            await EventWriter.importRow(_db, tx, companion);
            events++;
          } catch (e) {
            debugPrint('ics: VEVENT insert error: $e');
          }
        } else if (child is VTodo) {
          try {
            final childCal = VCalendar();
            childCal.productId = '-//CalendarTodoApp//EN';
            childCal.children.add(child);
            var companion = _converter.icalToTodoCompanion(
              childCal.toString(),
              calendarId,
            );
            final import = _recurrenceFromIcs(child, component);
            if (import != null) {
              companion = companion.copyWith(
                rrule: Value(import.rule),
                startDate: import.startDate == null
                    ? const Value.absent()
                    : Value(import.startDate),
                dueDate: import.dueDate == null
                    ? const Value.absent()
                    : Value(import.dueDate),
              );
            }
            await TodoWriter.importRow(
              _db,
              tx,
              companion,
              recurrenceSpec: import?.spec,
              recurrenceEvidence: import?.evidence,
            );
            todos++;
          } catch (e) {
            debugPrint('ics: VTODO insert error: $e');
          }
        }
      }
    });

    return (events: events, todos: todos);
  }

  _IcsTodoRecurrence? _recurrenceFromIcs(VTodo todo, VCalendar sourceCalendar) {
    final rule = todo.getProperty<Property>('RRULE');
    if (rule == null) return null;
    final start = todo.getProperty<Property>('DTSTART');
    final due = todo.getProperty<Property>('DUE');
    final anchorProperty = start ?? due;
    final hasVTimezone = sourceCalendar.children.any(
      (child) => child is VTimezone,
    );
    if (anchorProperty == null) {
      return _legacyTodo(
        rule.textValue,
        start,
        due,
        hasVTimezone: hasVTimezone,
      );
    }

    final valueType = anchorProperty.parameters['VALUE']?.textValue;
    final isDate = valueType?.toUpperCase() == 'DATE';
    final raw = anchorProperty.textValue;
    final rawTzid = anchorProperty.parameters['TZID']?.textValue;
    final RecurrenceLocalValue anchor;
    try {
      if (isDate) {
        if (!RegExp(r'^\d{8}$').hasMatch(raw)) {
          return _legacyTodo(
            rule.textValue,
            start,
            due,
            hasVTimezone: hasVTimezone,
          );
        }
        anchor = LocalDate(
          int.parse(raw.substring(0, 4)),
          int.parse(raw.substring(4, 6)),
          int.parse(raw.substring(6, 8)),
        );
      } else {
        final wall = raw.endsWith('Z') ? raw.substring(0, raw.length - 1) : raw;
        if (!RegExp(r'^\d{8}T\d{6}$').hasMatch(wall)) {
          return _legacyTodo(
            rule.textValue,
            start,
            due,
            hasVTimezone: hasVTimezone,
          );
        }
        anchor = LocalDateTime(
          int.parse(wall.substring(0, 4)),
          int.parse(wall.substring(4, 6)),
          int.parse(wall.substring(6, 8)),
          int.parse(wall.substring(9, 11)),
          int.parse(wall.substring(11, 13)),
          int.parse(wall.substring(13, 15)),
        );
      }
      final zone = rawTzid;
      if (!isDate && (zone == null || raw.endsWith('Z'))) {
        return _legacyTodo(
          rule.textValue,
          start,
          due,
          hasVTimezone: hasVTimezone,
        );
      }
      if (!isDate && zone != null) {
        final matchingTimezone = _matchingTimezone(sourceCalendar, zone);
        if (matchingTimezone != null) {
          return _legacyTodo(
            rule.textValue,
            start,
            due,
            semantic: _vTimezoneSemantic(matchingTimezone, zone),
            hasVTimezone: true,
          );
        }
      }
      final spec = RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: start != null
              ? RecurrenceAnchorSource.start
              : RecurrenceAnchorSource.due,
          value: anchor,
        ),
        // DATE values have no instant; a TZID parameter cannot affect their
        // identity or make a VTIMEZONE definition relevant to expansion.
        timeZone: isDate ? 'Etc/UTC' : zone!,
        rrule: rule.textValue,
      );
      TodoRecurrence.known(spec, revision: 1);
      final projection = anchor is LocalDate
          ? DateTime(anchor.year, anchor.month, anchor.day)
          : DateTime(
              (anchor as LocalDateTime).year,
              anchor.month,
              anchor.day,
              anchor.hour,
              anchor.minute,
              anchor.second,
            );
      return _IcsTodoRecurrence(
        rule.textValue,
        spec: spec,
        startDate: start == null ? null : projection,
        dueDate: due == null ? null : _dateProjection(due),
      );
    } on Object {
      return _legacyTodo(
        rule.textValue,
        start,
        due,
        hasVTimezone: hasVTimezone,
      );
    }
  }

  VTimezone? _matchingTimezone(VCalendar calendar, String tzid) {
    for (final child in calendar.children) {
      if (child is VTimezone && child.timezoneId == tzid) return child;
    }
    return null;
  }

  String _vTimezoneSemantic(VTimezone timezone, String tzid) {
    if (!_isKnownIanaZone(tzid)) return 'unknownTzid';
    final location = tz.getLocation(tzid);
    final ianaOffsets = location.zones
        .map((zone) => zone.offset.inMinutes)
        .toSet();
    for (final phase in timezone.children) {
      if (phase is! VTimezonePhase) return 'vtimezoneUnsupported';
      final declaredOffsets = [phase.from, phase.to].map((offset) {
        final sign = offset.offsetHour < 0 ? -1 : 1;
        return offset.offsetHour * 60 + sign * offset.offsetMinute;
      });
      if (declaredOffsets.any((offset) => !ianaOffsets.contains(offset))) {
        return 'vtimezoneConflict';
      }
    }
    // Matching offset values do not establish equivalent transition rules.
    return 'vtimezoneUnsupported';
  }

  _IcsTodoRecurrence _legacyTodo(
    String rule,
    Property? start,
    Property? due, {
    String? semantic,
    bool hasVTimezone = false,
  }) {
    final anchor = start ?? due;
    final rawTzid = anchor?.parameters['TZID']?.textValue;
    final rawValue = anchor?.textValue ?? '';
    var inferredSemantic = semantic ?? 'unknown';
    if (semantic == null && anchor != null) {
      final isDate =
          anchor.parameters['VALUE']?.textValue.toUpperCase() == 'DATE';
      if (!isDate && rawValue.endsWith('Z')) {
        inferredSemantic = 'utcInstant';
      } else if (!isDate && rawTzid == null) {
        inferredSemantic = 'floating';
      } else if (rawTzid != null && !_isKnownIanaZone(rawTzid)) {
        inferredSemantic = 'unknownTzid';
      } else {
        final valueType = isDate
            ? RecurrenceValueType.date
            : RecurrenceValueType.dateTime;
        try {
          ValidatedRRule.parse(
            rule.startsWith('RRULE:') ? rule.substring(6) : rule,
            valueType: valueType,
          );
        } on RecurrenceRuleException {
          inferredSemantic = 'unsupportedRrule';
        }
      }
    }
    return _IcsTodoRecurrence.legacy(
      rule,
      startDate: start == null ? null : _dateProjection(start),
      dueDate: due == null ? null : _dateProjection(due),
      evidence: LegacyRecurrenceEvidence(
        source: 'ics',
        timeSemantic: inferredSemantic,
        rawTzid: rawTzid,
        hasVTimezone: hasVTimezone,
      ),
    );
  }

  bool _isKnownIanaZone(String zone) {
    ensureTodoRecurrenceTimeZonesInitialized();
    try {
      tz.getLocation(zone);
      return true;
    } on Object {
      return false;
    }
  }

  DateTime? _dateProjection(Property property) {
    final raw = property.textValue;
    final isDate =
        property.parameters['VALUE']?.textValue.toUpperCase() == 'DATE';
    final wall = raw.endsWith('Z') ? raw.substring(0, raw.length - 1) : raw;
    if (isDate && RegExp(r'^\d{8}$').hasMatch(wall)) {
      return DateTime(
        int.parse(wall.substring(0, 4)),
        int.parse(wall.substring(4, 6)),
        int.parse(wall.substring(6, 8)),
      );
    }
    if (RegExp(r'^\d{8}T\d{6}$').hasMatch(wall)) {
      return DateTime(
        int.parse(wall.substring(0, 4)),
        int.parse(wall.substring(4, 6)),
        int.parse(wall.substring(6, 8)),
        int.parse(wall.substring(9, 11)),
        int.parse(wall.substring(11, 13)),
        int.parse(wall.substring(13, 15)),
      );
    }
    return null;
  }
}

String _icsDateTime(LocalDateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}T'
    '${value.hour.toString().padLeft(2, '0')}'
    '${value.minute.toString().padLeft(2, '0')}'
    '${value.second.toString().padLeft(2, '0')}';

final class _IcsTodoRecurrence {
  const _IcsTodoRecurrence(
    this.rule, {
    this.spec,
    this.startDate,
    this.dueDate,
    this.evidence,
  });

  factory _IcsTodoRecurrence.legacy(
    String rule, {
    DateTime? startDate,
    DateTime? dueDate,
    LegacyRecurrenceEvidence? evidence,
  }) => _IcsTodoRecurrence(
    rule,
    startDate: startDate,
    dueDate: dueDate,
    evidence: evidence,
  );

  final String rule;
  final RecurrenceSpec? spec;
  final DateTime? startDate;
  final DateTime? dueDate;
  final LegacyRecurrenceEvidence? evidence;
}
