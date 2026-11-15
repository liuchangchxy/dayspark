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
const int _a2StartHour = 0;
const int _a2EndHour = 24;
const int _a2DefaultScrollHour = 8;
const int _a2DawnEndHour = 6;
const double _a2DawnFoldHeight = 28;

/// Maps a clock minute onto the 24-hour axis. The 00:00–06:00 band collapses
/// to one row when it holds nothing, so the axis is not always
/// `minutes / 60 * _a2HourHeight`; every position and hit test goes through
/// this class instead of multiplying by the hour height.
class _A2Axis {
  const _A2Axis({required this.foldDawn});

  final bool foldDawn;

  double get height => foldDawn
      ? _a2DawnFoldHeight + (24 - _a2DawnEndHour) * _a2HourHeight
      : 24 * _a2HourHeight;

  double offsetOf(int minutes) {
    if (!foldDawn) return minutes / 60 * _a2HourHeight;
    final dawnEnd = _a2DawnEndHour * 60;
    if (minutes <= dawnEnd) {
      return minutes / dawnEnd * _a2DawnFoldHeight;
    }
    return _a2DawnFoldHeight + (minutes - dawnEnd) / 60 * _a2HourHeight;
  }

  /// The inverse of [offsetOf], floored to the half hour. Inside the folded
  /// band there is no visible slot, so it resolves to the first drawn hour
  /// rather than a time the axis never shows.
  DateTimeRange rangeAt(DateTime day, double dy) {
    final dawnEnd = _a2DawnEndHour * 60;
    final int raw;
    if (!foldDawn) {
      raw = (dy / _a2HourHeight * 60).floor();
    } else if (dy <= _a2DawnFoldHeight) {
      raw = dawnEnd;
    } else {
      raw = dawnEnd + ((dy - _a2DawnFoldHeight) / _a2HourHeight * 60).floor();
    }
    final snapped = (raw ~/ 30) * 30;
    final startMinutes = snapped.clamp(
      foldDawn ? dawnEnd : _a2StartHour * 60,
      _a2EndHour * 60 - 60,
    );
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    return DateTimeRange(
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
  }
}

/// One overflow token for every folded list in the calendar. The month cell
/// and the week lanes used to say "More (1)" and "+1" for the same idea, which
/// reads like two different counts; the design's month cell is `+N`.
String _a2OverflowLabel(int hidden) => '+$hidden';

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
    final l = AppLocalizations.of(context)!;
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
            tooltip: l.previousPeriod,
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
            tooltip: l.nextPeriod,
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
          child: LayoutBuilder(
            // A row is as tall as the window allows. Drawing three chips in a
            // short cell overflowed the grid; the cell now shows only what fits
            // and folds the rest into +N, the same contract as a long day.
            builder: (context, constraints) {
              // When something folds, one of the available rows belongs to the
              // +N line itself, so the chips must not consume all of them.
              final capacity = ((constraints.maxHeight - 16) / 20)
                  .floor()
                  .clamp(0, visible.length);
              final overflows = capacity < visible.length;
              final fits = overflows
                  ? (capacity - 1).clamp(0, visible.length)
                  : capacity;
              final shown = visible.take(fits).toList();
              final folded = hidden + (visible.length - shown.length);
              return Column(
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
                  for (final entry in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _A2MonthChip(
                        entry: entry,
                        onEvent: onEvent,
                        onAllocation: onAllocation,
                        onDeadline: onDeadline,
                      ),
                    ),
                  if (folded > 0)
                    Text(
                      _a2OverflowLabel(folded),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _a2Text(11, FontWeight.w400, ds.ink3),
                    ),
                ],
              );
            },
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
    final l = AppLocalizations.of(context)!;
    final trailing = entry.label(l);
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
              trailing,
              maxLines: 1,
              style: _a2Text(
                11,
                FontWeight.w400,
                textColor,
                height: 1.35,
              ).copyWith(fontFeatures: AppTypography.tabular),
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
  /// A date-only deadline has no slot, so it prints the deadline word alone
  /// instead of inventing `00:00`.
  String label(AppLocalizations l) {
    if (deadline != null && !calDeadlineHasTime(deadline!.due)) {
      return l.deadline;
    }
    final value =
        event?.start ??
        allocation?.allocation.startAt.toLocal() ??
        deadline!.due;
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
    final allDayByDay = <DateTime, List<CalendaEventAdapter>>{};
    final allDayEvents = <CalendaEventAdapter>[];
    for (final day in days) {
      final key = calDayOf(day);
      final items = calAllDayEvents(day: day, events: events);
      allDayByDay[key] = items;
      for (final event in items) {
        if (!allDayEvents.contains(event)) allDayEvents.add(event);
      }
    }
    // The now-line is content too: folding the band while the reader's own
    // clock sits inside it would hide the one marker the axis exists for.
    final dawnHoldsNow = calSameDay(now, today) && now.hour < _a2DawnEndHour;
    final axis = _A2Axis(
      foldDawn: !dawnHoldsNow && !_dawnHasItems(blocks, days),
    );
    // The dawn band has no hour rows when it folds, so an opening offset that
    // points inside it would land on a time the axis never draws.
    final initialHour = math.max(
      axis.foldDawn ? _a2DawnEndHour : 0,
      _initialScrollHour(days, events, allocations),
    );
    final showNow = days.any((day) => calSameDay(day, today));
    final nowOffset = showNow
        ? axis.offsetOf(now.hour * 60 + now.minute)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dayMode ? _dayHead(context, days.first) : _weekHead(context),
        _deadlineLane(context, l),
        // All-day items have no position on a clock, so they get their own
        // lane above the grid and never a 24-hour block. With nothing to show
        // the lane is absent, so it costs no height at all.
        if (allDayEvents.isNotEmpty) _allDayLane(context, allDayByDay),
        Expanded(
          child: _A2TimeScroll(
            daysKey: [for (final day in days) calDayOf(day)].join(','),
            initialHour: initialHour,
            axis: axis,
            nowOffset: nowOffset,
            nowLabel: DateFormatters.formatTime(now),
            child: SizedBox(
              height: axis.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: _a2Gutter,
                          child: _hourGutter(context, axis),
                        ),
                        for (var index = 0; index < days.length; index++)
                          Expanded(
                            child: _column(
                              context,
                              days[index],
                              blocks[calDayOf(days[index])] ?? const [],
                              lanes[calDayOf(days[index])] ?? const [],
                              allocationItems,
                              axis: axis,
                              isToday: calSameDay(days[index], today),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (axis.foldDawn)
                    Positioned(
                      top: 0,
                      left: _a2Gutter,
                      right: 0,
                      height: _a2DawnFoldHeight,
                      child: IgnorePointer(child: _dawnFoldRow(context)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The 00:00–06:00 band folds only when no visible day has anything in it.
  /// A single item anywhere in the band keeps the real hours drawn.
  bool _dawnHasItems(
    Map<DateTime, List<CalBlockItem>> blocks,
    List<DateTime> days,
  ) {
    for (final day in days) {
      final windowStart = DateTime(day.year, day.month, day.day);
      final windowDawnEnd = DateTime(
        day.year,
        day.month,
        day.day,
        _a2DawnEndHour,
      );
      for (final item in blocks[calDayOf(day)] ?? const <CalBlockItem>[]) {
        if (item.start.isBefore(windowDawnEnd) &&
            item.end.isAfter(windowStart)) {
          return true;
        }
      }
      for (final deadline in deadlines) {
        if (!calDeadlineHasTime(deadline.due)) continue;
        if (!calSameDay(deadline.due, day)) continue;
        if (deadline.due.isBefore(windowDawnEnd) &&
            !deadline.due.isBefore(windowStart)) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _hourGutter(BuildContext context, _A2Axis axis) {
    final ds = context.ds;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (
          var hour = axis.foldDawn ? _a2DawnEndHour : _a2StartHour;
          hour < _a2EndHour;
          hour++
        )
          Positioned(
            top: axis.offsetOf(hour * 60) - (hour == 0 ? 0 : 6),
            left: 0,
            right: 8,
            child: Align(
              alignment: Alignment.topRight,
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
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
    );
  }

  /// The folded 00:00–06:00 band. It carries no slots: the axis reports its
  /// single row as the first drawn hour, so a tap there still lands on a time
  /// the user can see. Low contrast because nothing happens in it.
  Widget _dawnFoldRow(BuildContext context) {
    final ds = context.ds;
    String clock(int hour) => '${hour.toString().padLeft(2, '0')}:00';
    return Container(
      decoration: BoxDecoration(
        color: ds.surface2,
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Center(
        child: Text(
          AppLocalizations.of(context)!.dawnQuiet(
            clock(_a2StartHour),
            clock(_a2DawnEndHour),
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: _a2Text(
            10.5,
            FontWeight.w400,
            ds.ink3,
            height: 1,
            tabular: true,
          ),
        ),
      ),
    );
  }

  /// Scrolls to 08:00 by default, but an item earlier than that pulls the
  /// viewport one hour above itself so the day never opens on an empty band.
  int _initialScrollHour(
    List<DateTime> days,
    List<CalendaEventAdapter> events,
    List<TaskAllocationCalendarItem> allocations,
  ) {
    int? earliest;
    bool visible(DateTime value) => days.any((day) => calSameDay(day, value));
    for (final event in events) {
      if (event.isAllDay) continue;
      if (!calSameDay(event.start, event.end)) continue;
      if (!visible(event.start)) continue;
      earliest = earliest == null
          ? event.start.hour
          : math.min(earliest, event.start.hour);
    }
    for (final item in allocations) {
      final start = item.allocation.startAt.toLocal();
      if (!visible(start)) continue;
      earliest = earliest == null ? start.hour : math.min(earliest, start.hour);
    }
    if (earliest == null) return _a2DefaultScrollHour;
    return math.min(_a2DefaultScrollHour, math.max(0, earliest - 1));
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
    final locale = Localizations.localeOf(context).toString();
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
                calDeadlineHasTime(item.due)
                    ? '${DateFormatters.formatTime(item.due)} ${item.title}'
                    : '${l.deadlinePrefix(DateFormat.MMMd(locale).format(item.due))}'
                          ' ${item.title}',
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
              Expanded(child: _weekDeadlineCell(context, l, day)),
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

  Widget _weekDeadlineCell(
    BuildContext context,
    AppLocalizations l,
    DateTime day,
  ) {
    final ds = context.ds;
    final items = [
      for (final value in deadlines)
        if (calSameDay(value.due, day)) value,
    ];
    const maxVisible = 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items.take(maxVisible))
          _deadlineText(
            context,
            calDeadlineHasTime(item.due)
                ? DateFormatters.formatTime(item.due)
                : l.deadline,
            item,
          ),
        if (items.length > maxVisible)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              _a2OverflowLabel(items.length - maxVisible),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _a2Text(10.5, FontWeight.w400, ds.ink3, height: 16 / 10.5),
            ),
          ),
      ],
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

  /// All-day events share the column grid with the hour rows, so a chip sits
  /// under the day it belongs to. Day view is the same lane with one column.
  Widget _allDayLane(
    BuildContext context,
    Map<DateTime, List<CalendaEventAdapter>> byDay,
  ) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final label = SizedBox(
      width: _a2Gutter,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Align(
          alignment: Alignment.topRight,
          child: Text(
            l.allDayLabel,
            maxLines: 1,
            softWrap: false,
            style: _a2Text(10.5, FontWeight.w400, ds.ink3, height: 16 / 10.5),
          ),
        ),
      ),
    );
    const maxVisible = 2;
    final Widget body;
    if (dayMode) {
      final items = byDay[calDayOf(days.first)] ?? const [];
      body = Expanded(
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          children: [
            for (final event in items)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: _A2AllDayChip(
                  event: event,
                  onTap: onEvent == null ? null : () => onEvent!(event),
                ),
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
                child: Builder(
                  builder: (context) {
                    final items = byDay[calDayOf(day)] ?? const [];
                    final shown = items.take(maxVisible).toList();
                    final folded = items.length - shown.length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final event in shown)
                          Padding(
                            padding: const EdgeInsets.only(right: 2, bottom: 2),
                            child: _A2AllDayChip(
                              event: event,
                              onTap: onEvent == null
                                  ? null
                                  : () => onEvent!(event),
                            ),
                          ),
                        if (folded > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Text(
                              _a2OverflowLabel(folded),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: _a2Text(
                                10.5,
                                FontWeight.w400,
                                ds.ink3,
                                height: 16 / 10.5,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
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

  Widget _column(
    BuildContext context,
    DateTime day,
    List<CalBlockItem> items,
    List<CalLane> itemLanes,
    Map<int, TaskAllocationCalendarItem> allocationItems, {
    required _A2Axis axis,
    required bool isToday,
  }) {
    final ds = context.ds;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final windowStart = DateTime(day.year, day.month, day.day);
        final windowEnd = DateTime(
          day.year,
          day.month,
          day.day,
        ).add(const Duration(days: 1));
        final showNow =
            isToday && !now.isBefore(windowStart) && now.isBefore(windowEnd);
        final widgets = <Widget>[
          Positioned.fill(
            child: onSlot == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) =>
                        onSlot!(axis.rangeAt(day, details.localPosition.dy)),
                  ),
          ),
          for (var hour = 0; hour < _a2EndHour - _a2StartHour; hour++)
            if (!axis.foldDawn || hour >= _a2DawnEndHour)
              Positioned(
                top: axis.offsetOf(hour * 60),
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
          final top = axis.offsetOf(start.difference(windowStart).inMinutes);
          final height = math.max(
            18.0,
            axis.offsetOf(end.difference(windowStart).inMinutes) - top,
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
              top: axis.offsetOf(now.difference(windowStart).inMinutes),
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

/// The full-day grid is 24 hours tall; opening at midnight would show every
/// calendar as empty. The viewport starts at 08:00 (or above the first item)
/// and jumps there again when the visible days change, not on every rebuild.
///
/// The now-line and the deadline lane are both pinned anchors, but for
/// different reasons: the deadline lane sits above the scroller (it never
/// scrolls), while the now-line lives inside the axis and has to stay readable
/// after it scrolls past the top edge. So the scroller paints a sticky clock
/// strip whenever the line's own offset is above the viewport, and offers a
/// "back to now" key once the reader is more than one screen away.
class _A2TimeScroll extends StatefulWidget {
  const _A2TimeScroll({
    required this.daysKey,
    required this.initialHour,
    required this.axis,
    required this.nowOffset,
    required this.nowLabel,
    required this.child,
  });

  final String daysKey;
  final int initialHour;
  final _A2Axis axis;
  final double? nowOffset;
  final String nowLabel;
  final Widget child;

  @override
  State<_A2TimeScroll> createState() => _A2TimeScrollState();
}

class _A2TimeScrollState extends State<_A2TimeScroll> {
  late final ScrollController _controller;

  double _offset(int hour) => widget.axis.offsetOf(hour * 60);

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: _offset(widget.initialHour),
    )..addListener(_onScroll);
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _A2TimeScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    final daysChanged = widget.daysKey != oldWidget.daysKey;
    // Folding or unfolding the dawn band rewrites every offset above it, so
    // the old pixel offset no longer names the same time.
    final axisChanged = widget.axis.foldDawn != oldWidget.axis.foldDawn;
    if (!daysChanged && !axisChanged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(
        _offset(
          widget.initialHour,
        ).clamp(0.0, _controller.position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  double get _scrollOffset => _controller.hasClients
      ? _controller.offset
      : _controller.initialScrollOffset;

  void _backToNow() {
    final target = widget.nowOffset;
    if (target == null || !_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    _controller.animateTo(
      (target - viewport * 0.25).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final nowOffset = widget.nowOffset;
    final scrollOffset = _scrollOffset;
    // The line is drawn on the axis; once the reader scrolls past it, the
    // clock reading has to follow or the axis loses its "where am I" anchor.
    final nowAboveViewport = nowOffset != null && nowOffset < scrollOffset;
    final nowOutOfReach =
        nowOffset != null &&
        _controller.hasClients &&
        (nowOffset - scrollOffset).abs() >
            _controller.position.viewportDimension;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            controller: _controller,
            child: widget.child,
          ),
        ),
        if (nowAboveViewport)
          Positioned(
            key: const ValueKey('calendar-sticky-now'),
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: ds.primaryTint,
                  border: Border(
                    bottom: BorderSide(color: ds.primary, width: 2),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _a2Gutter,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            widget.nowLabel,
                            maxLines: 1,
                            softWrap: false,
                            style: _a2Text(
                              10.5,
                              FontWeight.w600,
                              ds.primary,
                              height: 1,
                              tabular: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (nowOutOfReach)
          Positioned(
            right: 0,
            bottom: 0,
            child: Tooltip(
              message: l.backToNow,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Semantics(
                  button: true,
                  label: l.backToNow,
                  child: GestureDetector(
                    key: const ValueKey('calendar-back-to-now'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _backToNow,
                    // The key reads as 24px; the hit area is the full 48px
                    // target, so a thumb can find it without a bigger dot.
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: ds.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: ds.line),
                          ),
                          child: Center(
                            child: Icon(
                              CupertinoIcons.arrow_up,
                              size: 12,
                              color: ds.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
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
