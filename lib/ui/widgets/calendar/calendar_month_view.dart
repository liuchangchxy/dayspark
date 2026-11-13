import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart' show MonthDayHeaderStyle;

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';

class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
    super.key,
    required this.anchor,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.now,
    required this.onSelectDay,
    required this.onOpenDay,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
  });

  final DateTime anchor;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(anchor.year, anchor.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = calDayOf(now);
    final totalEvents = _monthEventCount(anchor);
    final totalHours = _monthHours(anchor);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 24,
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
                              style: TextStyle(fontSize: 11, color: ds.ink3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cellHeight = ((constraints.maxHeight) / 6).clamp(
                      72.0,
                      132.0,
                    );
                    return Column(
                      key: const ValueKey('calendar-month-body'),
                      children: [
                        for (var week = 0; week < 6; week++)
                          SizedBox(
                            height: cellHeight,
                            child: Row(
                              children: [
                                for (var d = 0; d < 7; d++)
                                  Expanded(
                                    child: _DesktopMonthCell(
                                      date: gridStart.add(
                                        Duration(days: week * 7 + d),
                                      ),
                                      anchor: anchor,
                                      today: today,
                                      inMonth:
                                          gridStart
                                              .add(Duration(days: week * 7 + d))
                                              .month ==
                                          anchor.month,
                                      firstColumn: d == 0,
                                      firstRow: week == 0,
                                      entries: _entriesFor(
                                        context,
                                        gridStart.add(
                                          Duration(days: week * 7 + d),
                                        ),
                                      ),
                                      onSelect: onSelectDay,
                                      onOpen: onOpenDay,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s4),
        SizedBox(
          width: 260,
          child: _MonthRail(
            anchor: anchor,
            today: today,
            totalEvents: totalEvents,
            totalHours: totalHours,
            entries: _agendaEntries(context, anchor),
            onSlot: onSlot,
          ),
        ),
      ],
    );
  }

  int _monthEventCount(DateTime month) {
    return events
        .where(
          (event) =>
              event.start.year == month.year &&
              event.start.month == month.month,
        )
        .length;
  }

  int _monthHours(DateTime month) {
    final minutes = events
        .where(
          (event) =>
              !event.isAllDay &&
              event.start.year == month.year &&
              event.start.month == month.month,
        )
        .fold<int>(
          0,
          (sum, event) => sum + event.end.difference(event.start).inMinutes,
        );
    return (minutes / 60).round();
  }

  List<_MonthEntry> _entriesFor(BuildContext context, DateTime day) {
    final ds = context.ds;
    final entries = <_MonthEntry>[
      for (final event in events)
        if (calSameDay(event.start, day))
          _MonthEntry(
            title: event.title,
            color: event.color ?? ds.primary,
            onTap: onEvent == null ? null : () => onEvent!(event),
          ),
      for (final allocation in allocations)
        if (calSameDay(allocation.start, day))
          _MonthEntry(
            title: allocation.todoTitle,
            color: ds.ink3,
            allocation: true,
            onTap: onAllocation == null
                ? null
                : () => onAllocation!(allocation),
          ),
      for (final deadline in deadlines)
        if (calSameDay(deadline.due, day))
          _MonthEntry(
            title: deadline.title,
            color: ds.warn,
            deadline: true,
            onTap: onDeadline == null ? null : () => onDeadline!(deadline),
          ),
    ];
    return entries;
  }

  List<_AgendaEntry> _agendaEntries(BuildContext context, DateTime day) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final entries =
        <_AgendaEntry>[
          for (final event in events)
            if (calSameDay(event.start, day))
              _AgendaEntry(
                time: event.isAllDay
                    ? l.allDay
                    : DateFormatters.formatTime(event.start),
                title: event.title,
                meta:
                    event.location ??
                    calDuration(l, event.end.difference(event.start)),
                color: event.color ?? ds.primary,
                inProgress:
                    !event.isAllDay &&
                    now.isAfter(event.start) &&
                    now.isBefore(event.end),
                onTap: onEvent == null ? null : () => onEvent!(event),
              ),
          for (final allocation in allocations)
            if (calSameDay(allocation.start, day))
              _AgendaEntry(
                time: DateFormatters.formatTime(allocation.start),
                title: allocation.todoTitle,
                meta: l.scheduledLabel,
                color: ds.ink3,
                onTap: onAllocation == null
                    ? null
                    : () => onAllocation!(allocation),
              ),
          for (final deadline in deadlines)
            if (calSameDay(deadline.due, day))
              _AgendaEntry(
                time: deadline.due.hour == 0 && deadline.due.minute == 0
                    ? l.allDay
                    : DateFormatters.formatTime(deadline.due),
                title: deadline.title,
                meta: l.deadline,
                color: ds.warn,
                onTap: onDeadline == null ? null : () => onDeadline!(deadline),
              ),
        ]..sort((a, b) {
          final aAll = a.time == l.allDay;
          final bAll = b.time == l.allDay;
          if (aAll != bAll) return aAll ? -1 : 1;
          return a.time.compareTo(b.time);
        });
    return entries;
  }
}

class _MonthEntry {
  const _MonthEntry({
    required this.title,
    required this.color,
    this.onTap,
    this.allocation = false,
    this.deadline = false,
  });

  final String title;
  final Color color;
  final VoidCallback? onTap;
  final bool allocation;
  final bool deadline;
}

class _AgendaEntry {
  const _AgendaEntry({
    required this.time,
    required this.title,
    required this.meta,
    required this.color,
    this.onTap,
    this.inProgress = false,
  });

  final String time;
  final String title;
  final String meta;
  final Color color;
  final VoidCallback? onTap;
  final bool inProgress;
}

class _DesktopMonthCell extends StatelessWidget {
  const _DesktopMonthCell({
    required this.date,
    required this.anchor,
    required this.today,
    required this.inMonth,
    required this.firstColumn,
    required this.firstRow,
    required this.entries,
    required this.onSelect,
    required this.onOpen,
  });

  final DateTime date;
  final DateTime anchor;
  final DateTime today;
  final bool inMonth;
  final bool firstColumn;
  final bool firstRow;
  final List<_MonthEntry> entries;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpen;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final isToday = calSameDay(date, today);
    final selected = calSameDay(date, anchor);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(date),
        onDoubleTap: () => onOpen(date),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 6, 7, 4),
          decoration: BoxDecoration(
            color: isToday
                ? ds.primaryTint
                : selected
                ? ds.surface2
                : ds.surface,
            border: Border(
              left: firstColumn
                  ? BorderSide(color: ds.lineSoft)
                  : BorderSide.none,
              top: firstRow ? BorderSide(color: ds.lineSoft) : BorderSide.none,
              right: BorderSide(color: ds.lineSoft),
              bottom: BorderSide(color: ds.lineSoft),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkedMonthDayHeader(
                date: date,
                dim: !inMonth,
                alignStart: true,
                showHolidayBadge: true,
                today: isToday,
                style: MonthDayHeaderStyle(
                  numberTextStyle: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: ds.ink,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              if (inMonth) ...[
                for (final entry in entries.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _MonthBar(entry: entry),
                  ),
                if (entries.length > 3)
                  Text(
                    '+${entries.length - 3}',
                    style: TextStyle(fontSize: 11, color: ds.ink3),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.entry});

  final _MonthEntry entry;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final bg = entry.deadline
        ? ds.warnSoft
        : entry.allocation
        ? ds.surface2
        : ds.tint(entry.color);
    return MouseRegion(
      cursor: entry.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.onTap,
        child: SizedBox(
          height: 17,
          child: CalEdgeBox(
            edgeColor: entry.color,
            background: bg,
            radius: 2,
            edgeWidth: 2,
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: ds.ink2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthRail extends StatelessWidget {
  const _MonthRail({
    required this.anchor,
    required this.today,
    required this.totalEvents,
    required this.totalHours,
    required this.entries,
    this.onSlot,
  });

  final DateTime anchor;
  final DateTime today;
  final int totalEvents;
  final int totalHours;
  final List<_AgendaEntry> entries;
  final void Function(DateTimeRange)? onSlot;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final isToday = calSameDay(anchor, today);
    final dayTitle =
        '${DateFormat.MMMd(locale).format(anchor)} '
        '${DateFormat.E(locale).format(anchor)}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4 + 2),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ds.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            DateFormat.yMMMM(locale).format(anchor),
            style: TextStyle(fontSize: 11, color: ds.ink3),
          ),
          const SizedBox(height: 4),
          Text(
            '${l.eventsAndFree(totalEvents)} · '
            '${l.hoursShort(totalHours)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ds.ink,
              fontFeatures: AppTypography.tabular,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Container(height: 1, color: ds.lineSoft),
          const SizedBox(height: AppSpacing.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  dayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ds.ink,
                  ),
                ),
              ),
              if (isToday)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: ds.primarySoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l.today,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: ds.primary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                l.dayItemCount(entries.length),
                style: TextStyle(fontSize: 11, color: ds.ink3),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Expanded(
            child: entries.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l.nothingScheduled,
                        style: TextStyle(fontSize: 12, color: ds.ink3),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final entry in entries)
                          _RailAgendaRow(entry: entry),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Material(
            color: ds.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onSlot == null
                  ? null
                  : () => onSlot!(
                      DateTimeRange(
                        start: DateTime(
                          anchor.year,
                          anchor.month,
                          anchor.day,
                          9,
                        ),
                        end: DateTime(
                          anchor.year,
                          anchor.month,
                          anchor.day,
                          10,
                        ),
                      ),
                    ),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.add, size: 16, color: ds.onPrimary),
                    const SizedBox(width: 7),
                    Text(
                      l.newEvent,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ds.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailAgendaRow extends StatelessWidget {
  const _RailAgendaRow({required this.entry});

  final _AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: entry.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  entry.time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: ds.ink3,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
              ),
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: entry.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: ds.ink),
                    ),
                    if (!entry.inProgress && entry.meta.isNotEmpty)
                      Text(
                        entry.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: ds.ink3),
                      ),
                  ],
                ),
              ),
              if (entry.inProgress)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 1),
                  child: Text(
                    AppLocalizations.of(context)!.inProgress,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: ds.primary,
                      fontWeight: FontWeight.w600,
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

class CalendarMobileMonthView extends StatelessWidget {
  const CalendarMobileMonthView({
    super.key,
    required this.anchor,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.now,
    required this.onSelectDay,
    required this.onOpenDay,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
  });

  final DateTime anchor;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(anchor.year, anchor.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = calDayOf(now);
    final totalEvents = events
        .where(
          (event) =>
              event.start.year == anchor.year &&
              event.start.month == anchor.month,
        )
        .length;
    final totalMinutes = events
        .where(
          (event) =>
              !event.isAllDay &&
              event.start.year == anchor.year &&
              event.start.month == anchor.month,
        )
        .fold<int>(
          0,
          (sum, event) => sum + event.end.difference(event.start).inMinutes,
        );
    final totalHours = (totalMinutes / 60).round();
    final entries = _mobileAgenda(context, anchor);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s1,
        AppSpacing.s4,
        AppSpacing.s6,
      ),
      children: [
        Row(
          children: [
            const Spacer(),
            Text(
              '${l.eventsAndFree(totalEvents)} · '
              '${l.hoursShort(totalHours)}',
              style: TextStyle(
                fontSize: 11,
                color: ds.ink3,
                fontFeatures: AppTypography.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 22,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      calWeekdayShort(locale, gridStart.add(Duration(days: i))),
                      style: TextStyle(fontSize: 11, color: ds.ink3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ds.line),
          ),
          child: Column(
            children: [
              for (var week = 0; week < 6; week++)
                Row(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Expanded(
                        child: _MobileMonthCell(
                          date: gridStart.add(Duration(days: week * 7 + d)),
                          anchor: anchor,
                          today: today,
                          inMonth:
                              gridStart
                                  .add(Duration(days: week * 7 + d))
                                  .month ==
                              anchor.month,
                          entryCount: _entriesFor(
                            gridStart.add(Duration(days: week * 7 + d)),
                          ),
                          lastRow: week == 5,
                          lastColumn: d == 6,
                          onTap: () => onSelectDay(
                            gridStart.add(Duration(days: week * 7 + d)),
                          ),
                          onDoubleTap: () => onOpenDay(
                            gridStart.add(Duration(days: week * 7 + d)),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Container(
          decoration: BoxDecoration(
            color: ds.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ds.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s3,
                  10,
                  AppSpacing.s3,
                  10,
                ),
                child: Row(
                  children: [
                    Text(
                      '${DateFormat.MMMd(locale).format(anchor)} '
                      '${DateFormat.E(locale).format(anchor)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ds.ink,
                      ),
                    ),
                    if (calSameDay(anchor, today)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: ds.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l.today,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: ds.primary,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      l.dayItemCount(entries.length),
                      style: TextStyle(fontSize: 11, color: ds.ink3),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: ds.lineSoft),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3,
                    vertical: 14,
                  ),
                  child: Text(
                    l.nothingScheduled,
                    style: TextStyle(fontSize: 12, color: ds.ink3),
                  ),
                )
              else
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) Container(height: 1, color: ds.lineSoft),
                  _MobileAgendaRow(entry: entries[i]),
                ],
            ],
          ),
        ),
      ],
    );
  }

  int _entriesFor(DateTime day) {
    return events.where((event) => calSameDay(event.start, day)).length +
        allocations
            .where((allocation) => calSameDay(allocation.start, day))
            .length +
        deadlines.where((deadline) => calSameDay(deadline.due, day)).length;
  }

  List<_AgendaEntry> _mobileAgenda(BuildContext context, DateTime day) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final entries =
        <_AgendaEntry>[
          for (final event in events)
            if (calSameDay(event.start, day))
              _AgendaEntry(
                time: event.isAllDay
                    ? l.allDay
                    : DateFormatters.formatTime(event.start),
                title: event.title,
                meta: event.location ?? '',
                color: event.color ?? ds.primary,
                inProgress:
                    !event.isAllDay &&
                    now.isAfter(event.start) &&
                    now.isBefore(event.end),
                onTap: onEvent == null ? null : () => onEvent!(event),
              ),
          for (final allocation in allocations)
            if (calSameDay(allocation.start, day))
              _AgendaEntry(
                time: DateFormatters.formatTime(allocation.start),
                title: allocation.todoTitle,
                meta: l.scheduledLabel,
                color: ds.ink3,
                onTap: onAllocation == null
                    ? null
                    : () => onAllocation!(allocation),
              ),
          for (final deadline in deadlines)
            if (calSameDay(deadline.due, day))
              _AgendaEntry(
                time: deadline.due.hour == 0 && deadline.due.minute == 0
                    ? l.allDay
                    : DateFormatters.formatTime(deadline.due),
                title: deadline.title,
                meta: l.deadline,
                color: ds.warn,
                onTap: onDeadline == null ? null : () => onDeadline!(deadline),
              ),
        ]..sort((a, b) {
          final aAll = a.time == l.allDay;
          final bAll = b.time == l.allDay;
          if (aAll != bAll) return aAll ? -1 : 1;
          return a.time.compareTo(b.time);
        });
    return entries;
  }
}

class _MobileMonthCell extends StatelessWidget {
  const _MobileMonthCell({
    required this.date,
    required this.anchor,
    required this.today,
    required this.inMonth,
    required this.entryCount,
    required this.lastRow,
    required this.lastColumn,
    required this.onTap,
    required this.onDoubleTap,
  });

  final DateTime date;
  final DateTime anchor;
  final DateTime today;
  final bool inMonth;
  final int entryCount;
  final bool lastRow;
  final bool lastColumn;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final isToday = calSameDay(date, today);
    final selected = calSameDay(date, anchor);
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            decoration: BoxDecoration(
              color: selected || isToday ? ds.primaryTint : ds.surface,
              border: Border(
                right: lastColumn
                    ? BorderSide.none
                    : BorderSide(color: ds.lineSoft),
                bottom: lastRow
                    ? BorderSide.none
                    : BorderSide(color: ds.lineSoft),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: selected || isToday
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: selected || isToday
                        ? ds.primary
                        : inMonth
                        ? ds.ink
                        : ds.faint,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    for (var i = 0; i < (entryCount > 3 ? 3 : entryCount); i++)
                      Container(
                        width: 3.5,
                        height: 3.5,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: selected || isToday ? ds.primary : ds.ink3,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAgendaRow extends StatelessWidget {
  const _MobileAgendaRow({required this.entry});

  final _AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: entry.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: 7,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    entry.time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: ds.ink3,
                      fontFeatures: AppTypography.tabular,
                    ),
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 5, right: 9),
                decoration: BoxDecoration(
                  color: entry.color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ds.ink,
                      ),
                    ),
                    if (entry.meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          entry.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: ds.ink3),
                        ),
                      ),
                  ],
                ),
              ),
              if (entry.inProgress)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: ds.primarySoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.inProgress,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: ds.primary,
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
