import 'package:drift/drift.dart';
import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:flutter/foundation.dart';

import '../../../data/local/database/app_database.dart';

class IcalConverter {
  String eventToIcal(Event event) {
    final cal = VCalendar();
    cal.productId = '-//CalendarTodoApp//EN';

    final vevent = VEvent();
    // Events have no uid column since schema v8; synthesize a stable UID for export.
    vevent.uid = 'dayspark-event-${event.id}@dayspark';
    vevent.summary = event.summary;
    vevent.start = event.startDt;
    vevent.end = event.endDt;
    vevent.timeStamp = DateTime.now();

    if (event.description != null) {
      vevent.description = event.description;
    }
    if (event.location != null) {
      vevent.location = event.location;
    }
    if (event.rrule != null && event.rrule!.isNotEmpty) {
      final recurrence = Recurrence.parse(event.rrule!);
      vevent.recurrenceRule = recurrence;
    }

    cal.children.add(vevent);
    return cal.toString();
  }

  String todoToIcal(Todo todo) {
    final cal = VCalendar();
    cal.productId = '-//CalendarTodoApp//EN';

    final vtodo = VTodo();
    // Todos have no uid column since schema v8; synthesize a stable UID for export.
    vtodo.uid = 'dayspark-todo-${todo.id}@dayspark';
    vtodo.summary = todo.summary;
    vtodo.timeStamp = DateTime.now();

    if (todo.dueDate != null) {
      vtodo.due = todo.dueDate;
    }
    if (todo.startDate != null) {
      vtodo.start = todo.startDate;
    }
    if (todo.description != null) {
      vtodo.description = todo.description;
    }
    if (todo.priority > 0) {
      vtodo.priorityInt = todo.priority;
    }
    if (todo.percentComplete > 0) {
      vtodo.percentComplete = todo.percentComplete;
    }
    if (todo.completedAt != null) {
      vtodo.completed = todo.completedAt;
    }

    vtodo.status = mapTodoStatus(todo.status);

    if (todo.rrule != null && todo.rrule!.isNotEmpty) {
      final recurrence = Recurrence.parse(todo.rrule!);
      vtodo.recurrenceRule = recurrence;
    }

    cal.children.add(vtodo);
    return cal.toString();
  }

  EventsCompanion icalToEventCompanion(String icalData, int calendarId) {
    final component = VComponent.parse(icalData);
    if (component is! VCalendar) {
      throw FormatException('Expected VCALENDAR, got ${component.name}');
    }

    final vevent = component.event;
    if (vevent == null) {
      throw FormatException('No VEVENT found in iCalendar data');
    }

    final start = vevent.start;
    if (start == null) {
      throw FormatException('VEVENT missing DTSTART');
    }
    final end = vevent.end ?? start.add(const Duration(hours: 1));
    final isAllDay = _isAllDay(vevent);

    return EventsCompanion.insert(
      calendarId: calendarId,
      summary: vevent.summary ?? '',
      startDt: start,
      endDt: end,
      isAllDay: Value(isAllDay),
      description: Value(vevent.description),
      location: Value(vevent.location),
      rrule: Value(vevent.recurrenceRule?.toString()),
    );
  }

  TodosCompanion icalToTodoCompanion(String icalData, int calendarId) {
    final component = VComponent.parse(icalData);
    if (component is! VCalendar) {
      throw FormatException('Expected VCALENDAR, got ${component.name}');
    }

    final vtodo = component.todo;
    if (vtodo == null) {
      throw FormatException('No VTODO found in iCalendar data');
    }

    return TodosCompanion.insert(
      calendarId: calendarId,
      summary: vtodo.summary ?? '',
      priority: Value(vtodo.priorityInt ?? 0),
      status: Value(_todoStatusToString(vtodo.status)),
      dueDate: Value(vtodo.due),
      description: Value(vtodo.description),
      rrule: Value(vtodo.recurrenceRule?.toString()),
      startDate: Value(vtodo.start),
      completedAt: Value(vtodo.completed),
      percentComplete: Value(vtodo.percentComplete ?? 0),
    );
  }

  String? detectComponentType(String icalData) {
    try {
      final component = VComponent.parse(icalData);
      if (component is! VCalendar) return null;

      if (component.event != null) return 'VEVENT';
      if (component.todo != null) return 'VTODO';
      return null;
    } catch (e) {
      debugPrint('ical: detectType error: $e');
      return null;
    }
  }

  bool _isAllDay(VEvent event) {
    final start = event.start;
    if (start == null) return false;
    final end = event.end;
    if (end != null) {
      return start.hour == 0 &&
          start.minute == 0 &&
          start.second == 0 &&
          end.hour == 0 &&
          end.minute == 0 &&
          end.second == 0;
    }
    return false;
  }

  TodoStatus mapTodoStatus(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return TodoStatus.completed;
      case 'IN-PROCESS':
      case 'INPROCESS':
        return TodoStatus.inProcess;
      case 'CANCELLED':
        return TodoStatus.cancelled;
      case 'NEEDS-ACTION':
      default:
        return TodoStatus.needsAction;
    }
  }

  String _todoStatusToString(TodoStatus status) {
    switch (status) {
      case TodoStatus.completed:
        return 'COMPLETED';
      case TodoStatus.inProcess:
        return 'IN-PROCESS';
      case TodoStatus.cancelled:
        return 'CANCELLED';
      case TodoStatus.needsAction:
      case TodoStatus.unknown:
        return 'NEEDS-ACTION';
    }
  }
}
