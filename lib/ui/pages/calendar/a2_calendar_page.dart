import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/data/local/database/app_database.dart' show Calendar;
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_filter_sheet.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

bool _initialLoading(AsyncValue<Object?>? state) =>
    state != null && state.isLoading && !state.hasValue;

const _keyHiddenCalendars = 'calendar_hidden_filters';

class A2CalendarPage extends ConsumerStatefulWidget {
  const A2CalendarPage({
    super.key,
    required this.events,
    required this.allocations,
    required this.deadlines,
    this.eventsAsync,
    this.allocationsAsync,
    this.onRetry,
    this.onEventTapped,
    this.onAllocationTapped,
    this.onDeadlineTapped,
    this.onTimeSlotTapped,
    this.onCreateAtDay,
    this.onEventChanged,
    this.onAllocationChanged,
    this.onSearch,
  });

  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final List<CalendarDeadline> deadlines;

  /// The queries behind [events] and [allocations]. When supplied, the page
  /// keeps a loading frame and an error frame instead of drawing the empty
  /// grid that a value-less read would produce.
  final AsyncValue<List<CalendaEventAdapter>>? eventsAsync;
  final AsyncValue<List<TaskAllocationCalendarItem>>? allocationsAsync;
  final VoidCallback? onRetry;
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

  /// The phone header's search glyph. HomePage wires it to the command/search
  /// surface; the calendar itself has nothing to search.
  final VoidCallback? onSearch;

  @override
  ConsumerState<A2CalendarPage> createState() => _A2CalendarPageState();
}

class _A2CalendarPageState extends ConsumerState<A2CalendarPage> {
  bool _hiddenRestored = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<Set<int>>(calendarHiddenFilterProvider, (_, next) {
      _saveHidden(next);
    });
    // Restore the hidden calendar set on cold start. The provider keeps its
    // type and API; only the page persists its value.
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_keyHiddenCalendars);
      if (!mounted) return;
      if (raw != null) {
        final restored = <int>{
          for (final value in raw)
            if (int.tryParse(value) != null) int.parse(value),
        };
        // Do not clobber a set the user already touched during startup.
        if (restored.isNotEmpty &&
            ref.read(calendarHiddenFilterProvider).isEmpty) {
          ref.read(calendarHiddenFilterProvider.notifier).state = restored;
        }
      }
      _hiddenRestored = true;
    });
  }

  Future<void> _saveHidden(Set<int> hidden) async {
    if (!_hiddenRestored) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyHiddenCalendars,
      [for (final id in hidden) '$id'],
    );
  }

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

  void _openDay(DateTime value) {
    _setBrowse(value);
    _setMode(CalendarViewMode.day);
  }

  /// The three calendar views named in words, so the header does not have to
  /// teach three different icons. Month / week / day are the only options.
  bool _dayHasEntries(
    DateTime day,
    List<CalendaEventAdapter> events,
    List<TaskAllocationCalendarItem> allocations, {
    List<CalendarDeadline>? deadlines,
  }) {
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
    return (deadlines ?? widget.deadlines).any(
      (deadline) => calSameDay(deadline.due, day),
    );
  }

  /// Spec mobileCalendar('month'): every month cell enters cal-day, empty or
  /// not. The cell is a day, not a disclosure for "does this day have rows".
  void _selectDay(DateTime day) {
    _setBrowse(day);
    _setMode(CalendarViewMode.day);
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

  /// The drag and resize gestures both write a shifted span. A drop that would
  /// leave the original day, or collapse the span, must not reach the database:
  /// it is a failed gesture, not a silent edit behind the user's back.
  bool _spanStaysValid(DateTime start, DateTime end) =>
      end.isAfter(start) && calSameDay(start.toLocal(), end.toLocal());

  void _rejectOutOfBounds() {
    if (!mounted) return;
    showSpecToast(context, AppLocalizations.of(context)!.actionFailedRetry);
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
        final start = event.start.add(shift);
        final end = event.end.add(shift);
        if (!_spanStaysValid(start, end)) {
          _rejectOutOfBounds();
          return;
        }
        await handler(event.copyWithData(start: start, end: end));
        return;
      }
      final allocation = item.allocation;
      if (allocation == null) return;
      final handler = widget.onAllocationChanged;
      if (handler == null) return;
      final original = _allocationById(allocation.id);
      if (original == null) return;
      final start = original.allocation.startAt.add(shift);
      final end = original.allocation.endAt.add(shift);
      if (!_spanStaysValid(start, end)) {
        _rejectOutOfBounds();
        return;
      }
      await handler(
        TaskAllocationCalendarItem(
          allocation: original.allocation.copyWith(startAt: start, endAt: end),
          todo: original.todo,
        ),
      );
    } on Object catch (error) {
      debugPrint('a2 calendar: reschedule failed: $error');
      if (!mounted) return;
      showSpecToast(context, l.actionFailedRetry);
    }
  }

  Future<void> _resize(CalBlockItem item, int deltaMinutes) async {
    if (deltaMinutes == 0) return;
    final shift = Duration(minutes: deltaMinutes);
    final l = AppLocalizations.of(context)!;
    try {
      final event = item.event;
      if (event != null) {
        final handler = widget.onEventChanged;
        if (handler == null) return;
        final newEnd = event.end.add(shift);
        if (!_spanStaysValid(event.start, newEnd)) {
          _rejectOutOfBounds();
          return;
        }
        await handler(event.copyWithData(end: newEnd));
        return;
      }
      final allocation = item.allocation;
      if (allocation == null) return;
      final handler = widget.onAllocationChanged;
      if (handler == null) return;
      final original = _allocationById(allocation.id);
      if (original == null) return;
      final newEnd = original.allocation.endAt.add(shift);
      if (!_spanStaysValid(original.allocation.startAt, newEnd)) {
        _rejectOutOfBounds();
        return;
      }
      await handler(
        TaskAllocationCalendarItem(
          allocation: original.allocation.copyWith(endAt: newEnd),
          todo: original.todo,
        ),
      );
    } on Object catch (error) {
      debugPrint('a2 calendar: resize failed: $error');
      if (!mounted) return;
      showSpecToast(context, l.actionFailedRetry);
    }
  }

  String _yearMonth(AppLocalizations l, DateTime date) {
    return l.yearMonthTitle('${date.year}', '${date.month}');
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

    final failed =
        (widget.eventsAsync?.hasError ?? false) ||
        (widget.allocationsAsync?.hasError ?? false);
    final failedWithoutValue =
        ((widget.eventsAsync?.hasError ?? false) &&
            !(widget.eventsAsync?.hasValue ?? false)) ||
        ((widget.allocationsAsync?.hasError ?? false) &&
            !(widget.allocationsAsync?.hasValue ?? false));
    // A failed read that still carries the last data is a warning, not a
    // failure page: the grid keeps drawing, the banner says it is stale. A
    // read that never produced a value keeps the original error page.
    final stale = failed && !failedWithoutValue;
    final blockingFailure = failedWithoutValue;
    final loading =
        !failed &&
        (_initialLoading(widget.eventsAsync) ||
            _initialLoading(widget.allocationsAsync));
    final status = blockingFailure
        ? _CalendarLoadError(onRetry: widget.onRetry)
        : loading
        ? const _CalendarLoading()
        : null;
    final weekEmpty = days.every(
      (day) => !_dayHasEntries(
        day,
        visibleEvents,
        visibleAllocations,
        deadlines: visibleDeadlines,
      ),
    );
    final dayEmpty = !_dayHasEntries(
      calDayOf(browse),
      visibleEvents,
      visibleAllocations,
      deadlines: visibleDeadlines,
    );

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
        status,
        stale,
        weekEmpty,
        dayEmpty,
      );
    }
    return _phone(
      l,
      mode,
      browse,
      now,
      names,
      days,
      hidden,
      hiddenTotalItems,
      hiddenNames,
      visibleEvents,
      visibleAllocations,
      visibleDeadlines,
      status,
      stale,
      weekEmpty,
    );
  }

  Widget _phone(
    AppLocalizations l,
    CalendarViewMode mode,
    DateTime browse,
    DateTime now,
    Map<int, String> names,
    List<DateTime> days,
    Set<int> hidden,
    int hiddenItemsCount,
    List<String> hiddenNames,
    List<CalendaEventAdapter> visibleEvents,
    List<TaskAllocationCalendarItem> visibleAllocations,
    List<CalendarDeadline> visibleDeadlines,
    Widget? status,
    bool stale,
    bool weekEmpty,
  ) {
    final content = switch (mode) {
      CalendarViewMode.month => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          A2MonthStrip(
            label: _yearMonth(l, browse),
          ),
          Expanded(
            child: A2PhoneMonthGrid(
              anchor: browse,
              selected: browse,
              today: calDayOf(now),
              events: visibleEvents,
              allocations: visibleAllocations,
              deadlines: visibleDeadlines,
              onSelectDay: (day) => _selectDay(day),
              onEvent: widget.onEventTapped,
              onAllocation: widget.onAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
            ),
          ),
        ],
      ),
      CalendarViewMode.week => A2PhoneWeekList(
        key: const ValueKey('phone-week-list'),
        days: days,
        today: calDayOf(now),
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        isEmpty: weekEmpty,
        onEvent: widget.onEventTapped,
        onAllocation: widget.onAllocationTapped,
        onDeadline: widget.onDeadlineTapped,
        onReschedule: _reschedule,
        onCreateAtDay: widget.onCreateAtDay,
        onSlot: widget.onTimeSlotTapped,
      ),
      CalendarViewMode.day => A2PhoneDayList(
        key: const ValueKey('phone-day-list-view'),
        day: calDayOf(browse),
        now: now,
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        calendarNames: names,
        onEvent: widget.onEventTapped,
        onAllocation: widget.onAllocationTapped,
        onDeadline: widget.onDeadlineTapped,
        onSlot: widget.onTimeSlotTapped,
        onSelectDay: _setBrowse,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mobileTopBar(context, l),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: KeyedSubtree(
              // The old 1×1 disclosure is gone; this key now names the
              // visible segmented control it opened, so focus/keyboard
              // helpers keep one stable handle.
              key: const ValueKey('calendar-view-menu'),
              child: _SpecViewSwitch(
                key: const ValueKey('cal-view-switch'),
                mode: mode,
                onSelected: _setMode,
              ),
            ),
          ),
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
        if (stale) _StaleDataBanner(onRetry: widget.onRetry),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: status ?? content),
              // One create entry for all three views: month/day pass the
              // browsed day, week passes the day group's day through
              // onCreateAtDay. The slot tap below stays a separate gesture.
              A2Fab(
                tooltip: l.newEvent,
                onPressed: () => _createAt(browse),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mobileTopBar(BuildContext context, AppLocalizations l) {
    return Container(
      key: const ValueKey('m-top'),
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.calendar,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontVariations: [FontVariation('wght', 650)],
                letterSpacing: 0.15,
                color: SpecTokens.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spec mobileCalendar actions: search, "today", period arrows,
              // then the calendar filter funnel.
              _mIcon(
                key: const ValueKey('cal-search'),
                icon: CupertinoIcons.search,
                tooltip: l.search,
                onTap: () => widget.onSearch?.call(),
              ),
              const SizedBox(width: 5),
              _mToday(
                key: const ValueKey('cal-today'),
                label: l.today,
                onTap: _goToToday,
              ),
              const SizedBox(width: 5),
              _mIcon(
                key: const ValueKey('cal-prev'),
                icon: CupertinoIcons.chevron_left,
                tooltip: l.previousPeriod,
                onTap: () => _shift(-1),
              ),
              const SizedBox(width: 5),
              _mIcon(
                key: const ValueKey('cal-next'),
                icon: CupertinoIcons.chevron_right,
                tooltip: l.nextPeriod,
                onTap: () => _shift(1),
              ),
              const SizedBox(width: 5),
              _mIcon(
                key: const ValueKey('calendar-filter-button'),
                icon: Icons.filter_alt_outlined,
                size: 14,
                tooltip: l.showCalendars,
                onTap: () => CalendarFilterSheet.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Spec `.m-today`: a 24px pill among the round header icons.
  Widget _mToday({
    Key? key,
    required String label,
    required VoidCallback onTap,
  }) {
    return FocusableTap(
      key: key,
      onTap: onTap,
      semanticsLabel: label,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: SpecTokens.hair2),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: SpecTokens.ink2,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
      ),
    );
  }

  Widget _mIcon({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 15,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: FocusableTap(
          key: key,
          onTap: onTap,
          semanticsLabel: tooltip,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                icon,
                size: size,
                color: SpecTokens.muted,
              ),
            ),
          ),
        ),
      ),
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
    Widget? status,
    bool stale,
    bool weekEmpty,
    bool dayEmpty,
  ) {
    final body = switch (mode) {
      CalendarViewMode.month => A2DesktopMonthGrid(
        key: const ValueKey('desktop-month-grid'),
        anchor: browse,
        selected: browse,
        today: calDayOf(now),
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        calendarNames: names,
        onSelectDay: _openDay,
        onEvent: widget.onEventTapped,
        onAllocation: widget.onAllocationTapped,
        onDeadline: widget.onDeadlineTapped,
      ),
      CalendarViewMode.week => _timeGrid(
        key: const ValueKey('desktop-week-grid'),
        days: days,
        selected: browse,
        now: now,
        names: names,
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        dayMode: false,
        isDesktop: true,
        emptyTitle: weekEmpty ? l.calendarWeekEmpty : null,
        emptyHint: weekEmpty ? l.calendarWeekEmptyHint : null,
      ),
      CalendarViewMode.day => _timeGrid(
        key: const ValueKey('desktop-day-grid'),
        days: [calDayOf(browse)],
        selected: browse,
        now: now,
        names: names,
        events: visibleEvents,
        allocations: visibleAllocations,
        deadlines: visibleDeadlines,
        dayMode: true,
        isDesktop: true,
        emptyTitle: dayEmpty ? l.planDayEmpty : null,
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
          if (stale) _StaleDataBanner(onRetry: widget.onRetry),
          Expanded(
            child:
                status ??
                Padding(
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
      CalendarViewMode.week => calDateRangeLabel(l, locale, weekStart, weekEnd),
      CalendarViewMode.day =>
        '${calWeekdayLong(locale, browse)} · '
            '${calMonthDayLabel(l, locale, browse)}',
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
            fontVariations: [FontVariation('wght', 650)],
            letterSpacing: 0.1,
            height: 1.22,
            color: SpecTokens.ink,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            sub,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
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
        icon: Icons.filter_alt_outlined,
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
                Expanded(child: left),
                const SizedBox(width: 12),
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
    Key? key,
    required List<DateTime> days,
    required DateTime selected,
    required DateTime now,
    required Map<int, String> names,
    required List<CalendaEventAdapter> events,
    required List<TaskAllocationCalendarItem> allocations,
    required List<CalendarDeadline> deadlines,
    required bool dayMode,
    bool isDesktop = true,
    String? emptyTitle,
    String? emptyHint,
  }) {
    return A2TimeGridView(
      key: key,
      days: days,
      selected: selected,
      now: now,
      events: events,
      allocations: allocations,
      deadlines: deadlines,
      calendarNames: names,
      dayMode: dayMode,
      isDesktop: isDesktop,
      emptyTitle: emptyTitle,
      emptyHint: emptyHint,
      onSelectDay: _openDay,
      onEvent: widget.onEventTapped,
      onAllocation: widget.onAllocationTapped,
      onDeadline: widget.onDeadlineTapped,
      onSlot: widget.onTimeSlotTapped,
      onReschedule: _reschedule,
      onResize: _resize,
    );
  }
}

class _CalendarLoading extends StatelessWidget {
  const _CalendarLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('calendar-loading'),
      color: SpecTokens.paper,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final width in const [0.62, 0.48, 0.7, 0.55, 0.66, 0.42])
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: width,
              child: Container(
                height: 18,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: SpecTokens.wash,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarLoadError extends StatelessWidget {
  const _CalendarLoadError({this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      key: const ValueKey('calendar-load-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.error),
          TextButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      ),
    );
  }
}

/// Spec `m-banner.is-red`: a read failed but last-known data is still on
/// screen. It does not replace the grid, and it keeps retry reachable.
class _StaleDataBanner extends StatelessWidget {
  const _StaleDataBanner({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      key: const ValueKey('calendar-stale-banner'),
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0ED),
        border: const Border(
          left: BorderSide(color: Color(0xFFB03B2F), width: 3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.staleCalendarTitle,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: Color(0xFF7C231B),
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                Text(
                  l.staleCalendarBody,
                  style: const TextStyle(
                    fontSize: 9.5,
                    height: 1.5,
                    color: Color(0xFF7C231B),
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            FocusableTap(
              onTap: onRetry,
              semanticsLabel: l.retry,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  l.retry,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C231B),
                    decoration: TextDecoration.underline,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
      child: FocusableTap(
        onTap: widget.onTap,
        semanticsLabel: widget.tooltip ?? widget.label ?? '',
        borderRadius: BorderRadius.circular(6),
        child: content,
      ),
    );
  }
}

class _SpecViewSwitch extends StatelessWidget {
  const _SpecViewSwitch({
    super.key,
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
            Tooltip(
              message: options[i].$2,
              child: _SpecSwitchButton(
                label: options[i].$2,
                selected: options[i].$1 == mode,
                onTap: () => onSelected(options[i].$1),
              ),
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
      child: FocusableTap(
        onTap: widget.onTap,
        semanticsLabel: widget.label,
        borderRadius: BorderRadius.circular(5),
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
    final summaryText = (l.localeName.startsWith('zh') && hiddenNames.isNotEmpty)
        ? (hiddenNames.length == 1
            ? l.calendarHiddenSingleSummary(hiddenNames.first, hiddenItemsCount)
            : l.calendarHiddenMultipleSummary(hiddenNames.length, hiddenItemsCount))
        : l.hiddenCalendarsSummary(hiddenCount);
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
            summaryText,
            style: const TextStyle(
              fontSize: 9.5,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: FocusableTap(
              onTap: onRestore,
              semanticsLabel: l.restoreAllCalendars,
              borderRadius: BorderRadius.circular(4),
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
            child: FocusableTap(
              onTap: onShowCalendars,
              semanticsLabel: l.showCalendars,
              borderRadius: BorderRadius.circular(4),
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
