import 'dart:io';

import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/local/database/app_database.dart';
import '../../data/remote/caldav/ical_converter.dart';

/// Import/export .ics files.
class IcsService {
  final AppDatabase _db;
  final IcalConverter _converter = IcalConverter();

  IcsService(this._db);

  /// Export all events from a calendar to a .ics file.
  Future<String> exportCalendar(int calendarId) async {
    final events = await (_db.select(_db.events)
          ..where((t) => t.calendarId.equals(calendarId)))
        .get();
    final todos = await (_db.select(_db.todos)
          ..where((t) => t.calendarId.equals(calendarId)))
        .get();

    final cal = VCalendar();
    cal.productId = '-//CalendarTodoApp//EN';
    cal.version = '2.0';

    for (final event in events) {
      final vevent = VEvent();
      vevent.uid = event.uid;
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
      vtodo.uid = todo.uid;
      vtodo.summary = todo.summary;
      vtodo.timeStamp = todo.updatedAt;
      if (todo.dueDate != null) vtodo.due = todo.dueDate;
      if (todo.description != null) vtodo.description = todo.description;
      if (todo.priority > 0) vtodo.priorityInt = todo.priority;
      vtodo.status = _converter.mapTodoStatus(todo.status);
      if (todo.rrule != null && todo.rrule!.isNotEmpty) {
        vtodo.recurrenceRule = Recurrence.parse(todo.rrule!);
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
      String icsContent, int calendarId) async {
    final component = VComponent.parse(icsContent);
    if (component is! VCalendar) {
      throw FormatException('Not a valid VCALENDAR');
    }

    int events = 0;
    int todos = 0;

    for (final child in component.children) {
      if (child is VEvent) {
        try {
          final childCal = VCalendar();
          childCal.productId = '-//CalendarTodoApp//EN';
          childCal.children.add(child);
          final companion = _converter.icalToEventCompanion(
            childCal.toString(),
            calendarId,
            null,
            null,
          );
          await _db.into(_db.events).insertOnConflictUpdate(
                Event(
                  id: -1,
                  calendarId: companion.calendarId.value,
                  uid: companion.uid.value,
                  summary: companion.summary.value,
                  startDt: companion.startDt.value,
                  endDt: companion.endDt.value,
                  isAllDay: companion.isAllDay.value,
                  description: companion.description.present
                      ? companion.description.value
                      : null,
                  location: companion.location.present
                      ? companion.location.value
                      : null,
                  rrule: companion.rrule.present ? companion.rrule.value : null,
                  etag: companion.etag.present ? companion.etag.value : null,
                  isDirty: true,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
          events++;
        } catch (_) {}
      } else if (child is VTodo) {
        try {
          final childCal = VCalendar();
          childCal.productId = '-//CalendarTodoApp//EN';
          childCal.children.add(child);
          final companion = _converter.icalToTodoCompanion(
            childCal.toString(),
            calendarId,
            null,
            null,
          );
          await _db.into(_db.todos).insertOnConflictUpdate(
                Todo(
                  id: -1,
                  calendarId: companion.calendarId.value,
                  uid: companion.uid.value,
                  summary: companion.summary.value,
                  dueDate: companion.dueDate.present
                      ? companion.dueDate.value
                      : null,
                  startDate: companion.startDate.present
                      ? companion.startDate.value
                      : null,
                  priority: companion.priority.present
                      ? companion.priority.value
                      : 0,
                  status: companion.status.present
                      ? companion.status.value
                      : 'NEEDS-ACTION',
                  description: companion.description.present
                      ? companion.description.value
                      : null,
                  rrule: companion.rrule.present ? companion.rrule.value : null,
                  completedAt: companion.completedAt.present
                      ? companion.completedAt.value
                      : null,
                  percentComplete: companion.percentComplete.present
                      ? companion.percentComplete.value
                      : 0,
                  etag: companion.etag.present ? companion.etag.value : null,
                  isDirty: true,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
          todos++;
        } catch (_) {}
      }
    }

    return (events: events, todos: todos);
  }

}
