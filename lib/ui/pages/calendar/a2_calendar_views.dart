import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';

const double _a2Gutter = 56;
const double _a2HourHeight = 88;
const int _a2StartHour = 12;
const int _a2EndHour = 18;

TextStyle _a2Text(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
  bool tabular = false,
}) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    fontFeatures: tabular ? AppTypography.tabular : null,
  );
  if (AppTypography.fallback.isEmpty) return style;
  return style.copyWith(fontFamilyFallback: AppTypography.fallback);
}

List<TaskAllocationCalendarAdapter> _adapt(
  List<TaskAllocationCalendarItem> allocations,
) {
  return [
    for (final item in allocations)
      TaskAllocationCalendarAdapter.fromItem(item),
  ];
}

TaskAllocationCalendarItem? _findAllocation(
  List<TaskAllocationCalendarItem> allocations,
  int id,
) {
  for (final item in allocations) {
    if (item.allocation.id == id) return item;
  }
  return null;
}

String _calendarName(Map<int, String> names, int calendarId) {
  final name = names[calendarId];
  return name == null || name.isEmpty ? '' : name;
}

String _blockMeta(
  CalBlockItem item,
  Map<int, String> names,
  Map<int, TaskAllocationCalendarItem> allocationItems,
) {
  final time = calTimeRange(item.start, item.end);
  final event = item.event;
  final allocation = item.allocation;
  final String name;
  if (event != null) {
    name = _calendarName(names, event.calendarId);
  } else if (allocation != null) {
    final item = allocationItems[allocation.id];
    name = item == null ? '' : _calendarName(names, item.todo.calendarId);
  } else {
    name = '';
  }
  if (name.isEmpty) return time;
  return '$time · $name';
}

class A2MonthStrip extends StatelessWidget {
  const A2MonthStrip({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          _A2NavButton(
            icon: CupertinoIcons.chevron_left,
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _a2Text(
                14,
                FontWeight.w600,
                ds.ink,
                height: 1.4,
                tabular: true,
              ),
            ),
          ),
          _A2NavButton(
            icon: CupertinoIcons.chevron_right,
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _A2NavButton extends StatelessWidget {
  const _A2NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onPressed,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 36,
              child: Center(child: Icon(icon, size: 14, color: ds.ink3)),
            ),
          ),
        ),
      ),
    );
  }
}

class A2PhoneMonthGrid extends StatelessWidget {
  const A2PhoneMonthGrid({
    super.key,
    required this.anchor,
    required this.selected,
    required this.today,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.onSelectDay,
  });

  final DateTime anchor;
  final DateTime selected;
  final DateTime today;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(anchor.year, anchor.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final rows = <Widget>[];
    for (var row = 0; row < 6; row++) {
      rows.add(
        Expanded(
          child: Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _A2PhoneMonthCell(
                    key: ValueKey(
                      'month-day-${gridStart.add(Duration(days: row * 7 + col)).year}'
                      '-${gridStart.add(Duration(days: row * 7 + col)).month}'
                      '-${gridStart.add(Duration(days: row * 7 + col)).day}',
                    ),
                    date: gridStart.add(Duration(days: row * 7 + col)),
                    inMonth:
                        gridStart.add(Duration(days: row * 7 + col)).month ==
                        anchor.month,
                    isToday: calSameDay(
                      gridStart.add(Duration(days: row * 7 + col)),
                      today,
                    ),
                    isSelected: calSameDay(
                      gridStart.add(Duration(days: row * 7 + col)),
                      selected,
                    ),
                    count: _entriesFor(
                      gridStart.add(Duration(days: row * 7 + col)),
                      events,
                      allocations,
                      deadlines,
                    ).length,
                    lastColumn: col == 6,
                    lastRow: row == 5,
                    onTap: () => onSelectDay(
                      gridStart.add(Duration(days: row * 7 + col)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ds.surface,
        border: Border.all(color: ds.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        calWeekdayShort(
                          locale,
                          gridStart.add(Duration(days: i)),
                        ),
                        style: _a2Text(11, FontWeight.w400, ds.ink3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: Column(children: rows)),
        ],
      ),
    );
  }
}

class _A2PhoneMonthCell extends StatelessWidget {
  const _A2PhoneMonthCell({
    super.key,
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.count,
    required this.lastColumn,
    required this.lastRow,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final int count;
  final bool lastColumn;
  final bool lastRow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final dots = math.min(count, 3);
    final background = isToday
        ? ds.primaryTint
        : (isSelected ? ds.surface2 : Colors.transparent);
    final Color numberColor;
    final FontWeight numberWeight;
    if (isToday) {
      numberColor = ds.primary;
      numberWeight = FontWeight.w600;
    } else if (!inMonth) {
      numberColor = ds.ink3.withValues(alpha: 0.35);
      numberWeight = FontWeight.w500;
    } else if (isSelected) {
      numberColor = ds.ink;
      numberWeight = FontWeight.w600;
    } else {
      numberColor = ds.ink;
      numberWeight = FontWeight.w500;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: background,
            border: Border(
              right: lastColumn
                  ? BorderSide.none
                  : BorderSide(color: ds.lineSoft),
              bottom: lastRow
                  ? BorderSide.none
                  : BorderSide(color: ds.lineSoft),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.day}',
                style: _a2Text(
                  12.5,
                  numberWeight,
                  numberColor,
                  height: 1,
                  tabular: true,
                ),
              ),
              if (dots > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < dots; i++)
                      Container(
                        width: 3.5,
                        height: 3.5,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday || isSelected ? ds.primary : ds.ink3,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class A2DesktopMonthGrid extends StatelessWidget {
  const A2DesktopMonthGrid({
    super.key,
    required this.anchor,
    required this.selected,
    required this.today,
    required this.now,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.calendarNames,
    required this.onSelectDay,
    required this.onSlot,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
  });

  final DateTime anchor;
  final DateTime selected;
  final DateTime today;
  final DateTime now;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final Map<int, String> calendarNames;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTimeRange>? onSlot;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(anchor.year, anchor.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final rows = <Widget>[];
    for (var row = 0; row < 6; row++) {
      rows.add(
        Expanded(
          child: Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _A2DesktopMonthCell(
                    date: gridStart.add(Duration(days: row * 7 + col)),
                    inMonth:
                        gridStart.add(Duration(days: row * 7 + col)).month ==
                        anchor.month,
                    isToday: calSameDay(
                      gridStart.add(Duration(days: row * 7 + col)),
                      today,
                    ),
                    isSelected: calSameDay(
                      gridStart.add(Duration(days: row * 7 + col)),
                      selected,
                    ),
                    firstColumn: col == 0,
                    entries: _entriesFor(
                      gridStart.add(Duration(days: row * 7 + col)),
                      events,
                      allocations,
                      deadlines,
                    ),
                    now: now,
                    onSelectDay: onSelectDay,
                    onSlot: onSlot,
                    onEvent: onEvent,
                    onAllocation: onAllocation,
                    onDeadline: onDeadline,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 26,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        calWeekdayShort(
                          locale,
                          gridStart.add(Duration(days: i)),
                        ),
                        style: _a2Text(11, FontWeight.w400, ds.ink3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: Column(children: rows)),
      ],
    );
  }
}

class _A2DesktopMonthCell extends StatelessWidget {
  const _A2DesktopMonthCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.firstColumn,
    required this.entries,
    required this.now,
    required this.onSelectDay,
    required this.onSlot,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool firstColumn;
  final List<_A2MonthEntry> entries;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTimeRange>? onSlot;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final background = isToday
        ? ds.primaryTint
        : (isSelected ? ds.surface2 : Colors.transparent);
    final Color numberColor;
    final FontWeight numberWeight;
    if (isToday) {
      numberColor = ds.primary;
      numberWeight = FontWeight.w600;
    } else if (!inMonth) {
      numberColor = ds.ink3.withValues(alpha: 0.35);
      numberWeight = FontWeight.w500;
    } else if (isSelected) {
      numberColor = ds.ink;
      numberWeight = FontWeight.w600;
    } else {
      numberColor = ds.ink;
      numberWeight = FontWeight.w500;
    }
    final visible = entries.take(3).toList();
    final hidden = entries.length - visible.length;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelectDay(date),
        onDoubleTap: onSlot == null
            ? null
            : () => onSlot!(_nextHourSlot(date, now)),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: background,
            border: Border(
              top: BorderSide(color: ds.lineSoft),
              left: firstColumn
                  ? BorderSide.none
                  : BorderSide(color: ds.lineSoft),
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.day}',
                style: _a2Text(
                  12.5,
                  numberWeight,
                  numberColor,
                  height: 1,
                  tabular: true,
                ),
              ),
              const SizedBox(height: 3),
              for (final entry in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _A2MonthChip(
                    entry: entry,
                    onEvent: onEvent,
                    onAllocation: onAllocation,
                    onDeadline: onDeadline,
                  ),
                ),
              if (hidden > 0)
                Text(
                  '+$hidden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _a2Text(11, FontWeight.w400, ds.ink3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _A2MonthChip extends StatelessWidget {
  const _A2MonthChip({
    required this.entry,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
  });

  final _A2MonthEntry entry;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final event = entry.event;
    final allocation = entry.allocation;
    final deadline = entry.deadline;
    final Color background;
    final Color edge;
    final Color textColor;
    if (event != null) {
      final accent = ds.eventAccent(event.color ?? ds.primary);
      background = ds.tint(accent);
      edge = accent;
      textColor = ds.ink;
    } else if (allocation != null) {
      background = ds.workBg;
      edge = ds.work;
      textColor = ds.ink2;
    } else {
      background = Colors.transparent;
      edge = ds.warn;
      textColor = ds.warn;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (event != null) onEvent?.call(event);
        if (allocation != null) onAllocation?.call(allocation);
        if (deadline != null) onDeadline?.call(deadline);
      },
      onDoubleTap: () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(2),
          border: Border(left: BorderSide(color: edge, width: 2)),
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _a2Text(11, FontWeight.w400, textColor, height: 1.35),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              entry.time,
              maxLines: 1,
              style: _a2Text(11, FontWeight.w400, textColor, height: 1.35)
                  .copyWith(fontFeatures: AppTypography.tabular),
            ),
          ],
        ),
      ),
    );
  }
}

class _A2MonthEntry {
  const _A2MonthEntry.event(CalendaEventAdapter value)
    : event = value,
      allocation = null,
      deadline = null;

  const _A2MonthEntry.allocation(TaskAllocationCalendarItem value)
    : event = null,
      allocation = value,
      deadline = null;

  const _A2MonthEntry.deadline(CalendarDeadline value)
    : event = null,
      allocation = null,
      deadline = value;

  final CalendaEventAdapter? event;
  final TaskAllocationCalendarItem? allocation;
  final CalendarDeadline? deadline;

  String get title =>
      event?.title ?? allocation?.todo.summary ?? deadline!.title;

  /// The chip reads "title 14:30": a month cell has no time axis, so the slot
  /// is the second thing a reader needs and it must not be what ellipsizes.
  String get time {
    final value =
        event?.start ?? allocation?.allocation.startAt.toLocal() ?? deadline!.due;
    return DateFormatters.formatTime(value);
  }
}

List<_A2MonthEntry> _entriesFor(
  DateTime day,
  List<CalendaEventAdapter> events,
  List<TaskAllocationCalendarItem> allocations,
  List<CalendarDeadline> deadlines,
) {
  final entries = <_A2MonthEntry>[
    for (final event in calAllDayEvents(day: day, events: events))
      _A2MonthEntry.event(event),
  ];
  for (final block in calDayBlocks(
    day: day,
    events: events,
    allocations: _adapt(allocations),
  )) {
    final event = block.event;
    if (event != null) {
      entries.add(_A2MonthEntry.event(event));
      continue;
    }
    final allocation = block.allocation;
    if (allocation == null) continue;
    final item = _findAllocation(allocations, allocation.id);
    if (item != null) entries.add(_A2MonthEntry.allocation(item));
  }
  for (final deadline in deadlines) {
    if (calSameDay(deadline.due, day)) {
      entries.add(_A2MonthEntry.deadline(deadline));
    }
  }
  return entries;
}

class A2TimeGridView extends StatelessWidget {
  const A2TimeGridView({
    super.key,
    required this.days,
    required this.selected,
    required this.now,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.calendarNames,
    required this.dayMode,
    this.onSelectDay,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onReschedule,
  });

  final List<DateTime> days;
  final DateTime selected;
  final DateTime now;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final Map<int, String> calendarNames;
  final bool dayMode;
  final ValueChanged<DateTime>? onSelectDay;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;
  final ValueChanged<DateTimeRange>? onSlot;
  final void Function(CalBlockItem item, int minutes)? onReschedule;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final adapters = _adapt(allocations);
    final allocationItems = {
      for (final item in allocations) item.allocation.id: item,
    };
    final today = calDayOf(now);
    final blocks = <DateTime, List<CalBlockItem>>{};
    final lanes = <DateTime, List<CalLane>>{};
    for (final day in days) {
      final key = calDayOf(day);
      final items = calDayBlocks(
        day: key,
        events: events,
        allocations: adapters,
      );
      blocks[key] = items;
      lanes[key] = calPackLanes(items);
    }
    final allDayEvents = <CalendaEventAdapter>[];
    for (final day in days) {
      for (final event in calAllDayEvents(day: day, events: events)) {
        if (!allDayEvents.contains(event)) allDayEvents.add(event);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dayMode ? _dayHead(context, days.first) : _weekHead(context),
        _deadlineLane(context, l),
        if (allDayEvents.isNotEmpty) _allDayBar(context, allDayEvents),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: (_a2EndHour - _a2StartHour) * _a2HourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _a2Gutter,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (
                          var hour = 0;
                          hour < _a2EndHour - _a2StartHour;
                          hour++
                        )
                          Positioned(
                            top: hour == 0 ? 0 : hour * _a2HourHeight - 6,
                            left: 0,
                            right: 8,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Text(
                                '${(_a2StartHour + hour).toString().padLeft(2, '0')}:00',
                                style: _a2Text(
                                  10.5,
                                  FontWeight.w400,
                                  ds.ink3,
                                  height: 1,
                                  tabular: true,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var index = 0; index < days.length; index++)
                    Expanded(
                      child: _column(
                        context,
                        days[index],
                        blocks[calDayOf(days[index])] ?? const [],
                        lanes[calDayOf(days[index])] ?? const [],
                        allocationItems,
                        isToday: calSameDay(days[index], today),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _weekHead(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _a2Gutter),
          for (final day in days)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSelectDay == null ? null : () => onSelectDay!(day),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: calSameDay(day, calDayOf(now))
                          ? ds.primaryTint
                          : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          calWeekdayShort(locale, day),
                          style: _a2Text(11, FontWeight.w400, ds.ink3),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${day.day}',
                          style: _a2Text(
                            15,
                            calSameDay(day, calDayOf(now)) ||
                                    calSameDay(day, selected)
                                ? FontWeight.w600
                                : FontWeight.w500,
                            calSameDay(day, calDayOf(now)) ||
                                    calSameDay(day, selected)
                                ? ds.primary
                                : ds.ink,
                            height: 1,
                            tabular: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayHead(BuildContext context, DateTime day) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final label =
        '${DateFormat.E(locale).format(day)} · ${DateFormat.MMMd(locale).format(day)}';
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _a2Gutter),
          Expanded(
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _a2Text(13, FontWeight.w600, ds.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deadlineLane(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    final label = SizedBox(
      width: _a2Gutter,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Align(
          alignment: Alignment.topRight,
          child: Text(
            l.deadline,
            maxLines: 1,
            softWrap: false,
            style: _a2Text(10.5, FontWeight.w400, ds.ink3, height: 16 / 10.5),
          ),
        ),
      ),
    );
    final Widget body;
    if (dayMode) {
      final day = days.first;
      final items = [
        for (final deadline in deadlines)
          if (calSameDay(deadline.due, day)) deadline,
      ];
      body = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              _deadlineText(
                context,
                '${DateFormatters.formatTime(item.due)} ${item.title}',
                item,
              ),
          ],
        ),
      );
    } else {
      body = Expanded(
        child: Row(
          children: [
            for (final day in days)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item
                        in deadlines
                            .where((value) => calSameDay(value.due, day))
                            .take(2))
                      _deadlineText(
                        context,
                        DateFormatters.formatTime(item.due),
                        item,
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, body],
      ),
    );
  }

  Widget _deadlineText(
    BuildContext context,
    String text,
    CalendarDeadline deadline,
  ) {
    final ds = context.ds;
    final content = Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: _a2Text(10.5, FontWeight.w400, ds.warn, height: 16 / 10.5),
    );
    if (onDeadline == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onDeadline!(deadline),
        child: content,
      ),
    );
  }

  Widget _allDayBar(BuildContext context, List<CalendaEventAdapter> values) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _a2Gutter,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l.allDayLabel,
                  maxLines: 1,
                  softWrap: false,
                  style: _a2Text(10.5, FontWeight.w400, ds.ink3),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final event in values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _A2AllDayChip(
                        event: event,
                        onTap: onEvent == null ? null : () => onEvent!(event),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(
    BuildContext context,
    DateTime day,
    List<CalBlockItem> items,
    List<CalLane> itemLanes,
    Map<int, TaskAllocationCalendarItem> allocationItems, {
    required bool isToday,
  }) {
    final ds = context.ds;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final windowStart = DateTime(
          day.year,
          day.month,
          day.day,
          _a2StartHour,
        );
        final windowEnd = DateTime(day.year, day.month, day.day, _a2EndHour);
        final showNow =
            isToday && !now.isBefore(windowStart) && now.isBefore(windowEnd);
        final widgets = <Widget>[
          Positioned.fill(
            child: onSlot == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) =>
                        onSlot!(_slotRange(day, details.localPosition.dy)),
                  ),
          ),
          for (var hour = 0; hour < _a2EndHour - _a2StartHour; hour++)
            Positioned(
              top: hour * _a2HourHeight,
              left: 0,
              right: 0,
              child: Container(height: 1, color: ds.line),
            ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 1,
            child: ColoredBox(color: ds.lineSoft.withValues(alpha: 0.6)),
          ),
        ];
        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          final start = item.start.isBefore(windowStart)
              ? windowStart
              : item.start;
          final end = item.end.isAfter(windowEnd) ? windowEnd : item.end;
          if (!end.isAfter(start)) continue;
          final lanes = itemLanes[index];
          final laneWidth = width / lanes.lanes;
          final top =
              start.difference(windowStart).inMinutes / 60 * _a2HourHeight;
          final height = math.max(
            18.0,
            end.difference(start).inMinutes / 60 * _a2HourHeight,
          );
          final accent = ds.eventAccent(item.event?.color ?? ds.primary);
          final meta = dayMode && height >= 29
              ? _blockMeta(item, calendarNames, allocationItems)
              : null;
          widgets.add(
            Positioned(
              top: top,
              left: lanes.lane * laneWidth + 2,
              width: math.max(8, laneWidth - 4),
              height: height,
              child: _A2TimeBlock(
                title: item.title,
                meta: meta,
                compact: width < 52,
                fill: item.isAllocation ? ds.workBg : ds.tint(accent),
                edge: item.isAllocation ? ds.work : accent,
                onTap: () => _openBlock(item, allocationItems),
                onReschedule:
                    item.canDrag &&
                        onReschedule != null &&
                        (item.isAllocation
                            ? onAllocation != null
                            : onEvent != null)
                    ? (minutes) => onReschedule!(item, minutes)
                    : null,
              ),
            ),
          );
        }
        if (showNow) {
          widgets.add(
            _A2NowLine(
              top: now.difference(windowStart).inMinutes / 60 * _a2HourHeight,
              color: ds.primary,
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: widgets);
      },
    );
  }

  void _openBlock(
    CalBlockItem item,
    Map<int, TaskAllocationCalendarItem> allocationItems,
  ) {
    final event = item.event;
    if (event != null) {
      onEvent?.call(event);
      return;
    }
    final allocation = item.allocation;
    if (allocation == null) return;
    final original = allocationItems[allocation.id];
    if (original != null) onAllocation?.call(original);
  }
}

class _A2AllDayChip extends StatelessWidget {
  const _A2AllDayChip({required this.event, this.onTap});

  final CalendaEventAdapter event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final accent = ds.eventAccent(event.color ?? ds.primary);
    final chip = Container(
      height: 18,
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      decoration: BoxDecoration(
        color: ds.tint(accent),
        borderRadius: BorderRadius.circular(2),
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _a2Text(11, FontWeight.w400, ds.ink, height: 1),
        ),
      ),
    );
    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

class _A2TimeBlock extends StatefulWidget {
  const _A2TimeBlock({
    required this.title,
    required this.meta,
    required this.fill,
    required this.edge,
    required this.onTap,
    this.onReschedule,
    this.compact = false,
  });

  final String title;
  final String? meta;

  /// Two blocks side by side halve a 43px phone column. At that width every
  /// pixel the inset takes is one the title cannot use, so a narrow block
  /// trades its padding away. (Even then a 13px content box holds at most one
  /// Latin glyph; the design has no rule for a half-width lane.)
  final bool compact;
  final Color fill;
  final Color edge;
  final VoidCallback onTap;
  final ValueChanged<int>? onReschedule;

  @override
  State<_A2TimeBlock> createState() => _A2TimeBlockState();
}

class _A2TimeBlockState extends State<_A2TimeBlock> {
  double _dragDy = 0;

  void _finishDrag() {
    final minutes = (_dragDy / _a2HourHeight * 60).round();
    setState(() => _dragDy = 0);
    final snapped = (minutes / 30).round() * 30;
    if (snapped != 0) widget.onReschedule?.call(snapped);
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final canDrag = widget.onReschedule != null;
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ds.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 3, child: ColoredBox(color: widget.edge)),
          Expanded(
            child: Padding(
              padding: widget.compact
                  ? const EdgeInsets.fromLTRB(2, 2, 0, 2)
                  : const EdgeInsets.fromLTRB(4, 2, 2, 2),
              child: LayoutBuilder(
                builder: (context, constraints) => ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    maxWidth: constraints.maxWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _a2Text(
                            10.5,
                            FontWeight.w600,
                            ds.ink,
                            height: 1.25,
                          ),
                        ),
                        if (widget.meta != null)
                          Text(
                            widget.meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _a2Text(
                              9.5,
                              FontWeight.w400,
                              ds.ink3,
                              height: 1.25,
                              tabular: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Transform.translate(
      offset: Offset(0, _dragDy),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPressStart: canDrag ? (_) => setState(() => _dragDy = 0) : null,
          onLongPressMoveUpdate: canDrag
              ? (details) =>
                    setState(() => _dragDy = details.offsetFromOrigin.dy)
              : null,
          onLongPressEnd: canDrag ? (_) => _finishDrag() : null,
          child: card,
        ),
      ),
    );
  }
}

class _A2NowLine extends StatelessWidget {
  const _A2NowLine({required this.top, required this.color});

  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: -3,
      right: 0,
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned(
              left: 3,
              right: 0,
              top: 2,
              child: Container(height: 2, color: color),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DateTimeRange _slotRange(DateTime day, double dy) {
  final raw = (dy / _a2HourHeight * 60).floor() + _a2StartHour * 60;
  final snapped = (raw ~/ 30) * 30;
  final startMinutes = snapped.clamp(_a2StartHour * 60, _a2EndHour * 60 - 60);
  final start = DateTime(
    day.year,
    day.month,
    day.day,
    startMinutes ~/ 60,
    startMinutes % 60,
  );
  return DateTimeRange(start: start, end: start.add(const Duration(hours: 1)));
}

DateTimeRange _nextHourSlot(DateTime day, DateTime now) {
  final DateTime start;
  if (calSameDay(day, now)) {
    final hour = (now.hour + 1).clamp(0, 23);
    start = DateTime(day.year, day.month, day.day, hour);
  } else {
    start = DateTime(day.year, day.month, day.day, 9);
  }
  return DateTimeRange(start: start, end: start.add(const Duration(hours: 1)));
}
