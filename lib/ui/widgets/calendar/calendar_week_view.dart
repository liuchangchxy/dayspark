import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/schedule/day_strip.dart';

const int calStartHour = 7;
const int calEndHour = 22;
const double calGutter = 56;

typedef CalReschedule = void Function(CalBlockItem item, int minutes);

class CalendarWeekGrid extends StatelessWidget {
  const CalendarWeekGrid({
    super.key,
    required this.days,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.now,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onReschedule,
    this.showHeader = true,
  });

  final List<DateTime> days;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final DateTime now;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;
  final CalReschedule? onReschedule;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final today = calDayOf(now);
    final allDay = <DateTime, List<CalendaEventAdapter>>{
      for (final day in days)
        calDayOf(day): calAllDayEvents(day: day, events: events),
    };
    final dayDeadlines = <DateTime, List<CalendarDeadline>>{
      for (final day in days)
        calDayOf(day): [
          for (final deadline in deadlines)
            if (calSameDay(deadline.due, day)) deadline,
        ]..sort((a, b) => a.due.compareTo(b.due)),
    };
    final hasAllDay = allDay.values.any((items) => items.isNotEmpty);
    final hasDeadlines = dayDeadlines.values.any((items) => items.isNotEmpty);

    return LayoutBuilder(
      builder: (context, constraints) {
        final headerHeight = showHeader ? 52.0 : 0.0;
        final allDayHeight = hasAllDay ? 30.0 : 0.0;
        final deadlineHeight = hasDeadlines ? 28.0 : 0.0;
        final gridHeight =
            (constraints.maxHeight -
                    headerHeight -
                    allDayHeight -
                    deadlineHeight)
                .clamp(0.0, double.infinity);
        final hourHeight = gridHeight / (calEndHour - calStartHour);
        final columnWidth = (constraints.maxWidth - calGutter) / days.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              SizedBox(
                height: headerHeight,
                child: Row(
                  children: [
                    const SizedBox(width: calGutter),
                    for (final day in days)
                      Expanded(
                        child: _DayHeader(
                          day: day,
                          locale: locale,
                          today: calSameDay(day, today),
                        ),
                      ),
                  ],
                ),
              ),
            if (hasAllDay)
              SizedBox(
                height: allDayHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: calGutter,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            l.allDay,
                            style: TextStyle(fontSize: 10.5, color: ds.ink3),
                          ),
                        ),
                      ),
                    ),
                    for (final day in days)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: ds.lineSoft),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 4,
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final event
                                    in allDay[calDayOf(day)] ?? const [])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: _AllDayChip(
                                      event: event,
                                      onTap: onEvent == null
                                          ? null
                                          : () => onEvent!(event),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (hasDeadlines)
              SizedBox(
                height: deadlineHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: calGutter,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            l.deadline,
                            style: TextStyle(fontSize: 10.5, color: ds.ink3),
                          ),
                        ),
                      ),
                    ),
                    for (final day in days)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: ds.lineSoft),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          child: _DeadlineCell(
                            deadlines: dayDeadlines[calDayOf(day)] ?? const [],
                            onTap: onDeadline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(
              height: gridHeight,
              child: Stack(
                key: const ValueKey('calendar-time-grid'),
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < days.length; i++)
                    if (calSameDay(days[i], today))
                      Positioned(
                        top: 0,
                        left: calGutter + i * columnWidth,
                        width: columnWidth,
                        height: gridHeight,
                        child: ColoredBox(color: ds.primaryTint),
                      ),
                  for (var hour = 0; hour <= calEndHour - calStartHour; hour++)
                    Positioned(
                      top: hour * hourHeight,
                      left: calGutter,
                      right: 0,
                      child: Container(
                        height: 1,
                        color: hour == 0 || hour == calEndHour - calStartHour
                            ? ds.line
                            : ds.lineSoft,
                      ),
                    ),
                  for (var i = 0; i <= days.length; i++)
                    Positioned(
                      top: 0,
                      left: calGutter + i * columnWidth,
                      width: 1,
                      height: gridHeight,
                      child: ColoredBox(color: ds.lineSoft),
                    ),
                  for (var hour = 0; hour <= calEndHour - calStartHour; hour++)
                    Positioned(
                      top: (hour * hourHeight - (hour == 0 ? 0 : 7)).clamp(
                        0.0,
                        gridHeight > 15 ? gridHeight - 15 : 0.0,
                      ),
                      left: 0,
                      width: calGutter - 8,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Text(
                          '${(calStartHour + hour).toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: ds.ink3,
                            fontFeatures: AppTypography.tabular,
                          ),
                        ),
                      ),
                    ),
                  for (var i = 0; i < days.length; i++)
                    Positioned(
                      top: 0,
                      left: calGutter + i * columnWidth,
                      width: columnWidth,
                      height: gridHeight,
                      child: Semantics(
                        button: true,
                        label: l.emptySlotSemantics,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: onSlot == null
                              ? null
                              : (details) {
                                  final minutes =
                                      (details.localPosition.dy /
                                              hourHeight *
                                              60)
                                          .round();
                                  onSlot!(_slotRange(days[i], minutes));
                                },
                        ),
                      ),
                    ),
                  for (var i = 0; i < days.length; i++)
                    ..._blocks(i, hourHeight, columnWidth, ds),
                  ..._nowLine(context, hourHeight, columnWidth, ds),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  DateTimeRange _slotRange(DateTime day, int minutes) {
    final totalMinutes = ((calEndHour - calStartHour) * 60) - 60;
    final clamped = minutes.clamp(0, totalMinutes);
    var start = DateTime(
      day.year,
      day.month,
      day.day,
      calStartHour,
    ).add(Duration(minutes: clamped));
    start = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      (start.minute ~/ 30) * 30,
    );
    return DateTimeRange(
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
  }

  List<Widget> _blocks(
    int dayIndex,
    double hourHeight,
    double columnWidth,
    DsColors ds,
  ) {
    final day = days[dayIndex];
    final items = calDayBlocks(
      day: day,
      events: events,
      allocations: allocations,
    );
    if (items.isEmpty) return const [];
    final lanes = calPackLanes(items);
    final windowStart = DateTime(day.year, day.month, day.day, calStartHour);
    final windowEnd = DateTime(day.year, day.month, day.day, calEndHour);
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final start = item.start.isBefore(windowStart) ? windowStart : item.start;
      final end = item.end.isAfter(windowEnd) ? windowEnd : item.end;
      if (!end.isAfter(start)) continue;
      final top = start.difference(windowStart).inMinutes / 60 * hourHeight;
      final height = end.difference(start).inMinutes / 60 * hourHeight;
      final laneWidth = columnWidth / lanes[i].lanes;
      widgets.add(
        Positioned(
          top: top,
          left:
              calGutter +
              dayIndex * columnWidth +
              lanes[i].lane * laneWidth +
              1,
          width: laneWidth - 2,
          height: height,
          child: CalBlockTile(
            item: item,
            color: item.color ?? ds.primary,
            hourHeight: hourHeight,
            now: now,
            onTap: item.isAllocation
                ? () => onAllocation?.call(item.allocation!)
                : () => onEvent?.call(item.event!),
            onReschedule: item.canDrag && onReschedule != null
                ? (minutes) => onReschedule!(item, minutes)
                : null,
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _nowLine(
    BuildContext context,
    double hourHeight,
    double columnWidth,
    DsColors ds,
  ) {
    final today = calDayOf(now);
    final index = days.indexWhere((day) => calSameDay(day, today));
    if (index < 0) return const [];
    final windowStart = DateTime(now.year, now.month, now.day, calStartHour);
    final windowEnd = DateTime(now.year, now.month, now.day, calEndHour);
    if (now.isBefore(windowStart) || now.isAfter(windowEnd)) return const [];
    final top = now.difference(windowStart).inMinutes / 60 * hourHeight;
    return [
      Positioned(
        top: top - 1,
        left: calGutter + index * columnWidth,
        width: columnWidth,
        height: 2,
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: ColoredBox(color: ds.primary)),
              Positioned(
                right: 0,
                top: -7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  color: ds.primary,
                  child: Text(
                    DateFormatters.formatTime(now),
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.3,
                      color: ds.onPrimary,
                      fontFeatures: AppTypography.tabular,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.locale,
    required this.today,
  });

  final DateTime day;
  final String locale;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      color: today ? ds.primaryTint : null,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            calWeekdayShort(locale, day),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.2,
              color: today ? ds.primary : ds.ink3,
            ),
          ),
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: today ? ds.primary : ds.ink,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.event, this.onTap});

  final CalendaEventAdapter event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final color = event.color ?? ds.primary;
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 18,
          child: CalEdgeBox(
            edgeColor: color,
            background: ds.tint(color),
            radius: 3,
            edgeWidth: 2,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Center(
              widthFactor: 1,
              child: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: ds.ink2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeadlineCell extends StatelessWidget {
  const _DeadlineCell({required this.deadlines, this.onTap});

  final List<CalendarDeadline> deadlines;
  final void Function(CalendarDeadline)? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    if (deadlines.isEmpty) return const SizedBox.shrink();
    final first = deadlines.first;
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(first),
        child: Text(
          deadlines.length > 1
              ? '${first.title} +${deadlines.length - 1}'
              : first.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, color: ds.warn),
        ),
      ),
    );
  }
}

class CalendarMobileWeekView extends StatelessWidget {
  const CalendarMobileWeekView({
    super.key,
    required this.weekStart,
    required this.selected,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.now,
    required this.onSelectDay,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onReschedule,
  });

  final DateTime weekStart;
  final DateTime selected;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;
  final CalReschedule? onReschedule;

  int _itemCount(DateTime day) {
    return events.where((event) => calSameDay(event.start, day)).length +
        allocations.where((item) => calSameDay(item.start, day)).length +
        deadlines.where((item) => calSameDay(item.due, day)).length;
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final today = calDayOf(now);
    final days = [
      for (var i = 0; i < 7; i++) calDayOf(weekStart).add(Duration(days: i)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _WeekStripCell(
                    day: day,
                    locale: locale,
                    selected: calSameDay(day, selected),
                    today: calSameDay(day, today),
                    itemCount: _itemCount(day),
                    onTap: () => onSelectDay(day),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: CalendarMobileTimeline(
            day: selected,
            events: events,
            allocations: allocations,
            deadlines: deadlines,
            now: now,
            onEvent: onEvent,
            onAllocation: onAllocation,
            onDeadline: onDeadline,
            onSlot: onSlot,
            onReschedule: onReschedule,
          ),
        ),
      ],
    );
  }
}

class _WeekStripCell extends StatelessWidget {
  const _WeekStripCell({
    required this.day,
    required this.locale,
    required this.selected,
    required this.today,
    required this.itemCount,
    required this.onTap,
  });

  final DateTime day;
  final String locale;
  final bool selected;
  final bool today;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            color: selected ? ds.primaryTint : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  calWeekdayShort(locale, day),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: selected || today ? ds.primary : ds.ink3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: selected || today ? ds.primary : ds.ink,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < (itemCount > 3 ? 3 : itemCount); i++)
                        Container(
                          width: 3,
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: selected || today ? ds.primary : ds.ink3,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CalendarMobileDayView extends StatelessWidget {
  const CalendarMobileDayView({
    super.key,
    required this.day,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.now,
    required this.onSelectDay,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onReschedule,
  });

  final DateTime day;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;
  final CalReschedule? onReschedule;

  bool _hasItems(DateTime target) {
    return events.any((event) => calSameDay(event.start, target)) ||
        allocations.any((item) => calSameDay(item.start, target)) ||
        deadlines.any((item) => calSameDay(item.due, target));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DayStrip(selected: day, onPick: onSelectDay, hasItems: _hasItems),
        Expanded(
          child: CalendarMobileTimeline(
            day: day,
            events: events,
            allocations: allocations,
            deadlines: deadlines,
            now: now,
            onEvent: onEvent,
            onAllocation: onAllocation,
            onDeadline: onDeadline,
            onSlot: onSlot,
            onReschedule: onReschedule,
          ),
        ),
      ],
    );
  }
}

class CalendarMobileTimeline extends StatelessWidget {
  const CalendarMobileTimeline({
    super.key,
    required this.day,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.now,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onReschedule,
  });

  final DateTime day;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final DateTime now;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;
  final CalReschedule? onReschedule;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final target = calDayOf(day);
    final blocks = calDayBlocks(
      day: target,
      events: events,
      allocations: allocations,
    );
    final allDay = calAllDayEvents(day: target, events: events);
    final dayDeadlines = [
      for (final deadline in deadlines)
        if (calSameDay(deadline.due, target)) deadline,
    ]..sort((a, b) => a.due.compareTo(b.due));
    final gaps = calFreeGaps(
      day: target,
      items: blocks,
      startHour: calStartHour,
      endHour: calEndHour,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allDay.isNotEmpty)
          _MobileEventStrip(events: allDay, onEvent: onEvent),
        if (dayDeadlines.isNotEmpty)
          _MobileDeadlineStrip(deadlines: dayDeadlines, onTap: onDeadline),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gridHeight = constraints.maxHeight.clamp(
                  0.0,
                  double.infinity,
                );
                final hourHeight = gridHeight / (calEndHour - calStartHour);
                final laneWidth = constraints.maxWidth - calGutter;
                return Stack(
                  key: const ValueKey('calendar-mobile-time-grid'),
                  clipBehavior: Clip.none,
                  children: [
                    for (
                      var hour = 0;
                      hour <= calEndHour - calStartHour;
                      hour++
                    )
                      Positioned(
                        top: hour * hourHeight,
                        left: calGutter,
                        right: 0,
                        child: Container(
                          height: 1,
                          color: hour == 0 || hour == calEndHour - calStartHour
                              ? ds.line
                              : ds.lineSoft,
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: calGutter,
                      width: 1,
                      height: gridHeight,
                      child: ColoredBox(color: ds.lineSoft),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      width: 1,
                      height: gridHeight,
                      child: ColoredBox(color: ds.lineSoft),
                    ),
                    for (
                      var hour = 0;
                      hour <= calEndHour - calStartHour;
                      hour++
                    )
                      Positioned(
                        top: (hour * hourHeight - (hour == 0 ? 0 : 7)).clamp(
                          0.0,
                          gridHeight > 15 ? gridHeight - 15 : 0.0,
                        ),
                        left: 0,
                        width: calGutter - 8,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Text(
                            '${(calStartHour + hour).toString().padLeft(2, '0')}:00',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: ds.ink3,
                              fontFeatures: AppTypography.tabular,
                            ),
                          ),
                        ),
                      ),
                    for (final gap in gaps)
                      Positioned(
                        top: _top(gap.start, target, hourHeight),
                        left: calGutter,
                        width: laneWidth,
                        height: gap.duration.inMinutes / 60 * hourHeight,
                        child: IgnorePointer(child: _FreeBand(gap: gap)),
                      ),
                    Positioned(
                      top: 0,
                      left: calGutter,
                      width: laneWidth,
                      height: gridHeight,
                      child: Semantics(
                        button: true,
                        label: l.emptySlotSemantics,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: onSlot == null
                              ? null
                              : (details) {
                                  final minutes =
                                      (details.localPosition.dy /
                                              hourHeight *
                                              60)
                                          .round();
                                  onSlot!(_slotRange(target, minutes));
                                },
                        ),
                      ),
                    ),
                    ..._blocks(target, blocks, hourHeight, laneWidth, ds),
                    ..._nowLine(context, hourHeight, laneWidth),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  DateTimeRange _slotRange(DateTime target, int minutes) {
    final totalMinutes = ((calEndHour - calStartHour) * 60) - 60;
    final clamped = minutes.clamp(0, totalMinutes);
    var start = DateTime(
      target.year,
      target.month,
      target.day,
      calStartHour,
    ).add(Duration(minutes: clamped));
    start = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      (start.minute ~/ 30) * 30,
    );
    return DateTimeRange(
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
  }

  double _top(DateTime value, DateTime target, double hourHeight) {
    final windowStart = DateTime(
      target.year,
      target.month,
      target.day,
      calStartHour,
    );
    return value.difference(windowStart).inMinutes / 60 * hourHeight;
  }

  List<Widget> _blocks(
    DateTime target,
    List<CalBlockItem> items,
    double hourHeight,
    double width,
    DsColors ds,
  ) {
    if (items.isEmpty) return const [];
    final lanes = calPackLanes(items);
    final windowStart = DateTime(
      target.year,
      target.month,
      target.day,
      calStartHour,
    );
    final windowEnd = DateTime(
      target.year,
      target.month,
      target.day,
      calEndHour,
    );
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final start = item.start.isBefore(windowStart) ? windowStart : item.start;
      final end = item.end.isAfter(windowEnd) ? windowEnd : item.end;
      if (!end.isAfter(start)) continue;
      final top = start.difference(windowStart).inMinutes / 60 * hourHeight;
      final visualHeight = end.difference(start).inMinutes / 60 * hourHeight;
      final hitHeight = visualHeight < 44 ? 44.0 : visualHeight;
      final laneWidth = width / lanes[i].lanes;
      final left = calGutter + lanes[i].lane * laneWidth + 1;
      widgets.add(
        Positioned(
          top: top,
          left: left,
          width: laneWidth - 2,
          height: hitHeight,
          child: CalBlockTile(
            item: item,
            color: item.color ?? ds.primary,
            hourHeight: hourHeight,
            now: now,
            mobile: true,
            visualHeight: visualHeight,
            onTap: item.isAllocation
                ? () => onAllocation?.call(item.allocation!)
                : () => onEvent?.call(item.event!),
            onReschedule: item.canDrag && onReschedule != null
                ? (minutes) => onReschedule!(item, minutes)
                : null,
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _nowLine(BuildContext context, double hourHeight, double width) {
    if (!calSameDay(day, now)) return const [];
    final windowStart = DateTime(now.year, now.month, now.day, calStartHour);
    final windowEnd = DateTime(now.year, now.month, now.day, calEndHour);
    if (now.isBefore(windowStart) || now.isAfter(windowEnd)) return const [];
    final ds = context.ds;
    final top = now.difference(windowStart).inMinutes / 60 * hourHeight;
    return [
      Positioned(
        top: top - 1,
        left: calGutter,
        width: width,
        height: 2,
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: ColoredBox(color: ds.primary)),
              Positioned(
                left: -3,
                top: -2,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: ds.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  color: ds.primary,
                  child: Text(
                    DateFormatters.formatTime(now),
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.4,
                      color: ds.onPrimary,
                      fontFeatures: AppTypography.tabular,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _FreeBand extends StatelessWidget {
  const _FreeBand({required this.gap});

  final CalGap gap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final compact = gap.duration.inMinutes < 35;
    return Container(
      decoration: BoxDecoration(
        color: ds.free,
        border: Border(
          top: BorderSide(color: ds.lineSoft),
          bottom: BorderSide(color: ds.lineSoft),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ds.ink3),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              l.freeFor(calDuration(l, gap.duration)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: ds.ink3),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            Text(
              calTimeRange(gap.start, gap.end),
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                color: ds.ink3,
                fontFeatures: AppTypography.tabular,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileEventStrip extends StatelessWidget {
  const _MobileEventStrip({required this.events, this.onEvent});

  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter)? onEvent;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final event = events[index];
          final color = event.color ?? ds.primary;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEvent == null ? null : () => onEvent!(event),
                child: SizedBox(
                  height: 28,
                  child: CalEdgeBox(
                    edgeColor: color,
                    background: ds.tint(color),
                    radius: 6,
                    edgeWidth: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: ds.ink2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileDeadlineStrip extends StatelessWidget {
  const _MobileDeadlineStrip({required this.deadlines, this.onTap});

  final List<CalendarDeadline> deadlines;
  final void Function(CalendarDeadline)? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        itemCount: deadlines.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final deadline = deadlines[index];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Semantics(
                button: onTap != null,
                label: '${l.deadline}: ${deadline.title}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap == null ? null : () => onTap!(deadline),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: ds.warnSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.flag, size: 11, color: ds.warn),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            deadline.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: ds.warn),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
