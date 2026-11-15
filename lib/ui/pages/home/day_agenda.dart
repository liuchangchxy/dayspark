import 'package:flutter/material.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';

/// One row of a day projection, whatever produced it.
///
/// The domain keeps Event time, TaskAllocation and `Todo.dueDate` apart; this
/// type is where they meet for display, and its [kind] is what stops the UI
/// from ever rendering one of them as another.
enum DayItemKind { event, allocation, deadline, instance }

class DayItem {
  const DayItem({
    required this.kind,
    required this.title,
    this.start,
    this.end,
    this.todo,
    this.event,
    this.allocation,
    this.occurrenceId,
    this.calendarName,
    this.calendarColor,
    this.completed = false,
    this.allDay = false,
  });

  final DayItemKind kind;
  final String title;

  /// Null for a bare deadline and for a DATE-valued recurring instance: those
  /// are facts about a day, not spans inside it.
  final DateTime? start;
  final DateTime? end;

  final Todo? todo;
  final CalendaEventAdapter? event;
  final TaskAllocationCalendarItem? allocation;
  final String? occurrenceId;
  final String? calendarName;
  final Color? calendarColor;
  final bool completed;
  final bool allDay;

  bool get isTimed => start != null && !allDay;
  int get todoId => todo?.id ?? allocation?.todo.id ?? -1;

}

/// The day as the app shows it: the same Todo appears once, the allocation
/// leading and the deadline reduced to secondary metadata (SPEC rule 20).
class DayAgenda {
  const DayAgenda({
    required this.day,
    required this.events,
    required this.allocations,
    required this.dueTodos,
    required this.overdueTodos,
    required this.instances,
  });

  final DateTime day;
  final List<DayItem> events;
  final List<DayItem> allocations;
  final List<DayItem> dueTodos;
  final List<DayItem> overdueTodos;
  final List<DayItem> instances;

  bool get isEmpty =>
      events.isEmpty &&
      allocations.isEmpty &&
      dueTodos.isEmpty &&
      overdueTodos.isEmpty &&
      instances.isEmpty;

  /// Everything that occupies the day's timeline, in clock order.
  List<DayItem> get timed {
    final all = [...events, ...allocations]
      ..sort((a, b) => a.start!.compareTo(b.start!));
    return all;
  }

  factory DayAgenda.build({
    required DateTime day,
    required List<CalendaEventAdapter> events,
    required List<TaskAllocationCalendarItem> allocations,
    required List<Todo> dueTodos,
    List<Todo> overdueTodos = const [],
    List<ProjectedTaskInstance> instances = const [],
    Map<int, String> calendarNames = const {},
    Map<int, Color> calendarColors = const {},
  }) {
    final target = DateTime(day.year, day.month, day.day);
    final dayStart = target;
    final dayEnd = target.add(const Duration(days: 1));
    final dayEvents = <DayItem>[
      for (final event in events)
        if (event.start.isBefore(dayEnd) && event.end.isAfter(dayStart))
          DayItem(
            kind: DayItemKind.event,
            title: event.title,
            start: event.start,
            end: event.end,
            event: event,
            allDay: event.isAllDay,
            calendarName: calendarNames[event.calendarId],
            calendarColor: event.color ?? calendarColors[event.calendarId],
          ),
    ];
    final dayAllocations = <DayItem>[
      for (final item in allocations)
        if (item.allocation.startAt.toLocal().year == target.year &&
            item.allocation.startAt.toLocal().month == target.month &&
            item.allocation.startAt.toLocal().day == target.day)
          DayItem(
            kind: DayItemKind.allocation,
            title: item.todo.summary,
            start: item.allocation.startAt.toLocal(),
            end: item.allocation.endAt.toLocal(),
            todo: item.todo,
            allocation: item,
            occurrenceId: item.allocation.occurrenceId,
            calendarName: calendarNames[item.todo.calendarId],
            calendarColor: calendarColors[item.todo.calendarId],
            completed: item.todo.status == 'COMPLETED',
          ),
    ];

    // One Todo, one row: an allocation already carries the todo, so its
    // deadline must not appear a second time as a block.
    final allocatedToday = dayAllocations.map((item) => item.todoId).toSet();

    // A planned occurrence is the same obligation as its pending instance:
    // the allocation leads, the instance row stays out.
    final plannedOccurrences = <String>{
      for (final item in dayAllocations)
        if (item.allocation?.allocation.occurrenceId != null)
          item.allocation!.allocation.occurrenceId!,
    };

    DayItem deadlineRow(Todo todo) {
      final due = todo.dueDate;
      final hasTime = due != null && (due.hour != 0 || due.minute != 0);
      return DayItem(
        kind: DayItemKind.deadline,
        title: todo.summary,
        start: hasTime ? due : null,
        todo: todo,
        calendarName: calendarNames[todo.calendarId],
        calendarColor: calendarColors[todo.calendarId],
        completed: todo.status == 'COMPLETED',
      );
    }

    final due = <DayItem>[
      for (final todo in dueTodos)
        if (!allocatedToday.contains(todo.id)) deadlineRow(todo),
    ];
    // Stable: the source list is already in the user's manual order, and a
    // timed deadline only refines it rather than reshuffling equal ones.
    final dueIndexed = <(int, DayItem)>[
      for (var index = 0; index < due.length; index++) (index, due[index]),
    ]..sort((a, b) {
        final at = a.$2.start;
        final bt = b.$2.start;
        if (at == null && bt == null) return a.$1.compareTo(b.$1);
        if (at == null) return 1;
        if (bt == null) return -1;
        final byTime = at.compareTo(bt);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    final orderedDue = <DayItem>[for (final pair in dueIndexed) pair.$2];

    final overdue = <DayItem>[
      for (final todo in overdueTodos)
        if (!allocatedToday.contains(todo.id)) deadlineRow(todo),
    ];

    final recurring = <DayItem>[
      for (final instance in instances)
        if (instance.isPending &&
            !plannedOccurrences.contains(instance.occurrenceId))
          DayItem(
            kind: DayItemKind.instance,
            title: instance.todo.summary,
            start: instance.occurrence.resolvedStartInstant?.toLocal(),
            todo: instance.todo,
            occurrenceId: instance.occurrenceId,
            calendarName: calendarNames[instance.todo.calendarId],
            calendarColor: calendarColors[instance.todo.calendarId],
          ),
    ];

    return DayAgenda(
      day: target,
      events: dayEvents,
      allocations: dayAllocations,
      dueTodos: orderedDue,
      overdueTodos: overdue,
      instances: recurring,
    );
  }
}
