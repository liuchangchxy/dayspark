import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';
import 'package:dayspark/ui/widgets/schedule/day_strip.dart';

/// The calendar is a time surface, not a table of events.
///
/// Month is a 6×7 grid of 92px rows with at most three lines per day; week and
/// day are an 8:00–22:00 line grid at 56px per hour. Deadlines that occupy no
/// time are a lane above the grid, never blocks inside it.
class CalendarSection extends ConsumerStatefulWidget {
  const CalendarSection({
    super.key,
    required this.events,
    this.deadlines = const [],
    this.onDeadlineTapped,
    this.allocations = const [],
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onEventChanged,
    this.onTaskAllocationTapped,
    this.onTaskAllocationChanged,
    this.onAnchorChanged,
    this.hideHeader = false,
    this.onHeaderChanged,
  });

  final List<CalendaEventAdapter> events;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<CalendarDeadline>? onDeadlineTapped;
  final List<TaskAllocationCalendarAdapter> allocations;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;
  final Future<void> Function(CalendaEventAdapter event)? onEventChanged;
  final void Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationTapped;
  final Future<void> Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationChanged;
  final void Function(DateTime anchor)? onAnchorChanged;
  final bool hideHeader;
  final void Function(String title, String? subtitle)? onHeaderChanged;

  @override
  ConsumerState<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<CalendarSection> {
  late DateTime _anchorDate;
  String? _lastTitle;
  String? _lastSubtitle;

  CalendarViewMode get _mode => ref.watch(calendarViewModeProvider);

  @override
  void initState() {
    super.initState();
    final viewed = ref.read(viewedDateProvider);
    _anchorDate = DateTime(viewed.year, viewed.month, viewed.day);
  }

  DateTime get _weekStart =>
      _anchorDate.subtract(Duration(days: _anchorDate.weekday - 1));

  void _setAnchor(DateTime next) {
    final date = DateTime(next.year, next.month, next.day);
    if (date == _anchorDate) return;
    setState(() => _anchorDate = date);
    ref.read(viewedDateProvider.notifier).state = date;
    widget.onAnchorChanged?.call(date);
  }

  void _shift(int direction) {
    switch (_mode) {
      case CalendarViewMode.day:
        _setAnchor(_anchorDate.add(Duration(days: direction)));
      case CalendarViewMode.week:
        _setAnchor(_anchorDate.add(Duration(days: 7 * direction)));
      case CalendarViewMode.month:
        _setAnchor(
          DateTime(_anchorDate.year, _anchorDate.month + direction, 1),
        );
    }
  }

  void _goToToday() {
    final now = DateTime.now();
    _setAnchor(DateTime(now.year, now.month, now.day));
  }

  bool get _viewingToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_mode) {
      case CalendarViewMode.day:
        return _anchorDate == today;
      case CalendarViewMode.week:
        final start = _weekStart;
        return !today.isBefore(start) &&
            today.isBefore(start.add(const Duration(days: 7)));
      case CalendarViewMode.month:
        return _anchorDate.year == today.year &&
            _anchorDate.month == today.month;
    }
  }

  String _title(AppLocalizations l) {
    final locale = Localizations.localeOf(context).toString();
    switch (_mode) {
      case CalendarViewMode.day:
        return DateFormat.MMMMEEEEd(locale).format(_anchorDate);
      case CalendarViewMode.week:
        final end = _weekStart.add(const Duration(days: 6));
        return '${DateFormat.MMMd(locale).format(_weekStart)} – '
            '${DateFormat.MMMd(locale).format(end)}';
      case CalendarViewMode.month:
        return DateFormat.yMMMM(locale).format(_anchorDate);
    }
  }

  void _emitHeader() {
    final l = AppLocalizations.of(context)!;
    final title = _title(l);
    final locale = Localizations.localeOf(context).toString();
    final weekday = switch (_mode) {
      CalendarViewMode.day || CalendarViewMode.week =>
        '${DateFormat.Md(locale).format(_anchorDate)} · '
            '${DateFormat.E(locale).format(_anchorDate)}',
      CalendarViewMode.month => '${_anchorDate.month}/${_anchorDate.year}',
    };
    if (title == _lastTitle && weekday == _lastSubtitle) return;
    _lastTitle = title;
    _lastSubtitle = weekday;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHeaderChanged?.call(title, weekday);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    _emitHeader();
    final mode = _mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.s2,
            bottom: AppSpacing.s2,
          ),
          child: Row(
            children: [
              DsSegmented<CalendarViewMode>(
                height: 30,
                selected: mode,
                options: [
                  DsSegmentOption(CalendarViewMode.day, l.day),
                  DsSegmentOption(CalendarViewMode.week, l.week),
                  DsSegmentOption(CalendarViewMode.month, l.month),
                ],
                onSelected: (next) => ref
                    .read(calendarViewModeProvider.notifier)
                    .setViewMode(next),
              ),
              const Spacer(),
              if (!_viewingToday)
                DsButton(
                  label: l.today,
                  tone: DsButtonTone.ghost,
                  small: true,
                  onPressed: _goToToday,
                ),
              DsIconButton(
                icon: CupertinoIcons.chevron_left,
                size: 18,
                compact: true,
                tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                onPressed: () => _shift(-1),
              ),
              DsIconButton(
                icon: CupertinoIcons.chevron_right,
                size: 18,
                compact: true,
                tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                onPressed: () => _shift(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (mode) {
            CalendarViewMode.month => _MonthView(
              anchor: _anchorDate,
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              desktop: desktop,
              onSelectDay: _setAnchor,
              onOpenDay: (day) {
                _setAnchor(day);
                ref
                    .read(calendarViewModeProvider.notifier)
                    .setViewMode(CalendarViewMode.day);
              },
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
            ),
            CalendarViewMode.week when !desktop => _WeekAgenda(
              days: List.generate(7, (i) => _weekStart.add(Duration(days: i))),
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onOpenDay: (day) {
                _setAnchor(day);
                ref
                    .read(calendarViewModeProvider.notifier)
                    .setViewMode(CalendarViewMode.day);
              },
            ),
            CalendarViewMode.week => _TimeGrid(
              days: List.generate(7, (i) => _weekStart.add(Duration(days: i))),
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onSlot: widget.onTimeSlotTapped,
              onEventRescheduled: widget.onEventChanged,
              onAllocationRescheduled: widget.onTaskAllocationChanged,
              showNow: true,
            ),
            CalendarViewMode.day when !desktop => _MobileDayView(
              day: _anchorDate,
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              onPickDay: _setAnchor,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onSlot: widget.onTimeSlotTapped,
              onEventRescheduled: widget.onEventChanged,
              onAllocationRescheduled: widget.onTaskAllocationChanged,
            ),
            CalendarViewMode.day => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _TimeGrid(
                  days: [_anchorDate],
                  events: widget.events,
                  allocations: widget.allocations,
                  deadlines: widget.deadlines,
                  onEvent: widget.onEventTapped,
                  onAllocation: widget.onTaskAllocationTapped,
                  onDeadline: widget.onDeadlineTapped,
                  onSlot: widget.onTimeSlotTapped,
                  onEventRescheduled: widget.onEventChanged,
                  onAllocationRescheduled: widget.onTaskAllocationChanged,
                  showNow: true,
                  singleDay: true,
                ),
              ),
            ),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- month

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.anchor,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.desktop,
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
  final bool desktop;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final first = DateTime(anchor.year, anchor.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = _dayOf(DateTime.now());
    final heads = [
      for (var i = 0; i < 7; i++)
        _weekdayLabel(locale, gridStart.add(Duration(days: i))),
    ];

    return ListView(
      key: const ValueKey('calendar-month-body'),
      padding: EdgeInsets.only(
        bottom: AppSpacing.s6,
        left: desktop ? 0 : AppSpacing.s4,
        right: desktop ? 0 : AppSpacing.s4,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                DateFormat.yMMMM(locale).format(anchor),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: ds.ink,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final head in heads)
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: Text(
                      head,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: ds.ink3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var week = 0; week < 6; week++)
          SizedBox(
            height: desktop ? 92 : 52,
            child: Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: _MonthCell(
                      date: gridStart.add(Duration(days: week * 7 + d)),
                      inMonth:
                          gridStart.add(Duration(days: week * 7 + d)).month ==
                          anchor.month,
                      selected:
                          _dayOf(gridStart.add(Duration(days: week * 7 + d))) ==
                          _dayOf(anchor),
                      today:
                          _dayOf(gridStart.add(Duration(days: week * 7 + d))) ==
                          today,
                      entries: _entriesFor(
                        context,
                        gridStart.add(Duration(days: week * 7 + d)),
                      ),
                      compact: !desktop,
                      hasDeadline: deadlines.any(
                        (deadline) =>
                            _dayOf(deadline.due) ==
                            _dayOf(gridStart.add(Duration(days: week * 7 + d))),
                      ),
                      deadlines: [
                        for (final deadline in deadlines)
                          if (_dayOf(deadline.due) ==
                              _dayOf(
                                gridStart.add(Duration(days: week * 7 + d)),
                              ))
                            deadline,
                      ],
                      desktop: desktop,
                      onTap: () => onSelectDay(
                        gridStart.add(Duration(days: week * 7 + d)),
                      ),
                      onDoubleTap: () => onOpenDay(
                        gridStart.add(Duration(days: week * 7 + d)),
                      ),
                      onEvent: onEvent,
                      onAllocation: onAllocation,
                      onDeadline: onDeadline,
                    ),
                  ),
              ],
            ),
          ),
        DsSectionLabel(
          '${DateFormat.MMMd(locale).format(anchor)} '
          '\u00b7 ${DateFormat.E(locale).format(anchor)}',
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.s4,
            0,
            AppSpacing.s1,
          ),
        ),
        ..._agendaFor(context, _dayOf(anchor)),
      ],
    );
  }

  List<Widget> _agendaFor(BuildContext context, DateTime day) {
    final rows = <Widget>[];
    final dayEvents = events.where((e) => _dayOf(e.start) == day).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final dayAllocations =
        allocations.where((a) => _dayOf(a.start) == day).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final dayDeadlines = deadlines.where((d) => _dayOf(d.due) == day).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    for (final event in dayEvents) {
      rows.add(
        _AgendaRow(
          time: event.isAllDay
              ? AppLocalizations.of(context)!.allDay
              : DateFormatters.formatTime(event.start),
          title: event.title,
          meta: event.location,
          color: event.color,
          onTap: onEvent == null ? null : () => onEvent!(event),
        ),
      );
    }
    for (final allocation in dayAllocations) {
      rows.add(
        _AgendaRow(
          time: DateFormatters.formatTime(allocation.start),
          title: allocation.todoTitle,
          meta:
              '${AppLocalizations.of(context)!.plannedExecution} '
              '${DateFormatters.formatTime(allocation.start)}–'
              '${DateFormatters.formatTime(allocation.end)}',
          planned: true,
          onTap: onAllocation == null ? null : () => onAllocation!(allocation),
        ),
      );
    }
    for (final deadline in dayDeadlines) {
      final due = deadline.due.toLocal();
      final hasTime = due.hour != 0 || due.minute != 0;
      rows.add(
        _AgendaRow(
          time: hasTime
              ? DateFormatters.formatTime(due)
              : AppLocalizations.of(context)!.allDay,
          title: deadline.title,
          meta: hasTime
              ? '${AppLocalizations.of(context)!.deadline} '
                    '${DateFormatters.formatTime(due)}'
              : '${AppLocalizations.of(context)!.deadline} '
                    '${DateFormat.MMMd(Localizations.localeOf(context).toString()).format(due)}',
          due: true,
          onTap: onDeadline == null ? null : () => onDeadline!(deadline),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            AppLocalizations.of(context)!.nothingScheduled,
            style: AppTypography.small.copyWith(color: context.ds.ink3),
          ),
        ),
      );
    }
    return rows;
  }

  List<_MonthEntry> _entriesFor(BuildContext context, DateTime day) {
    final ds = context.ds;
    final result = <_MonthEntry>[
      for (final e in events)
        if (_dayOf(e.start) == day)
          _MonthEntry(title: e.title, color: e.color ?? ds.primary, event: e),
      for (final a in allocations)
        if (_dayOf(a.start) == day)
          _MonthEntry(title: a.todoTitle, color: ds.ink3, allocation: a),
    ];
    return result;
  }
}

class _MonthEntry {
  const _MonthEntry({
    required this.title,
    required this.color,
    this.event,
    this.allocation,
  });
  final String title;
  final Color color;
  final CalendaEventAdapter? event;
  final TaskAllocationCalendarAdapter? allocation;
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.entries,
    required this.hasDeadline,
    required this.deadlines,
    required this.compact,
    required this.desktop,
    required this.onTap,
    required this.onDoubleTap,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
  });

  final DateTime date;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<_MonthEntry> entries;
  final bool hasDeadline;
  final List<CalendarDeadline> deadlines;
  final bool compact;
  final bool desktop;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    if (compact) return _compact(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 6, 7, 4),
          decoration: BoxDecoration(
            color: selected ? ds.surface2 : ds.surface,
            border: Border(
              right: BorderSide(color: ds.lineSoft),
              bottom: BorderSide(color: ds.lineSoft),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkedMonthDayHeader(date: date, dim: !inMonth, selected: today),
              const SizedBox(height: 2),
              for (final line in _lines(context))
                Text(
                  line.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: line.$2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, Color)> _lines(BuildContext context) {
    final ds = context.ds;
    final items = <(String, Color)>[
      for (final entry in entries)
        if (entry.event != null)
          (
            '${entry.event!.isAllDay ? AppLocalizations.of(context)!.allDay : DateFormatters.formatTime(entry.event!.start)} '
                '${entry.title}',
            ds.ink2,
          )
        else
          (
            '${AppLocalizations.of(context)!.plannedShort} ${entry.title}',
            ds.ink3,
          ),
      for (final deadline in deadlines)
        (
          '${AppLocalizations.of(context)!.deadline} ${deadline.title}',
          ds.warn,
        ),
    ];
    if (items.length <= 3) return items;
    return [items[0], items[1], ('+${items.length - 2}', ds.ink3)];
  }

  Widget _compact(BuildContext context) {
    final ds = context.ds;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MarkedMonthDayHeader(date: date, dim: !inMonth, selected: selected),
            const SizedBox(height: 2),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < entries.take(3).length; i++)
                    Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: selected ? ds.onPrimary : ds.ink3,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- week agenda

class _WeekAgenda extends StatelessWidget {
  const _WeekAgenda({
    required this.days,
    required this.events,
    required this.allocations,
    required this.deadlines,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    required this.onOpenDay,
  });

  final List<DateTime> days;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final today = _dayOf(DateTime.now());
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      children: [
        for (var i = 0; i < days.length; i++)
          _WeekDaySection(
            day: days[i],
            first: i == 0,
            isToday: _dayOf(days[i]) == today,
            count: _countFor(days[i]),
            rows: _rows(context, days[i]),
            onOpenDay: () => onOpenDay(days[i]),
          ),
      ],
    );
  }

  int _countFor(DateTime day) {
    final dayAllocations = allocations.where((a) => _dayOf(a.start) == day);
    final plannedTodoIds = {for (final a in dayAllocations) a.todoId};
    final eventsCount = events.where((e) => _dayOf(e.start) == day).length;
    final deadlinesCount = deadlines
        .where((d) => _dayOf(d.due) == day)
        .where((d) => !plannedTodoIds.contains(d.todoId))
        .length;
    return eventsCount + dayAllocations.length + deadlinesCount;
  }

  List<Widget> _rows(BuildContext context, DateTime day) {
    final l = AppLocalizations.of(context)!;
    final rows = <Widget>[];
    final dayEvents = events.where((e) => _dayOf(e.start) == day).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final dayAllocations =
        allocations.where((a) => _dayOf(a.start) == day).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final dayDeadlines = deadlines.where((d) => _dayOf(d.due) == day).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final plannedTodoIds = {for (final a in dayAllocations) a.todoId};
    for (final event in dayEvents) {
      rows.add(
        _WeekRow(
          time: event.isAllDay
              ? l.allDay
              : DateFormatters.formatTime(event.start),
          title: event.title,
          meta: [
            if (!event.isAllDay)
              '${DateFormatters.formatTime(event.start)}\u2013'
                  '${DateFormatters.formatTime(event.end)}',
            if (event.location != null && event.location!.isNotEmpty)
              event.location!,
          ].join(' \u00b7 '),
          accent: event.color,
          onTap: onEvent == null ? null : () => onEvent!(event),
        ),
      );
    }
    for (final allocation in dayAllocations) {
      rows.add(
        _WeekRow(
          time: DateFormatters.formatTime(allocation.start),
          title: allocation.todoTitle,
          meta:
              '${l.plannedExecution} '
              '${DateFormatters.formatTime(allocation.start)}\u2013'
              '${DateFormatters.formatTime(allocation.end)}',
          planned: true,
          onTap: onAllocation == null ? null : () => onAllocation!(allocation),
        ),
      );
    }
    for (final deadline in dayDeadlines) {
      if (plannedTodoIds.contains(deadline.todoId)) continue;
      rows.add(
        _WeekRow(
          time: l.deadline,
          title: deadline.title,
          meta: _deadlineMeta(context, deadline),
          due: true,
          onTap: onDeadline == null ? null : () => onDeadline!(deadline),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            l.noPlansDay,
            style: TextStyle(fontSize: 12.5, color: context.ds.ink3),
          ),
        ),
      );
    }
    return rows;
  }

  String _deadlineMeta(BuildContext context, CalendarDeadline deadline) {
    final l = AppLocalizations.of(context)!;
    final due = deadline.due.toLocal();
    final hasTime = due.hour != 0 || due.minute != 0;
    if (!hasTime) {
      final locale = Localizations.localeOf(context).toString();
      return '${l.deadline} \u00b7 ${DateFormat.Md(locale).format(due)}';
    }
    return '${l.deadline} \u00b7 ${DateFormatters.formatTime(due)}';
  }
}

class _WeekDaySection extends StatelessWidget {
  const _WeekDaySection({
    required this.day,
    required this.first,
    required this.isToday,
    required this.count,
    required this.rows,
    required this.onOpenDay,
  });

  final DateTime day;
  final bool first;
  final bool isToday;
  final int count;
  final List<Widget> rows;
  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: ds.lineSoft)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: onOpenDay,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Text(
                      '${DateFormat.E(locale).format(day)} \u00b7 '
                      '${DateFormat.Md(locale).format(day)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isToday ? ds.primary : ds.ink,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: AppSpacing.s2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: ds.primarySoft,
                          borderRadius: BorderRadius.circular(999),
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
                    if (count > 0)
                      Text(
                        l.dayItemCount(count),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ds.ink3,
                          fontFeatures: AppTypography.tabular,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 7, bottom: AppSpacing.s2),
            child: Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: ds.lineSoft)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.time,
    required this.title,
    this.meta,
    this.accent,
    this.planned = false,
    this.due = false,
    this.onTap,
  });

  final String time;
  final String title;
  final String? meta;
  final Color? accent;
  final bool planned;
  final bool due;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final barColor = due
        ? ds.warm
        : (planned ? ds.ink3 : (accent ?? ds.primary));
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: due ? ds.warm : ds.ink3,
                        fontFeatures: AppTypography.tabular,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 3,
                  height: 30,
                  margin: const EdgeInsets.only(right: 10, top: 1),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: ds.ink,
                        ),
                      ),
                      if (meta != null && meta!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: due ? ds.warm : ds.ink3,
                            ),
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

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.time,
    required this.title,
    this.meta,
    this.color,
    this.planned = false,
    this.due = false,
    this.onTap,
  });

  final String time;
  final String title;
  final String? meta;
  final Color? color;
  final bool planned;
  final bool due;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final accent = due ? ds.warm : (color ?? ds.primary);
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ds.lineSoft)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    time,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: due ? ds.warm : ds.ink3,
                      fontFeatures: AppTypography.tabular,
                    ),
                  ),
                ),
                Container(
                  width: 2,
                  height: 30,
                  margin: const EdgeInsets.only(right: 8, top: 1),
                  decoration: due
                      ? BoxDecoration(
                          border: Border.all(color: ds.warm),
                          borderRadius: BorderRadius.circular(1),
                        )
                      : BoxDecoration(
                          color: planned ? ds.ink3 : accent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: ds.ink,
                        ),
                      ),
                      if (meta != null && meta!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: ds.ink3),
                          ),
                        ),
                    ],
                  ),
                ),
                if (planned)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      CupertinoIcons.square,
                      size: 13,
                      color: ds.ink3,
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

// ---------------------------------------------------------------- time grid

const double _hourHeight = 56;
const int _startHour = 8;
const int _endHour = 22;

class _TimeGrid extends StatefulWidget {
  const _TimeGrid({
    required this.days,
    required this.events,
    required this.allocations,
    required this.deadlines,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onEventRescheduled,
    this.onAllocationRescheduled,
    this.showNow = true,
    this.singleDay = false,
    this.showHeader = true,
    this.showDeadlines = true,
  });

  final List<DateTime> days;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;
  final Future<void> Function(CalendaEventAdapter)? onEventRescheduled;
  final Future<void> Function(TaskAllocationCalendarAdapter)?
  onAllocationRescheduled;
  final bool showNow;
  final bool singleDay;
  final bool showHeader;
  final bool showDeadlines;

  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: (8 - _startHour) * _hourHeight,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<DateTime> get days => widget.days;
  List<CalendaEventAdapter> get events => widget.events;
  List<TaskAllocationCalendarAdapter> get allocations => widget.allocations;
  List<CalendarDeadline> get deadlines => widget.deadlines;
  void Function(CalendaEventAdapter)? get onEvent => widget.onEvent;
  void Function(TaskAllocationCalendarAdapter)? get onAllocation =>
      widget.onAllocation;
  void Function(CalendarDeadline)? get onDeadline => widget.onDeadline;
  void Function(DateTimeRange)? get onSlot => widget.onSlot;
  bool get showNow => widget.showNow;

  double get _height => (_endHour - _startHour) * _hourHeight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final today = _dayOf(DateTime.now());
    const gutter = 52.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = (constraints.maxWidth - gutter) / days.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeader)
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    const SizedBox(width: gutter),
                    for (final day in days)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdayLabel(locale, day),
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                color: _dayOf(day) == today
                                    ? ds.primary
                                    : ds.ink3,
                              ),
                            ),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: _dayOf(day) == today
                                    ? ds.primary
                                    : ds.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (_hasAllDay) ...[
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Center(
                        child: Text(
                          l.allDay,
                          style: TextStyle(fontSize: 10.5, color: ds.ink3),
                        ),
                      ),
                    ),
                    for (final day in days)
                      Expanded(child: _allDayCell(context, day)),
                  ],
                ),
              ),
            ],
            if (widget.showDeadlines)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5, right: 8),
                          child: Text(
                            l.deadline,
                            style: TextStyle(fontSize: 10, color: ds.ink3),
                          ),
                        ),
                      ),
                    ),
                    for (final day in days)
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 30),
                          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: ds.lineSoft),
                              bottom: BorderSide(color: ds.line),
                            ),
                          ),
                          child: _deadlineCell(context, day),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('calendar-time-grid'),
                controller: _scroll,
                child: SizedBox(
                  height: _height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var h = _startHour; h <= _endHour; h++)
                        Positioned(
                          top: (h - _startHour) * _hourHeight,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: gutter,
                                child: Transform.translate(
                                  offset: Offset(0, h == _startHour ? 0 : -7),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        '${h.toString().padLeft(2, '0')}:00',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: ds.ink3,
                                          fontFeatures: AppTypography.tabular,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: h == _startHour || h == _endHour
                                      ? ds.line
                                      : ds.lineSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (var i = 0; i < days.length; i++)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: gutter + i * colWidth,
                          width: colWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: i == 0 ? ds.lineSoft : ds.line,
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (var i = 0; i < days.length; i++)
                        Positioned(
                          top: 0,
                          left: gutter + i * colWidth,
                          width: colWidth,
                          height: _height,
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
                                                  _hourHeight *
                                                  60)
                                              .round();
                                      var start = DateTime(
                                        days[i].year,
                                        days[i].month,
                                        days[i].day,
                                        _startHour,
                                      ).add(Duration(minutes: minutes));
                                      start = DateTime(
                                        start.year,
                                        start.month,
                                        start.day,
                                        start.hour,
                                        (start.minute ~/ 30) * 30,
                                      );
                                      onSlot!(
                                        DateTimeRange(
                                          start: start,
                                          end: start.add(
                                            const Duration(hours: 1),
                                          ),
                                        ),
                                      );
                                    },
                            ),
                          ),
                        ),
                      ..._nowLine(context, days, gutter, colWidth),
                      for (var i = 0; i < days.length; i++)
                        ..._blocks(context, days[i], i, gutter, colWidth),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reschedule(_BlockItem item, int minutes) async {
    if (minutes == 0) return;
    final shift = Duration(minutes: minutes);
    final l = AppLocalizations.of(context)!;
    try {
      if (item.event != null) {
        final event = item.event!;
        if (event.rrule != null ||
            event.isRecurringOccurrence ||
            event.isAllDay) {
          return;
        }
        final handler = widget.onEventRescheduled;
        if (handler == null) return;
        await handler(
          event.copyWithData(
            start: event.start.add(shift),
            end: event.end.add(shift),
          ),
        );
      } else {
        final allocation = item.allocation!;
        final handler = widget.onAllocationRescheduled;
        if (handler == null) return;
        await handler(
          allocation.copyWith(
            start: allocation.start.add(shift),
            end: allocation.end.add(shift),
          ),
        );
      }
    } on Object catch (error) {
      debugPrint('calendar: reschedule failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
    }
  }

  bool get _hasAllDay => events.any(
    (e) => e.isAllDay && days.any((d) => _dayOf(d) == _dayOf(e.start)),
  );

  Widget _allDayCell(BuildContext context, DateTime day) {
    final ds = context.ds;
    final items = events
        .where((e) => e.isAllDay && _dayOf(e.start) == _dayOf(day))
        .toList();
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: ds.lineSoft)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final event in items)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: GestureDetector(
                  onTap: onEvent == null ? null : () => onEvent!(event),
                  child: Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: ds.tint(event.color ?? ds.primary),
                      borderRadius: BorderRadius.circular(3),
                      border: Border(
                        left: BorderSide(
                          color: event.color ?? ds.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      event.title,
                      style: TextStyle(fontSize: 10, color: ds.ink2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _deadlineCell(BuildContext context, DateTime day) {
    final ds = context.ds;
    final items = deadlines.where((d) => _dayOf(d.due) == _dayOf(day)).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    if (items.isEmpty) return const SizedBox(height: 24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items.take(2))
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDeadline == null ? null : () => onDeadline!(item),
              child: Text(
                item.due.hour != 0 || item.due.minute != 0
                    ? '${DateFormatters.formatTime(item.due)} ${item.title}'
                    : item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: ds.warm,
                ),
              ),
            ),
          ),
        if (items.length > 2)
          Text(
            '+${items.length - 2}',
            style: TextStyle(fontSize: 10, height: 1.4, color: ds.ink3),
          ),
      ],
    );
  }

  List<Widget> _nowLine(
    BuildContext context,
    List<DateTime> days,
    double gutter,
    double colWidth,
  ) {
    if (!showNow) return const [];
    final now = DateTime.now();
    final index = days.indexWhere((d) => _dayOf(d) == _dayOf(now));
    if (index < 0) return const [];
    final minutes = now.hour * 60 + now.minute - _startHour * 60;
    if (minutes < 0 || minutes > (_endHour - _startHour) * 60) return const [];
    final top = minutes / 60 * _hourHeight;
    final ds = context.ds;
    return [
      Positioned(
        top: top,
        left: gutter,
        right: 0,
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(height: 2, color: ds.warm),
              Positioned(
                left: index * colWidth + 4,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  color: ds.warm,
                  child: Text(
                    DateFormatters.formatTime(now),
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      color: ds.onPrimary,
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

  List<Widget> _blocks(
    BuildContext context,
    DateTime day,
    int index,
    double gutter,
    double colWidth,
  ) {
    final ds = context.ds;
    final dayStart = DateTime(day.year, day.month, day.day, _startHour);
    final dayEnd = DateTime(day.year, day.month, day.day, _endHour);

    final items = <_BlockItem>[];
    for (final event in events) {
      if (event.isAllDay) continue;
      if (_dayOf(event.start) != _dayOf(day)) continue;
      items.add(_BlockItem(event: event));
    }
    for (final allocation in allocations) {
      if (_dayOf(allocation.start) != _dayOf(day)) continue;
      items.add(_BlockItem(allocation: allocation));
    }
    items.sort((a, b) => a.start.compareTo(b.start));

    final lanes = <int>[];
    final laneEnds = <DateTime>[];
    for (final item in items) {
      var lane = laneEnds.indexWhere((end) => !end.isAfter(item.start));
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(item.end);
      } else {
        laneEnds[lane] = item.end;
      }
      lanes.add(lane);
    }
    final laneCount = laneEnds.isEmpty ? 1 : laneEnds.length;

    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final start = item.start.isBefore(dayStart) ? dayStart : item.start;
      final end = item.end.isAfter(dayEnd) ? dayEnd : item.end;
      if (!end.isAfter(start)) continue;
      final top = start.difference(dayStart).inMinutes / 60 * _hourHeight + 1;
      final height = (end.difference(start).inMinutes / 60 * _hourHeight).clamp(
        18.0,
        _height,
      );
      final laneWidth = colWidth / laneCount;
      widgets.add(
        Positioned(
          top: top,
          left: gutter + index * colWidth + lanes[i] * laneWidth + 1,
          width: laneWidth - 3,
          height: height,
          child: _GridBlock(
            item: item,
            color: item.color ?? ds.primary,
            onTap: item.event != null
                ? () => onEvent?.call(item.event!)
                : () => onAllocation?.call(item.allocation!),
            onReschedule: (minutes) => _reschedule(item, minutes),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _MobileDayView extends StatelessWidget {
  const _MobileDayView({
    required this.day,
    required this.events,
    required this.allocations,
    required this.deadlines,
    required this.onPickDay,
    this.onEvent,
    this.onAllocation,
    this.onDeadline,
    this.onSlot,
    this.onEventRescheduled,
    this.onAllocationRescheduled,
  });

  final DateTime day;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<DateTime> onPickDay;
  final void Function(CalendaEventAdapter)? onEvent;
  final void Function(TaskAllocationCalendarAdapter)? onAllocation;
  final void Function(CalendarDeadline)? onDeadline;
  final void Function(DateTimeRange)? onSlot;
  final Future<void> Function(CalendaEventAdapter)? onEventRescheduled;
  final Future<void> Function(TaskAllocationCalendarAdapter)?
  onAllocationRescheduled;

  @override
  Widget build(BuildContext context) {
    final target = _dayOf(day);
    bool hasItems(DateTime date) {
      final d = _dayOf(date);
      return events.any((e) => _dayOf(e.start) == d) ||
          allocations.any((a) => _dayOf(a.start) == d) ||
          deadlines.any((x) => _dayOf(x.due) == d);
    }

    final dayDeadlines =
        deadlines.where((d) => _dayOf(d.due) == target).toList()
          ..sort((a, b) => a.due.compareTo(b.due));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DayStrip(selected: target, onPick: onPickDay, hasItems: hasItems),
        if (dayDeadlines.isNotEmpty)
          _DeadlineLane(deadlines: dayDeadlines, onTap: onDeadline),
        Expanded(
          child: _TimeGrid(
            days: [target],
            events: events,
            allocations: allocations,
            deadlines: deadlines,
            onEvent: onEvent,
            onAllocation: onAllocation,
            onDeadline: onDeadline,
            onSlot: onSlot,
            onEventRescheduled: onEventRescheduled,
            onAllocationRescheduled: onAllocationRescheduled,
            singleDay: true,
            showHeader: false,
            showDeadlines: false,
          ),
        ),
      ],
    );
  }
}

class _DeadlineLane extends StatelessWidget {
  const _DeadlineLane({required this.deadlines, this.onTap});

  final List<CalendarDeadline> deadlines;
  final void Function(CalendarDeadline)? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s2 + 2,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: ds.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: ds.warnSoft,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      border: Border.all(color: ds.warn, width: 1.4),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l.deadlineLane(deadlines.length),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ds.warn,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(AppSpacing.s2),
                itemCount: deadlines.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final item = deadlines[index];
                  return _DeadlineCard(
                    deadline: item,
                    onTap: onTap == null ? null : () => onTap!(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({required this.deadline, this.onTap});

  final CalendarDeadline deadline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final due = deadline.due.toLocal();
    final hasTime = due.hour != 0 || due.minute != 0;
    return Material(
      color: ds.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasTime ? DateFormatters.formatTime(due) : l.allDay,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ds.warn,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Flexible(
                child: Text(
                  deadline.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: ds.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockItem {
  _BlockItem({this.event, this.allocation})
    : assert(event != null || allocation != null);

  final CalendaEventAdapter? event;
  final TaskAllocationCalendarAdapter? allocation;

  DateTime get start => event?.start ?? allocation!.start;
  DateTime get end => event?.end ?? allocation!.end;

  String get title => event?.title ?? allocation!.todoTitle;

  Color? get color => event?.color;
}

class _GridBlock extends StatefulWidget {
  const _GridBlock({
    required this.item,
    required this.color,
    required this.onTap,
    required this.onReschedule,
  });

  final _BlockItem item;
  final Color color;
  final VoidCallback onTap;
  final ValueChanged<int> onReschedule;

  @override
  State<_GridBlock> createState() => _GridBlockState();
}

class _GridBlockState extends State<_GridBlock> {
  double _dragDy = 0;

  bool get _canDrag {
    final event = widget.item.event;
    if (event == null) return true;
    return event.rrule == null &&
        !event.isRecurringOccurrence &&
        !event.isAllDay;
  }

  void _endDrag(LongPressEndDetails _) {
    final minutes = (_dragDy / _hourHeight * 60).round();
    widget.onReschedule(((minutes / 30).round()) * 30);
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final item = widget.item;
    final color = widget.color;
    final planned = item.allocation != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: _canDrag ? (_) => _dragDy = 0 : null,
        onLongPressMoveUpdate: _canDrag
            ? (details) => _dragDy = details.offsetFromOrigin.dy
            : null,
        onLongPressEnd: _canDrag ? _endDrag : null,
        child: Container(
          decoration: BoxDecoration(
            color: planned ? Colors.transparent : ds.tint(color),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              left: BorderSide(color: planned ? ds.ink3 : color, width: 2),
            ),
          ),
          child: CustomPaint(
            painter: planned ? _DashedPainter(ds.line) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 3, 4, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: ds.ink,
                    ),
                  ),
                  Text(
                    '${DateFormatters.formatTime(item.start)}–'
                    '${DateFormatters.formatTime(item.end)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, height: 1.3, color: ds.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}

DateTime _dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

String _weekdayLabel(String locale, DateTime date) {
  final full = DateFormat.E(locale).format(date);
  if (locale.startsWith('zh') && full.isNotEmpty) {
    return full.substring(full.length - 1);
  }
  return full;
}

/// Kept for callers that imported the old lane directly from this file.
typedef CalendarDeadlineLaneView = CalendarDeadlineLane;
