import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';

class KalenderTaskAllocation extends CalendarEvent {
  KalenderTaskAllocation({
    required this.allocation,
    required super.dateTimeRange,
    required super.interaction,
    required super.id,
  });

  final TaskAllocationCalendarAdapter allocation;

  factory KalenderTaskAllocation.fromAdapter(
    TaskAllocationCalendarAdapter allocation,
  ) {
    // Kalender lays out wall-clock dates; the adapter retains UTC instants
    // for persistence and sync.
    return KalenderTaskAllocation(
      allocation: allocation,
      dateTimeRange: DateTimeRange(
        start: allocation.start.toLocal(),
        end: allocation.end.toLocal(),
      ),
      interaction: EventInteraction.allowAll(),
      id: 'task-allocation-${allocation.id}',
    );
  }

  @override
  bool layoutEquals(CalendarEvent other) =>
      other is KalenderTaskAllocation &&
      super.layoutEquals(other) &&
      other.allocation.todoTitle == allocation.todoTitle;

  @override
  KalenderTaskAllocation copyWith({
    DateTimeRange? dateTimeRange,
    EventInteraction? interaction,
  }) => KalenderTaskAllocation(
    allocation: allocation,
    dateTimeRange: dateTimeRange ?? this.dateTimeRange,
    interaction: interaction ?? this.interaction,
    id: id,
  );
}
