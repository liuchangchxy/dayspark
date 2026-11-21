import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';

const double _a2Gutter = 56.0;
const double _a2HourHeight = 54.0;
const double _a2AxisHeight = 648.0;
const int _a2EndHour = 20;
const int _a2StartMinute = 480;
const int _a2SpanMinutes = 720;

/// Authoritative time scale based on docs/design/frozen/dayspark-spec.html:
/// pct(m) = Math.max(0, Math.min(100, (m - 480) / 720 * 100))
/// Visible range: 08:00–20:00, 648px height, 54px/hour.
class _A2Axis {
  const _A2Axis();

  double get height => _a2AxisHeight;

  double offsetOf(int minutes) {
    final clamped = minutes.clamp(_a2StartMinute, _a2EndHour * 60);
    return (clamped - _a2StartMinute) / _a2SpanMinutes * _a2AxisHeight;
  }

  double pctOf(int minutes) {
    final clamped = minutes.clamp(_a2StartMinute, _a2EndHour * 60);
    return (clamped - _a2StartMinute) / _a2SpanMinutes * 100.0;
  }

  /// Inverse mapping floored to 30 minutes in range 08:00–19:00.
  DateTimeRange rangeAt(DateTime day, double dy) {
    final fraction = (dy / _a2AxisHeight).clamp(0.0, 1.0);
    final raw = _a2StartMinute + (fraction * _a2SpanMinutes).floor();
    final snapped = (raw ~/ 30) * 30;
    final startMinutes = snapped.clamp(_a2StartMinute, _a2EndHour * 60 - 60);
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
    final original = allocationItems[allocation.id];
    name = original == null ? '' : _calendarName(names, original.todo.calendarId);
  } else {
    name = '';
  }
  if (name.isEmpty) return time;
  return '$time · $name';
}

DateTimeRange _nextHourSlot(DateTime day, DateTime now) {
  final sameDay = calSameDay(day, now);
  final hour = sameDay ? (now.hour + 1).clamp(8, 19) : 9;
  final start = DateTime(day.year, day.month, day.day, hour);
  return DateTimeRange(start: start, end: start.add(const Duration(hours: 1)));
}

class A2MonthStrip extends StatelessWidget {
  const A2MonthStrip({
    super.key,
    required this.label,
    this.onPrevious,
    this.onNext,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

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
          if (onPrevious != null)
            _A2NavButton(
              icon: CupertinoIcons.chevron_left,
              tooltip: l.previousPeriod,
              onPressed: onPrevious!,
            ),
          Expanded(
            child: Text(
              label,
              textAlign: onPrevious != null ? TextAlign.center : TextAlign.left,
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
          if (onNext != null)
            _A2NavButton(
              icon: CupertinoIcons.chevron_right,
              tooltip: l.nextPeriod,
              onPressed: onNext!,
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
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
  });

  final DateTime anchor;
  final DateTime selected;
  final DateTime today;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(anchor.year, anchor.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final rows = <Widget>[];
    for (var row = 0; row < 6; row++) {
      rows.add(
        SizedBox(
          height: 48,
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
    final selectedEntries = _entriesFor(selected, events, allocations, deadlines);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ds.surface,
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 28,
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
                            style: _a2Text(10.5, FontWeight.w400, ds.ink3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(children: rows),
            ],
          ),
        ),
        // Selected day group header & stacked items list (mobile list stacking)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${DateFormat.MMMd(locale).format(selected)} · ${calWeekdayLong(locale, selected)}',
                style: _a2Text(11.5, FontWeight.w600, ds.ink),
              ),
              Text(
                l.dayItemCount(selectedEntries.length),
                style: _a2Text(10.5, FontWeight.w400, ds.ink3),
              ),
            ],
          ),
        ),
        for (final entry in selectedEntries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: _A2MobileMonthRow(
              entry: entry,
              onEvent: onEvent,
              onAllocation: onAllocation,
              onDeadline: onDeadline,
            ),
          ),
        if (selectedEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              l.noSchedule,
              style: _a2Text(11, FontWeight.w400, ds.ink3),
            ),
          ),
      ],
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
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: ds.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${date.day}',
                    style: _a2Text(
                      10.5,
                      FontWeight.w600,
                      Colors.white,
                      height: 1,
                      tabular: true,
                    ),
                  ),
                )
              else
                Text(
                  '${date.day}',
                  style: _a2Text(
                    11.5,
                    numberWeight,
                    numberColor,
                    height: 1,
                    tabular: true,
                  ),
                ),
              if (dots > 0) ...[
                const SizedBox(height: 3),
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

class _A2MobileMonthRow extends StatelessWidget {
  const _A2MobileMonthRow({
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
    final event = entry.event;
    final allocation = entry.allocation;
    final deadline = entry.deadline;
    final timeStr = entry.label(l);
    final Color barColor;
    final Color bgColor;
    if (event != null) {
      final accent = ds.eventAccent(event.color ?? ds.primary);
      barColor = accent;
      bgColor = ds.tint(accent);
    } else if (allocation != null) {
      barColor = ds.work;
      bgColor = const Color(0xFFF1F0EA);
    } else {
      barColor = ds.warn;
      bgColor = ds.surface2;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (event != null) onEvent?.call(event);
          if (allocation != null) onAllocation?.call(allocation);
          if (deadline != null) onDeadline?.call(deadline);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: barColor, width: 3)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  timeStr,
                  style: _a2Text(10, FontWeight.w500, ds.ink3, tabular: true),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _a2Text(11, FontWeight.w500, ds.ink),
                ),
              ),
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
        // Spec .month-week: height 30px, 9.5px faint font, border 1px solid var(--hair)
        Container(
          height: 30,
          decoration: const BoxDecoration(
            color: Color(0xFFFBFBF8),
            border: Border(
              left: BorderSide(color: SpecTokens.hair, width: 1),
              top: BorderSide(color: SpecTokens.hair, width: 1),
              right: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      calWeekdayLong(
                        locale,
                        gridStart.add(Duration(days: i)),
                      ),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w400,
                        color: SpecTokens.faint,
                        letterSpacing: 0.04,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Spec .month-grid: 7 cols, min-height 104px per row, border-left & top 1px solid var(--hair)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minTotal = 104.0 * 6;
              final height = math.max(minTotal, constraints.maxHeight);
              return SingleChildScrollView(
                child: Container(
                  height: height,
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: SpecTokens.hair, width: 1),
                      top: BorderSide(color: SpecTokens.hair, width: 1),
                    ),
                  ),
                  child: Column(children: rows),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _A2DesktopMonthCell extends StatefulWidget {
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
  State<_A2DesktopMonthCell> createState() => _A2DesktopMonthCellState();
}

class _A2DesktopMonthCellState extends State<_A2DesktopMonthCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Spec .mcell: border-right & border-bottom 1px solid var(--hair); padding: 6px 7px; background: #fff
    // .mcell:hover: #fbfbf8; .mcell.is-out: #fbfbf8
    final background = !widget.inMonth
        ? const Color(0xFFFBFBF8)
        : (_hovered ? const Color(0xFFFBFBF8) : SpecTokens.paper);
    final visible = widget.entries.take(3).toList();
    final hidden = widget.entries.length - visible.length;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelectDay(widget.date),
        onDoubleTap: widget.onSlot == null
            ? null
            : () => widget.onSlot!(_nextHourSlot(widget.date, widget.now)),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: background,
            border: const Border(
              right: BorderSide(color: SpecTokens.hair, width: 1),
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final capacity = ((constraints.maxHeight - 20) / 22)
                  .floor()
                  .clamp(0, visible.length);
              final overflows = capacity < visible.length;
              final fits = overflows
                  ? (capacity - 1).clamp(0, visible.length)
                  : capacity;
              final shown = visible.take(fits).toList();
              final folded = hidden + (visible.length - shown.length);

              // Spec .mnum: min-width 20px, height 20px, 10.5px ink-2 tabular.
              // .mnum.is-today: background: var(--red); color: #fff; border-radius: 10px;
              // .mcell.is-out .mnum: color: #c3c3ba;
              final dateLabel = widget.isToday
                  ? Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: SpecTokens.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        widget.date.day.toString(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1,
                          fontFeatures: AppTypography.tabular,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 20,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.date.day.toString(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: widget.inMonth
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: widget.inMonth
                                ? SpecTokens.ink2
                                : const Color(0xFFC3C3BA),
                            height: 1,
                            fontFeatures: AppTypography.tabular,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
                      ),
                    );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dateLabel,
                  const SizedBox(height: 3),
                  for (final entry in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _A2MonthChip(
                        entry: entry,
                        onEvent: widget.onEvent,
                        onAllocation: widget.onAllocation,
                        onDeadline: widget.onDeadline,
                      ),
                    ),
                  if (folded > 0)
                    Text(
                      _a2OverflowLabel(folded),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w400,
                        color: SpecTokens.faint,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
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
    final Color barColor;
    final Color textColor;
    if (event != null) {
      final accent = ds.eventAccent(event.color ?? ds.primary);
      background = ds.tint(accent);
      barColor = accent;
      textColor = SpecTokens.ink2;
    } else if (allocation != null) {
      background = const Color(0xFFF1F0EA);
      barColor = SpecTokens.work;
      textColor = SpecTokens.ink2;
    } else {
      final isOverdue = deadline != null && deadline.due.isBefore(DateTime.now());
      background = isOverdue ? SpecTokens.redSoft : SpecTokens.amberSoft;
      barColor = isOverdue ? SpecTokens.red : SpecTokens.amber;
      textColor = isOverdue ? SpecTokens.red : SpecTokens.amber;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (event != null) onEvent?.call(event);
          if (allocation != null) onAllocation?.call(allocation);
          if (deadline != null) onDeadline?.call(deadline);
        },
        child: Container(
          width: double.infinity,
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 9,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                    height: 1.2,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  trailing,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w400,
                    color: SpecTokens.faint,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ],
          ),
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

/// The authoritative Week / Day Time Grid View.
/// 08:00–20:00, 648px height, 54px/hour.
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
    this.isDesktop = true,
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
  final bool isDesktop;
  final ValueChanged<DateTime>? onSelectDay;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;
  final ValueChanged<DateTimeRange>? onSlot;
  final void Function(CalBlockItem item, int minutes)? onReschedule;

  static const _axis = _A2Axis();
  static const _hourLabels = [8, 10, 12, 14, 16, 18, 20];

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dayMode ? _dayHeadbar(context, days.first) : _weekHead(context),
        _allDayLane(context, allDayByDay, allDayEvents),
        _deadlineLane(context, l),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              // The 08:00 reading is centred on the axis origin, so half of it
              // falls above the scroll viewport; the phone inset keeps it whole
              // without changing any hour-to-hour distance.
              padding: EdgeInsets.only(top: isDesktop ? 0 : 6),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: SpecTokens.hair, width: 1),
                    bottom: BorderSide(color: SpecTokens.hair, width: 1),
                  ),
                ),
                height: _axis.height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _a2Gutter,
                      child: _hourGutter(context),
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
        ),
      ],
    );
  }

  Widget _dayHeadbar(BuildContext context, DateTime day) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final key = calDayOf(day);
    final count = calDayBlocks(
      day: key,
      events: events,
      allocations: _adapt(allocations),
    ).length;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBF8),
        border: Border(
          left: BorderSide(color: SpecTokens.hair, width: 1),
          top: BorderSide(color: SpecTokens.hair, width: 1),
          right: BorderSide(color: SpecTokens.hair, width: 1),
          bottom: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: calWeekdayLong(locale, day),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SpecTokens.ink2,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                TextSpan(
                  text: ' · ${DateFormat.MMMd(locale).format(day)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                    color: SpecTokens.muted,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ),
          ),
          Text(
            l.timeArrangementsCount(count),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekHead(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final today = calDayOf(now);
    return Container(
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(
          left: BorderSide(color: SpecTokens.hair, width: 1),
          top: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _a2Gutter,
            height: 46,
            decoration: const BoxDecoration(
              color: SpecTokens.paper,
              border: Border(
                right: BorderSide(color: SpecTokens.hair, width: 1),
                bottom: BorderSide(color: SpecTokens.hair, width: 1),
              ),
            ),
          ),
          for (final day in days)
            Expanded(
              child: _DayHeadCell(
                day: day,
                isToday: calSameDay(day, today),
                locale: locale,
                onTap: onSelectDay == null ? null : () => onSelectDay!(day),
              ),
            ),
        ],
      ),
    );
  }

  Widget _allDayLane(
    BuildContext context,
    Map<DateTime, List<CalendaEventAdapter>> byDay,
    List<CalendaEventAdapter> allDayEvents,
  ) {
    if (!isDesktop && allDayEvents.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final label = Container(
      width: _a2Gutter,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(
          right: BorderSide(color: SpecTokens.hair, width: 1),
          bottom: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: Text(
        l.allDayLabel,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          fontSize: 9.0,
          color: SpecTokens.faint,
          letterSpacing: 0.04,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
    const maxVisible = 2;
    final Widget body;
    if (dayMode) {
      final items = byDay[calDayOf(days.first)] ?? const [];
      body = Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
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
        ),
      );
    } else {
      body = Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final items = byDay[calDayOf(day)] ?? const [];
                      final shown = items.take(maxVisible).toList();
                      final folded = items.length - shown.length;
                      return Container(
                        constraints: const BoxConstraints(minHeight: 30),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: SpecTokens.hair, width: 1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final event in shown)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _A2AllDayChip(
                                  event: event,
                                  onTap: onEvent == null ? null : () => onEvent!(event),
                                ),
                              ),
                            if (folded > 0)
                              Text(
                                _a2OverflowLabel(folded),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w400,
                                  color: SpecTokens.muted,
                                  fontFamilyFallback: AppTypography.fallback,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(
          left: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [label, body],
        ),
      ),
    );
  }

  Widget _deadlineLane(BuildContext context, AppLocalizations l) {
    final hasDeadlines = deadlines.any(
      (deadline) => days.any((day) => calSameDay(deadline.due, day)),
    );
    // Spec mobileCalendar never draws an empty 截止 row; the desktop keeps the
    // fixed 30px lane so the 7 columns stay aligned.
    if (!isDesktop && !hasDeadlines) return const SizedBox.shrink();
    final label = Container(
      width: _a2Gutter,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(
          right: BorderSide(color: SpecTokens.hair, width: 1),
          bottom: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: Text(
        l.deadline,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          fontSize: 9.0,
          color: SpecTokens.faint,
          letterSpacing: 0.04,
          fontFamilyFallback: AppTypography.fallback,
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
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _deadlineChip(context, item),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      body = Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 30),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: SpecTokens.hair, width: 1),
                      ),
                    ),
                    child: _weekDeadlineCell(context, l, day),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(
          left: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [label, body],
        ),
      ),
    );
  }

  Widget _weekDeadlineCell(
    BuildContext context,
    AppLocalizations l,
    DateTime day,
  ) {
    final items = [
      for (final value in deadlines)
        if (calSameDay(value.due, day)) value,
    ];
    const maxVisible = 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items.take(maxVisible))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _deadlineChip(context, item),
          ),
        if (items.length > maxVisible)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              _a2OverflowLabel(items.length - maxVisible),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w400,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
      ],
    );
  }

  Widget _deadlineChip(BuildContext context, CalendarDeadline deadline) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final isOverdue = deadline.due.isBefore(now);
    final text = dayMode
        ? (calDeadlineHasTime(deadline.due)
            ? '${DateFormatters.formatTime(deadline.due)} ${deadline.title}'
            : '${l.deadlinePrefix(DateFormat.MMMd(locale).format(deadline.due))} ${deadline.title}')
        : deadline.title;
    final chip = Container(
      width: double.infinity,
      padding: isOverdue
          ? const EdgeInsets.fromLTRB(3, 1, 4, 1)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: isOverdue
          ? const BoxDecoration(
              color: Colors.transparent,
              border: Border(
                left: BorderSide(color: Color(0xFFD9A39D), width: 2),
              ),
            )
          : BoxDecoration(
              color: SpecTokens.amberSoft,
              borderRadius: BorderRadius.circular(3),
            ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.0,
          height: 1.35,
          color: isOverdue ? SpecTokens.red : SpecTokens.amber,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
    if (onDeadline == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onDeadline!(deadline),
        child: chip,
      ),
    );
  }

  Widget _hourGutter(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(right: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final hour in _hourLabels)
            Positioned(
              top: _axis.offsetOf(hour * 60) - 6,
              left: 0,
              right: 8,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  style: const TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w400,
                    color: SpecTokens.faint,
                    height: 1,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
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
        final windowStart = DateTime(day.year, day.month, day.day);
        final showNow = isToday && now.hour >= 8 && now.hour <= 20;

        final widgets = <Widget>[
          // Slot tap background
          Positioned.fill(
            child: onSlot == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) =>
                        onSlot!(_axis.rangeAt(day, details.localPosition.dy)),
                  ),
          ),
          // Hairlines every 54px (from hour 9 to 20)
          for (var hour = 9; hour <= 20; hour++)
            Positioned(
              top: _axis.offsetOf(hour * 60),
              left: 0,
              right: 0,
              child: Container(height: 1, color: SpecTokens.hair),
            ),
          // Column right border
          const Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 1,
            child: ColoredBox(color: SpecTokens.hair),
          ),
        ];

        // Positioned blocks with side-by-side lanes
        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          final rawStartM = item.start.difference(windowStart).inMinutes;
          final rawEndM = item.end.difference(windowStart).inMinutes;
          if (rawEndM <= 0 || rawStartM >= 24 * 60) continue;
          final startM = rawStartM.clamp(_a2StartMinute, _a2EndHour * 60);
          final endM = rawEndM.clamp(_a2StartMinute, _a2EndHour * 60);

          final lanes = itemLanes[index];
          final laneWidth = width / lanes.lanes;
          final top = _axis.offsetOf(startM);
          final bottom = _axis.offsetOf(endM);
          final rawHeight = bottom - top;
          // Math.max(2.4% of 648 = 15.55px, rawHeight)
          final height = math.max(15.55, rawHeight);
          final spanFraction = (endM - startM) / _a2SpanMinutes;
          final isShort = spanFraction < 0.06;

          final accent = ds.eventAccent(item.event?.color ?? ds.primary);
          final isPlan = item.isAllocation;
          final allocationItem = item.allocation == null
              ? null
              : allocationItems[item.allocation!.id];
          final hasOverdueDot = isPlan &&
              allocationItem != null &&
              allocationItem.todo.dueDate != null &&
              allocationItem.todo.dueDate!.isBefore(now);

          final meta = isShort
              ? null
              : _blockMeta(item, calendarNames, allocationItems);

          widgets.add(
            Positioned(
              top: top,
              left: lanes.lane * laneWidth + 1,
              width: math.max(6, laneWidth - 2),
              height: height,
              child: _A2TimeBlock(
                title: item.title,
                meta: meta,
                fill: isPlan ? const Color(0xFFF1F0EA) : ds.tint(accent),
                edge: isPlan ? SpecTokens.work : accent,
                isPlan: isPlan,
                isShort: isShort,
                hasOverdueDot: hasOverdueDot,
                compact: laneWidth < 50,
                onTap: () => _openBlock(item, allocationItems),
                onReschedule: item.canDrag &&
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

        // Timed deadline markers: 1.5px amber/red line + 6px dot + 8px label
        for (final deadline in deadlines) {
          if (!calDeadlineHasTime(deadline.due)) continue;
          if (!calSameDay(deadline.due, day)) continue;
          final dueM = deadline.due.hour * 60 + deadline.due.minute;
          if (dueM < _a2StartMinute || dueM > _a2EndHour * 60) continue;
          final top = _axis.offsetOf(dueM);
          final isOverdue = deadline.due.isBefore(now);
          widgets.add(
            _A2DeadlineMarker(
              top: top,
              title: deadline.title,
              time: DateFormatters.formatTime(deadline.due),
              isOverdue: isOverdue,
            ),
          );
        }

        // Now line: 1.5px red line + 6px circle dot
        if (showNow) {
          final nowM = now.hour * 60 + now.minute;
          widgets.add(
            _A2NowLine(
              key: const ValueKey('calendar-now-line'),
              top: _axis.offsetOf(nowM),
              color: SpecTokens.red,
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

class _DayHeadCell extends StatefulWidget {
  const _DayHeadCell({
    required this.day,
    required this.isToday,
    required this.locale,
    this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final String locale;
  final VoidCallback? onTap;

  @override
  State<_DayHeadCell> createState() => _DayHeadCellState();
}

class _DayHeadCellState extends State<_DayHeadCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final weekdayStr = calWeekdayLong(widget.locale, widget.day);
    final dayNum = widget.day.day.toString();

    final Widget content = Container(
      height: 46,
      decoration: BoxDecoration(
        color: _hovered ? const Color(0xFFFBFBF8) : SpecTokens.paper,
        border: const Border(
          right: BorderSide(color: SpecTokens.hair, width: 1),
          bottom: BorderSide(color: SpecTokens.hair, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 64;
          final weekdayWidget = Text(
            weekdayStr,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              color: widget.isToday ? SpecTokens.red : SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          );

          final dateWidget = widget.isToday
              ? Container(
                  width: isNarrow ? 20 : 22,
                  height: isNarrow ? 20 : 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: SpecTokens.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    dayNum,
                    style: TextStyle(
                      fontSize: isNarrow ? 10.0 : 11.0,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1,
                      fontFeatures: AppTypography.tabular,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                )
              : Text(
                  dayNum,
                  style: TextStyle(
                    fontSize: isNarrow ? 12.0 : 13.0,
                    fontWeight: FontWeight.w500,
                    color: SpecTokens.ink2,
                    height: 1,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                );

          if (isNarrow) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                weekdayWidget,
                const SizedBox(height: 1),
                dateWidget,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              weekdayWidget,
              const SizedBox(width: 7),
              dateWidget,
            ],
          );
        },
      ),
    );

    if (widget.onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      ),
    );
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
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: ds.tint(accent),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _a2Text(9.5, FontWeight.w500, ds.ink, height: 1.2),
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

/// Spec-fidelity calendar block: radius 4, left border 3px (event) / 2px (plan),
/// title 9.5/600, meta 8.5, hide meta when <6%, 4px overdue red dot.
class _A2TimeBlock extends StatefulWidget {
  const _A2TimeBlock({
    required this.title,
    required this.meta,
    required this.fill,
    required this.edge,
    required this.isPlan,
    required this.isShort,
    required this.hasOverdueDot,
    required this.onTap,
    this.onReschedule,
    this.compact = false,
  });

  final String title;
  final String? meta;
  final Color fill;
  final Color edge;
  final bool isPlan;
  final bool isShort;
  final bool hasOverdueDot;
  final bool compact;
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
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: widget.edge, width: widget.isPlan ? 2 : 3),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: widget.isShort
                ? const EdgeInsets.fromLTRB(4, 1, 4, 1)
                : const EdgeInsets.fromLTRB(4, 3, 4, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: widget.isShort
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _a2Text(
                    9.5,
                    FontWeight.w600,
                    widget.isPlan ? const Color(0xFF3B3B33) : ds.ink,
                    height: 1.25,
                  ),
                ),
                if (widget.meta != null && !widget.isShort) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _a2Text(
                      8.5,
                      FontWeight.w400,
                      ds.ink3,
                      height: 1.2,
                      tabular: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.hasOverdueDot)
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ds.danger,
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

/// Authoritative now line: 1.5px red line + 6px circle dot at left -3px.
class _A2NowLine extends StatelessWidget {
  const _A2NowLine({super.key, required this.top, required this.color});

  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top - 2.25,
      left: -3,
      right: 0,
      child: IgnorePointer(
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              Positioned(
                left: 3,
                right: 0,
                top: 2.25,
                child: Container(height: 1.5, color: color),
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
      ),
    );
  }
}

/// Authoritative deadline marker on the time grid:
/// 1.5px amber/red line + 6px dot at left -3px + 8px label at right 3px top -7px.
class _A2DeadlineMarker extends StatelessWidget {
  const _A2DeadlineMarker({
    required this.top,
    required this.title,
    required this.time,
    required this.isOverdue,
  });

  final double top;
  final String title;
  final String time;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final color = isOverdue ? ds.danger : ds.warn;
    return Positioned(
      top: top - 2.25,
      left: -3,
      right: 0,
      child: IgnorePointer(
        child: SizedBox(
          height: 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1.5px horizontal line
              Positioned(
                left: 3,
                right: 0,
                top: 2.25,
                child: Container(height: 1.5, color: color),
              ),
              // 6px dot
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
              // 8px white-background label with fine border
              Positioned(
                right: 3,
                top: -6,
                child: Container(
                  height: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: ds.lineSoft),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Center(
                    child: Text(
                      l.deadlineMarkerLabel(time, title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _a2Text(8.0, FontWeight.w400, color, height: 1.2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobile Week View (List Stacked) based on spec mobileCalendar('week'):
/// Vertical list of 7 days, each day has a head and item rows.
class A2PhoneWeekList extends StatelessWidget {
  const A2PhoneWeekList({
    super.key,
    required this.days,
    required this.today,
    required this.events,
    required this.allocations,
    required this.deadlines,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onReschedule,
    this.onCreateAtDay,
    this.onSlot,
  });

  final List<DateTime> days;
  final DateTime today;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;
  final void Function(CalBlockItem item, int minutes)? onReschedule;
  final ValueChanged<DateTime>? onCreateAtDay;
  final ValueChanged<DateTimeRange>? onSlot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    return ListView(
      key: const ValueKey('phone-week-list-view'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(
          calDateRangeLabel(l, locale, days.first, days.last),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0.01,
            color: SpecTokens.ink,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          l.calendarWeekSummary,
          style: const TextStyle(
            fontSize: 10.5,
            color: SpecTokens.muted,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        const SizedBox(height: 6),
        for (final day in days)
          _A2PhoneWeekDay(
            day: day,
            today: today,
            events: events,
            allocations: allocations,
            deadlines: deadlines,
            onEvent: onEvent,
            onAllocation: onAllocation,
            onDeadline: onDeadline,
            onReschedule: onReschedule,
            onCreateAtDay: onCreateAtDay,
            onSlot: onSlot,
          ),
      ],
    );
  }
}

// One day group of the spec's .m-week-list: a date head, then the day's
// events, plans and deadlines as rows. The desktop 7-column grid is a
// separate widget; this list is the phone structure.
class _A2PhoneWeekDay extends StatelessWidget {
  const _A2PhoneWeekDay({
    required this.day,
    required this.today,
    required this.events,
    required this.allocations,
    required this.deadlines,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onReschedule,
    this.onCreateAtDay,
    this.onSlot,
  });

  final DateTime day;
  final DateTime today;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;
  final void Function(CalBlockItem item, int minutes)? onReschedule;
  final ValueChanged<DateTime>? onCreateAtDay;
  final ValueChanged<DateTimeRange>? onSlot;

  static const double _dragHourHeight = 54;

  bool _eventOnDay(CalendaEventAdapter event) {
    if (calSameDay(event.start, day)) return true;
    if (event.isAllDay || !calSameDay(event.start, event.end)) {
      return calAllDayEvents(day: day, events: [event]).isNotEmpty;
    }
    return false;
  }

  bool get _canCreate => onSlot != null || onCreateAtDay != null;

  void _openCreate() {
    if (onSlot != null) {
      onSlot!(
        DateTimeRange(
          start: DateTime(day.year, day.month, day.day, 9),
          end: DateTime(day.year, day.month, day.day, 10),
        ),
      );
    } else {
      onCreateAtDay?.call(day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final isToday = calSameDay(day, today);
    final dayEvents = [
      for (final event in events)
        if (_eventOnDay(event)) event,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final dayAllocations = [
      for (final item in allocations)
        if (calSameDay(item.allocation.startAt.toLocal(), day)) item,
    ]..sort(
        (a, b) => a.allocation.startAt.compareTo(b.allocation.startAt),
      );
    final dayDeadlines = [
      for (final deadline in deadlines)
        if (calSameDay(deadline.due, day)) deadline,
    ]..sort((a, b) => a.due.compareTo(b.due));
    final count = dayEvents.length + dayAllocations.length + dayDeadlines.length;

    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF2F2ED))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _canCreate ? _openCreate : null,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${calWeekdayLong(locale, day)} · ${day.day}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isToday ? SpecTokens.red : SpecTokens.ink2,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                  Text(
                    l.dayItemCount(count),
                    style: const TextStyle(
                      fontSize: 10,
                      color: SpecTokens.muted,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (count == 0)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _canCreate ? _openCreate : null,
              child: SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l.noSchedule,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: ds.ink3,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ),
            ),
          for (final event in dayEvents)
            _A2PhoneWeekItem(
              color: event.color ?? ds.ink3,
              label: TextSpan(
                children: [
                  TextSpan(
                    text: event.isAllDay
                        ? '${l.allDayLabel} '
                        : '${DateFormatters.formatTime(event.start)} ',
                    style: const TextStyle(color: SpecTokens.muted),
                  ),
                  TextSpan(text: event.title),
                  if (event.rrule != null || event.isRecurringOccurrence)
                    const TextSpan(text: ' ↻'),
                ],
              ),
              onTap: onEvent == null ? null : () => onEvent!(event),
              onReschedule: onReschedule == null || !CalBlockItem.event(event).canDrag
                  ? null
                  : (minutes) => onReschedule!(
                        CalBlockItem.event(event),
                        minutes,
                      ),
              dragHourHeight: _dragHourHeight,
            ),
          for (final item in dayAllocations)
            _A2PhoneWeekItem(
              color: ds.work,
              label: TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${DateFormatters.formatTime(item.allocation.startAt.toLocal())} ',
                    style: const TextStyle(color: SpecTokens.muted),
                  ),
                  TextSpan(text: item.todo.summary),
                  TextSpan(
                    text: ' ${l.scheduledLabel}',
                    style: const TextStyle(color: SpecTokens.faint),
                  ),
                ],
              ),
              onTap: onAllocation == null ? null : () => onAllocation!(item),
              onReschedule: onReschedule == null
                  ? null
                  : (minutes) => onReschedule!(
                        CalBlockItem.allocation(
                          TaskAllocationCalendarAdapter.fromItem(item),
                        ),
                        minutes,
                      ),
              dragHourHeight: _dragHourHeight,
            ),
          for (final deadline in dayDeadlines)
            _A2PhoneWeekItem(
              color: deadline.due.isBefore(today)
                  ? SpecTokens.red
                  : SpecTokens.amber,
              label: TextSpan(
                text: '${l.deadline} ${deadline.title}',
                style: TextStyle(
                  color: deadline.due.isBefore(today)
                      ? SpecTokens.red
                      : SpecTokens.amber,
                ),
              ),
              onTap: onDeadline == null ? null : () => onDeadline!(deadline),
            ),
        ],
      ),
    );
  }
}

class _A2PhoneWeekItem extends StatefulWidget {
  const _A2PhoneWeekItem({
    required this.color,
    required this.label,
    this.onTap,
    this.onReschedule,
    this.dragHourHeight = 54,
  });

  final Color color;
  final InlineSpan label;
  final VoidCallback? onTap;
  final ValueChanged<int>? onReschedule;
  final double dragHourHeight;

  @override
  State<_A2PhoneWeekItem> createState() => _A2PhoneWeekItemState();
}

class _A2PhoneWeekItemState extends State<_A2PhoneWeekItem> {
  double _dragDy = 0;

  bool get _canDrag => widget.onReschedule != null;

  void _finishDrag() {
    final minutes = (_dragDy / widget.dragHourHeight * 60).round();
    setState(() => _dragDy = 0);
    final snapped = (minutes / 30).round() * 30;
    if (snapped != 0) widget.onReschedule!(snapped);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: _canDrag
            ? (_) {
                HapticFeedback.mediumImpact();
                setState(() => _dragDy = 0);
              }
            : null,
        onLongPressMoveUpdate: _canDrag
            ? (details) => setState(() => _dragDy = details.offsetFromOrigin.dy)
            : null,
        onLongPressEnd: _canDrag ? (_) => _finishDrag() : null,
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            decoration: _dragDy == 0
                ? null
                : BoxDecoration(
                    color: SpecTokens.wash,
                    borderRadius: BorderRadius.circular(4),
                  ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.45,
                      color: SpecTokens.ink2,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
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

/// Mobile Day View (List Stacked) based on spec mobileDayView():
/// Day headbar (42px) + all-day chips + deadline chips + time head + stacked items.
class A2PhoneDayList extends StatelessWidget {
  const A2PhoneDayList({
    super.key,
    required this.day,
    required this.now,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.calendarNames,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
  });

  final DateTime day;
  final DateTime now;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final Map<int, String> calendarNames;
  final ValueChanged<CalendaEventAdapter>? onEvent;
  final ValueChanged<TaskAllocationCalendarItem>? onAllocation;
  final ValueChanged<CalendarDeadline>? onDeadline;
  final ValueChanged<DateTimeRange>? onSlot;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final isToday = calSameDay(day, now);

    final allDayEvents = calAllDayEvents(day: day, events: events);
    final dayDeadlines = [
      for (final d in deadlines)
        if (calSameDay(d.due, day)) d,
    ];
    final items = calDayBlocks(
      day: calDayOf(day),
      events: events,
      allocations: _adapt(allocations),
    );
    final allocationItems = {
      for (final a in allocations) a.allocation.id: a,
    };

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Day headbar (42px)
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: ds.surface2,
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: isToday ? l.today : calWeekdayLong(locale, day),
                      style: _a2Text(12, FontWeight.w500, ds.ink),
                    ),
                    TextSpan(
                      text: ' · ${DateFormat.MMMd(locale).format(day)}',
                      style: _a2Text(10.5, FontWeight.w400, ds.ink3),
                    ),
                  ],
                ),
              ),
              Text(
                l.timeArrangementsCount(items.length),
                style: _a2Text(10.5, FontWeight.w400, ds.ink3),
              ),
            ],
          ),
        ),
        // All-day chips
        if (allDayEvents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final event in allDayEvents)
                  _A2AllDayChip(
                    event: event,
                    onTap: () => onEvent?.call(event),
                  ),
              ],
            ),
          ),
        // Deadline chips
        if (dayDeadlines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final dl in dayDeadlines)
                  _deadlineChip(context, dl),
              ],
            ),
          ),
        // Time head
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isToday ? l.today : DateFormat.MMMd(locale).format(day),
                style: _a2Text(11.5, FontWeight.w600, ds.ink),
              ),
              Text(
                l.dayItemCount(items.length),
                style: _a2Text(10.5, FontWeight.w400, ds.ink3),
              ),
            ],
          ),
        ),
        // Stacked list of timed items
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: _mobileTimeRow(context, item, allocationItems),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              l.todayEmptyTime,
              style: _a2Text(11, FontWeight.w400, ds.ink3),
            ),
          ),
      ],
    );
  }

  Widget _deadlineChip(BuildContext context, CalendarDeadline dl) {
    final ds = context.ds;
    final isOverdue = dl.due.isBefore(now);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onDeadline?.call(dl),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isOverdue ? ds.dangerSoft : ds.warnSoft,
          borderRadius: BorderRadius.circular(3),
          border: Border(
            left: BorderSide(color: isOverdue ? ds.danger : ds.warn, width: 2),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${calDeadlineHasTime(dl.due) ? '${DateFormatters.formatTime(dl.due)} ' : ''}${dl.title}',
            style: _a2Text(
              9.5,
              FontWeight.w400,
              isOverdue ? ds.danger : ds.warn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileTimeRow(
    BuildContext context,
    CalBlockItem item,
    Map<int, TaskAllocationCalendarItem> allocationItems,
  ) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final isPlan = item.isAllocation;
    final accent = ds.eventAccent(item.event?.color ?? ds.primary);
    final barColor = isPlan ? ds.work : accent;
    final bgColor = isPlan ? const Color(0xFFF1F0EA) : ds.tint(accent);
    final timeStr = DateFormatters.formatTime(item.start);
    final endStr = DateFormatters.formatTime(item.end);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final ev = item.event;
        if (ev != null) {
          onEvent?.call(ev);
          return;
        }
        final alloc = item.allocation;
        if (alloc != null) {
          final original = allocationItems[alloc.id];
          if (original != null) onAllocation?.call(original);
        }
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              timeStr,
              style: _a2Text(11, FontWeight.w500, ds.ink3, tabular: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border(left: BorderSide(color: barColor, width: isPlan ? 2 : 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _a2Text(
                      11,
                      FontWeight.w600,
                      isPlan ? const Color(0xFF3B3B33) : ds.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isPlan
                        ? l.calendarTimeRowPlanned('$timeStr–$endStr')
                        : '$timeStr–$endStr',
                    style: _a2Text(9.5, FontWeight.w400, ds.ink3, tabular: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
