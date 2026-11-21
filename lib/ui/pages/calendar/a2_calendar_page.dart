import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart' show Calendar;
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_filter_sheet.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

class A2CalendarPage extends ConsumerStatefulWidget {
  const A2CalendarPage({
    super.key,
    required this.events,
    required this.allocations,
    required this.deadlines,
    this.onEventTapped,
    this.onAllocationTapped,
    this.onDeadlineTapped,
    this.onTimeSlotTapped,
    this.onCreateAtDay,
    this.onEventChanged,
    this.onAllocationChanged,
  });

  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(TaskAllocationCalendarItem item)? onAllocationTapped;
  final void Function(CalendarDeadline deadline)? onDeadlineTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;

  /// The month grid has no time axis, so its "+" carries a day and nothing
  /// else: a time span invented there would become a planned slot the user
  /// never picked.
  final void Function(DateTime day)? onCreateAtDay;
  final Future<void> Function(CalendaEventAdapter event)? onEventChanged;
  final Future<void> Function(TaskAllocationCalendarItem item)?
  onAllocationChanged;

  @override
  ConsumerState<A2CalendarPage> createState() => _A2CalendarPageState();
}

class _A2CalendarPageState extends ConsumerState<A2CalendarPage> {
  void _setBrowse(DateTime value) {
    final day = calDayOf(value);
    if (calSameDay(day, ref.read(viewedDateProvider))) return;
    ref.read(viewedDateProvider.notifier).state = day;
  }

  void _shift(int direction) {
    final mode = ref.read(calendarViewModeProvider);
    final browse = ref.read(viewedDateProvider);
    switch (mode) {
      case CalendarViewMode.day:
        _setBrowse(browse.add(Duration(days: direction)));
      case CalendarViewMode.week:
        _setBrowse(browse.add(Duration(days: 7 * direction)));
      case CalendarViewMode.month:
        // The month arrows page the calendar, not the browsed day: the shared
        // date keeps its day-of-month (clamped) so Todo · By date still points
        // at the day the user chose.
        final lastDay = DateTime(browse.year, browse.month + direction + 1, 0);
        final day = browse.day.clamp(1, lastDay.day);
        _setBrowse(DateTime(lastDay.year, lastDay.month, day));
    }
  }

  void _goToToday() {
    _setBrowse(ref.read(calendarNowProvider)());
  }

  void _setMode(CalendarViewMode mode) {
    if (ref.read(calendarViewModeProvider) == mode) return;
    ref.read(calendarViewModeProvider.notifier).setViewMode(mode);
  }

  /// The three calendar views named in words, so the header does not have to
  /// teach three different icons. Month / week / day are the only options.
  Future<void> _openViewMenu() async {
    final l = AppLocalizations.of(context)!;
    final current = ref.read(calendarViewModeProvider);
    final picked = await showDsSheet<CalendarViewMode>(
      context: context,
      title: l.calendar,
      body: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              (CalendarViewMode.month, l.month),
              (CalendarViewMode.week, l.week),
              (CalendarViewMode.day, l.day),
            ])
              DsSettingRow(
                label: entry.$2,
                selected: entry.$1 == current,
                trailing: entry.$1 == current
                    ? Icon(
                        CupertinoIcons.checkmark,
                        size: 15,
                        color: SpecTokens.ink,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(entry.$1),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _setMode(picked);
  }

  bool _dayHasEntries(
    DateTime day,
    List<CalendaEventAdapter> events,
    List<TaskAllocationCalendarItem> allocations,
  ) {
    if (calAllDayEvents(day: day, events: events).isNotEmpty) {
      return true;
    }
    final blocks = calDayBlocks(
      day: day,
      events: events,
      allocations: [
        for (final item in allocations)
          TaskAllocationCalendarAdapter.fromItem(item),
      ],
    );
    if (blocks.isNotEmpty) return true;
    return widget.deadlines.any((deadline) => calSameDay(deadline.due, day));
  }

  /// A month cell only says "something happens here". Selecting a day with
  /// content therefore opens it, so the entry can actually be read; an empty
  /// day keeps the plain browse-date behaviour.
  void _selectDay(
    DateTime day,
    List<CalendaEventAdapter> events,
    List<TaskAllocationCalendarItem> allocations,
  ) {
    _setBrowse(day);
    if (_dayHasEntries(day, events, allocations)) {
      _setMode(CalendarViewMode.day);
    }
  }

  void _createAt(DateTime day) {
    widget.onCreateAtDay?.call(calDayOf(day));
  }

  TaskAllocationCalendarItem? _allocationById(int id) {
    for (final item in widget.allocations) {
      if (item.allocation.id == id) return item;
    }
    return null;
  }

  Future<void> _reschedule(CalBlockItem item, int minutes) async {
    if (minutes == 0) return;
    final shift = Duration(minutes: minutes);
    final l = AppLocalizations.of(context)!;
    try {
      final event = item.event;
      if (event != null) {
        final handler = widget.onEventChanged;
        if (handler == null) return;
        await handler(
          event.copyWithData(
            start: event.start.add(shift),
            end: event.end.add(shift),
          ),
        );
        return;
      }
      final allocation = item.allocation;
      if (allocation == null) return;
      final handler = widget.onAllocationChanged;
      if (handler == null) return;
      final original = _allocationById(allocation.id);
      if (original == null) return;
      await handler(
        TaskAllocationCalendarItem(
          allocation: original.allocation.copyWith(
            startAt: original.allocation.startAt.add(shift),
            endAt: original.allocation.endAt.add(shift),
          ),
          todo: original.todo,
        ),
      );
    } on Object catch (error) {
      debugPrint('a2 calendar: reschedule failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
    }
  }

  String _yearMonth(AppLocalizations l, DateTime date) {
    return l.yearMonthTitle('${date.year}', '${date.month}');
  }

  int _isoWeek(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final first = DateTime.utc(date.year, 1, 1);
    final dayOfYear = day.difference(first).inDays + 1;
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  (String, String?) _header(
    AppLocalizations l,
    String locale,
    CalendarViewMode mode,
    DateTime browse,
    DateTime now,
    DateTime weekStart,
  ) {
    switch (mode) {
      case CalendarViewMode.month:
        final subtitle =
            '${DateFormat.MMMd(locale).format(browse)} · '
            '${DateFormat.E(locale).format(browse)} · ${browse.year}';
        return (l.calendar, subtitle);
      case CalendarViewMode.week:
        final end = weekStart.add(const Duration(days: 6));
        final title =
            '${DateFormat.MMMd(locale).format(weekStart)} – '
            '${DateFormat.d(locale).format(end)}';
        final subtitle =
            '${_yearMonth(l, weekStart)} · '
            '${l.weekNumberLabel(_isoWeek(weekStart))}';
        return (title, subtitle);
      case CalendarViewMode.day:
        final title =
            '${DateFormat.MMMd(locale).format(browse)} '
            '${DateFormat.E(locale).format(browse)}';
        final subtitle = calSameDay(browse, now)
            ? '${l.today} · ${_yearMonth(l, browse)}'
            : _yearMonth(l, browse);
        return (title, subtitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mode = ref.watch(calendarViewModeProvider);
    final browse = ref.watch(viewedDateProvider);
    final now = ref.watch(calendarNowProvider)();
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? <Calendar>[];
    final names = {
      for (final calendar in calendars) calendar.id: calendar.name,
    };
    final locale = Localizations.localeOf(context).toString();
    final weekStart = calWeekStart(browse);
    final days = [
      for (var index = 0; index < 7; index++)
        weekStart.add(Duration(days: index)),
    ];
    final hidden = ref.watch(calendarHiddenFilterProvider);
    final visibleEvents = hidden.isEmpty
        ? widget.events
        : widget.events.where((e) => !hidden.contains(e.calendarId)).toList();
    final visibleAllocations = hidden.isEmpty
        ? widget.allocations
        : widget.allocations
            .where((a) => !hidden.contains(a.todo.calendarId))
            .toList();

    final todoCalendarMap = <int, int>{};
    for (final a in widget.allocations) {
      todoCalendarMap[a.todo.id] = a.todo.calendarId;
    }
    final allTodos = ref.watch(allTodosProvider).valueOrNull;
    if (allTodos != null) {
      for (final t in allTodos) {
        todoCalendarMap[t.id] = t.calendarId;
      }
    }
    final visibleDeadlines = hidden.isEmpty
        ? widget.deadlines
        : widget.deadlines.where((d) {
            final calId = d.calendarId ?? todoCalendarMap[d.todoId];
            return calId == null || !hidden.contains(calId);
          }).toList();

    final hiddenEventsCount =
        widget.events.where((e) => hidden.contains(e.calendarId)).length;
    final hiddenAllocCount = widget.allocations
        .where((a) => hidden.contains(a.todo.calendarId))
        .length;
    final hiddenDlCount = widget.deadlines.where((d) {
      final calId = d.calendarId ?? todoCalendarMap[d.todoId];
      return calId != null && hidden.contains(calId);
    }).length;
    final hiddenTotalItems =
        hiddenEventsCount + hiddenAllocCount + hiddenDlCount;
    final hiddenNames = [
      for (final id in hidden)
        if (names.containsKey(id)) names[id]!,
    ];

    if (isWorkspaceLayout(context)) {
      return _desktop(
        l,
        locale,
        mode,
        browse,
        now,
        names,
        weekStart,
        days,
        hidden,
        hiddenTotalItems,
        hiddenNames,
        visibleEvents,
        visibleAllocations,
        visibleDeadlines,
      );
    }
    return _phone(
      l,
      locale,
      mode,
      browse,
      now,
      names,
      weekStart,
      days,
      hidden,
      hiddenTotalItems,
      hiddenNames,
      visibleEvents,
      visibleAllocations,
      visibleDeadlines,
    );
  }

  Widget _phone(
    AppLocalizations l,
    String locale,
    CalendarViewMode mode,
    DateTime browse,
    DateTime now,
    Map<int, String> names,
    DateTime weekStart,
    List<DateTime> days,
    Set<int> hidden,
    int hiddenItemsCount,
    List<String> hiddenNames,
    List<CalendaEventAdapter> visibleEvents,
    List<TaskAllocationCalendarItem> visibleAllocations,
    List<CalendarDeadline> visibleDeadlines,
  ) {
    final (title, subtitle) = _header(l, locale, mode, browse, now, weekStart);
    final actions = <Widget>[
      A2IconAction(
        key: const ValueKey('calendar-filter-button'),
        icon: CupertinoIcons.line_horizontal_3_decrease,
        tooltip: l.showCalendars,
        onPressed: () => CalendarFilterSheet.show(context),
      ),
      A2IconAction(
        key: const ValueKey('calendar-view-menu'),
        icon: switch (mode) {
          CalendarViewMode.month => CupertinoIcons.square_grid_2x2,
          CalendarViewMode.week => CupertinoIcons.calendar,
          CalendarViewMode.day => CupertinoIcons.rectangle,
        },
        tooltip: l.calendar,
        onPressed: _openViewMenu,
      ),
      if (mode != CalendarViewMode.month)
        A2IconAction(
          icon: CupertinoIcons.add,
          tooltip: l.newEvent,
          onPressed: () => _createAt(browse),
        ),
    ];
    final content = switch (mode) {
      CalendarViewMode.month => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          A2MonthStrip(
            label: _yearMonth(l, browse),
            onPrevious: () => _shift(-1),
            onNext: () => _shift(1),
          ),
          Expanded(
            child: A2PhoneMonthGrid(
              anchor: browse,
              selected: browse,
              today: calDayOf(now),
              events: visibleEvents,
              allocations: visibleAllocations,
              deadlines: visibleDeadlines,
              onSelectDay: (day) => _selectDay(day, visibleEvents, visibleAllocations),
              onEvent: widget.onEventTapped,
              onAllocation: widget.onAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
            ),
          ),
        ],
      ),
      CalendarViewMode.week => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          A2MonthStrip(
            label: l.weekNumberLabel(_isoWeek(weekStart)),
            onPrevious: () => _shift(-1),
            onNext: () => _shift(1),
          ),
          Expanded(
            child: _timeGrid(
              days: days,
              selected: browse,
              now: now,
              names: names,
              events: visibleEvents,
              allocations: visibleAllocations,
              deadlines: visibleDeadlines,
              dayMode: false,
              isDesktop: false,
            ),
          ),
        ],
      ),
      CalendarViewMode.day => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          A2MonthStrip(
            label: calSameDay(browse, now) ? l.today : _yearMonth(l, browse),
            onPrevious: () => _shift(-1),
            onNext: () => _shift(1),
          ),
          Expanded(
            child: _timeGrid(
              days: [calDayOf(browse)],
              selected: browse,
              now: now,
              names: names,
              events: visibleEvents,
              allocations: visibleAllocations,
              deadlines: visibleDeadlines,
              dayMode: true,
              isDesktop: false,
            ),
          ),
        ],
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        A2DayHead(
          title: title,
          subtitle: subtitle,
          clock: DateFormatters.formatTime(now),
          actions: actions,
        ),
        if (hidden.isNotEmpty)
          _CalHiddenBanner(
            hiddenCount: hidden.length,
            hiddenItemsCount: hiddenItemsCount,
            hiddenNames: hiddenNames,
            onRestore: () =>
                ref.read(calendarHiddenFilterProvider.notifier).state = const {},
            onShowCalendars: () => CalendarFilterSheet.show(context),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              if (mode == CalendarViewMode.month)
                A2Fab(
                  tooltip: l.newEvent,
                  onPressed: () => widget.onCreateAtDay?.call(browse),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktop(
    AppLocalizations l,
    String locale,
    CalendarViewMode mode,
    DateTime browse,
    DateTime now,
    Map<int, String> names,
    DateTime weekStart,
    List<DateTime> days,
    Set<int> hidden,
    int hiddenItemsCount,
    List<String> hiddenNames,
    List<CalendaEventAdapter> visibleEvents,
    List<TaskAllocationCalendarItem> visibleAllocations,
    List<CalendarDeadline> visibleDeadlines,
  ) {
    final body = switch (mode) {
      CalendarViewMode.month => A2DesktopMonthGrid(
        anchor: browse,
        selected: browse,
        today: calDayOf(now),
        now: now,
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        calendarNames: names,
        onSelectDay: _setBrowse,
        onSlot: widget.onTimeSlotTapped,
        onEvent: widget.onEventTapped,
        onAllocation: widget.onAllocationTapped,
        onDeadline: widget.onDeadlineTapped,
      ),
      CalendarViewMode.week => _timeGrid(
        days: days,
        selected: browse,
        now: now,
        names: names,
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        dayMode: false,
        isDesktop: true,
      ),
      CalendarViewMode.day => _timeGrid(
        days: [calDayOf(browse)],
        selected: browse,
        now: now,
        names: names,
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        dayMode: true,
        isDesktop: true,
      ),
    };
    return Container(
      color: SpecTokens.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopHead(l, locale, mode, browse, weekStart, hidden),
          if (hidden.isNotEmpty)
            _CalHiddenBanner(
              hiddenCount: hidden.length,
              hiddenItemsCount: hiddenItemsCount,
              hiddenNames: hiddenNames,
              onRestore: () =>
                  ref.read(calendarHiddenFilterProvider.notifier).state = const {},
              onShowCalendars: () => CalendarFilterSheet.show(context),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final minWidth = switch (mode) {
                    CalendarViewMode.week => 820.0,
                    CalendarViewMode.month => 760.0,
                    CalendarViewMode.day => 580.0,
                  };
                  if (constraints.maxWidth < minWidth) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: minWidth,
                        child: body,
                      ),
                    );
                  }
                  return body;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopHead(
    AppLocalizations l,
    String locale,
    CalendarViewMode mode,
    DateTime browse,
    DateTime weekStart,
    Set<int> hidden,
  ) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final sub = switch (mode) {
      CalendarViewMode.month => _yearMonth(l, browse),
      CalendarViewMode.week => weekStart.month == weekEnd.month
          ? '${DateFormat.MMMd(locale).format(weekStart)} – ${DateFormat.d(locale).format(weekEnd)}'
          : '${DateFormat.MMMd(locale).format(weekStart)} – ${DateFormat.MMMd(locale).format(weekEnd)}',
      CalendarViewMode.day =>
        '${calWeekdayShort(locale, browse)} · ${DateFormat.MMMd(locale).format(browse)}',
    };

    final left = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.calendar,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.22,
            color: SpecTokens.ink,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          sub,
          style: const TextStyle(
            fontSize: 11.5,
            color: SpecTokens.muted,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
      ],
    );

    final tools = <Widget>[
      _SpecViewSwitch(
        mode: mode,
        onSelected: _setMode,
      ),
      _SpecToolButton(
        icon: CupertinoIcons.chevron_left,
        tooltip: l.previousPeriod,
        onTap: () => _shift(-1),
      ),
      _SpecToolButton(
        label: l.today,
        onTap: _goToToday,
      ),
      _SpecToolButton(
        icon: CupertinoIcons.chevron_right,
        tooltip: l.nextPeriod,
        onTap: () => _shift(1),
      ),
      _SpecToolButton(
        key: const ValueKey('calendar-filter-button'),
        icon: CupertinoIcons.line_horizontal_3_decrease,
        label: l.showCalendars,
        active: hidden.isNotEmpty,
        onTap: () => CalendarFilterSheet.show(context),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 13),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1.0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1000) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                left,
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < tools.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      tools[i],
                    ],
                  ],
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < tools.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      tools[i],
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _timeGrid({
    required List<DateTime> days,
    required DateTime selected,
    required DateTime now,
    required Map<int, String> names,
    required List<CalendaEventAdapter> events,
    required List<TaskAllocationCalendarItem> allocations,
    required List<CalendarDeadline> deadlines,
    required bool dayMode,
    bool isDesktop = true,
  }) {
    return A2TimeGridView(
      days: days,
      selected: selected,
      now: now,
      events: events,
      allocations: allocations,
      deadlines: deadlines,
      calendarNames: names,
      dayMode: dayMode,
      isDesktop: isDesktop,
      onSelectDay: _setBrowse,
      onEvent: widget.onEventTapped,
      onAllocation: widget.onAllocationTapped,
      onDeadline: widget.onDeadlineTapped,
      onSlot: widget.onTimeSlotTapped,
      onReschedule: _reschedule,
    );
  }
}

class _SpecToolButton extends StatefulWidget {
  const _SpecToolButton({
    super.key,
    this.icon,
    this.label,
    this.tooltip,
    this.active = false,
    this.onTap,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_SpecToolButton> createState() => _SpecToolButtonState();
}

class _SpecToolButtonState extends State<_SpecToolButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? SpecTokens.wash
        : (_hovered ? SpecTokens.wash : SpecTokens.paper);

    Widget content = Container(
      height: 29,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: SpecTokens.hair2, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.icon != null)
            Icon(
              widget.icon,
              size: 12,
              color: SpecTokens.muted,
            ),
          if (widget.icon != null && widget.label != null)
            const SizedBox(width: 5),
          if (widget.label != null)
            Text(
              widget.label!,
              style: const TextStyle(
                fontSize: 11,
                color: SpecTokens.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
        ],
      ),
    );

    if (widget.tooltip != null) {
      content = Tooltip(
        message: widget.tooltip!,
        child: content,
      );
    }

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
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

class _SpecViewSwitch extends StatelessWidget {
  const _SpecViewSwitch({
    required this.mode,
    required this.onSelected,
  });

  final CalendarViewMode mode;
  final ValueChanged<CalendarViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final options = <(CalendarViewMode, String)>[
      (CalendarViewMode.month, l.month),
      (CalendarViewMode.week, l.week),
      (CalendarViewMode.day, l.daySegmentLabel),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SpecTokens.wash,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _SpecSwitchButton(
              label: options[i].$2,
              selected: options[i].$1 == mode,
              onTap: () => onSelected(options[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpecSwitchButton extends StatefulWidget {
  const _SpecSwitchButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SpecSwitchButton> createState() => _SpecSwitchButtonState();
}

class _SpecSwitchButtonState extends State<_SpecSwitchButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 27,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? SpecTokens.paper
                : (_hovered ? Colors.white.withValues(alpha: 0.5) : Colors.transparent),
            borderRadius: BorderRadius.circular(5),
            boxShadow: widget.selected
                ? const [
                    BoxShadow(
                      color: Color.fromRGBO(25, 25, 24, 0.06),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              color: widget.selected ? SpecTokens.ink : SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalHiddenBanner extends StatelessWidget {
  const _CalHiddenBanner({
    required this.hiddenCount,
    required this.hiddenItemsCount,
    required this.hiddenNames,
    required this.onRestore,
    required this.onShowCalendars,
  });

  final int hiddenCount;
  final int hiddenItemsCount;
  final List<String> hiddenNames;
  final VoidCallback onRestore;
  final VoidCallback onShowCalendars;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBF8),
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1.0)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.eye_slash, size: 12, color: SpecTokens.muted),
          const SizedBox(width: 6),
          Text(
            l.hiddenCalendarsSummary(hiddenCount),
            style: const TextStyle(
              fontSize: 9.5,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRestore,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  l.restoreAllCalendars,
                  style: const TextStyle(
                    fontSize: 9.0,
                    color: SpecTokens.ink2,
                    decoration: TextDecoration.underline,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onShowCalendars,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  l.showCalendars,
                  style: const TextStyle(
                    fontSize: 9.0,
                    color: SpecTokens.ink2,
                    decoration: TextDecoration.underline,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
