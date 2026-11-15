import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart' show Calendar;
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
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
    if (isWorkspaceLayout(context)) {
      return _desktop(l, locale, mode, browse, now, names, weekStart, days);
    }
    return _phone(l, locale, mode, browse, now, names, weekStart, days);
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
  ) {
    final (title, subtitle) = _header(l, locale, mode, browse, now, weekStart);
    // The design's head switches views with an icon rather than a segmented
    // control. Month is entered by tapping a day, but week and day had no way
    // back to each other once the month grid was left: each mode names the
    // modes it can reach, and month keeps settings because the other two use
    // their third slot for the way back to it.
    final actions = <Widget>[
      ...switch (mode) {
        CalendarViewMode.month => [
          A2IconAction(
            icon: CupertinoIcons.calendar,
            tooltip: l.week,
            onPressed: () => _setMode(CalendarViewMode.week),
          ),
        ],
        CalendarViewMode.week => [
          A2IconAction(
            icon: CupertinoIcons.rectangle,
            tooltip: l.day,
            onPressed: () => _setMode(CalendarViewMode.day),
          ),
          A2IconAction(
            icon: CupertinoIcons.square_grid_2x2,
            tooltip: l.month,
            onPressed: () => _setMode(CalendarViewMode.month),
          ),
        ],
        CalendarViewMode.day => [
          A2IconAction(
            icon: CupertinoIcons.calendar,
            tooltip: l.week,
            onPressed: () => _setMode(CalendarViewMode.week),
          ),
          A2IconAction(
            icon: CupertinoIcons.square_grid_2x2,
            tooltip: l.month,
            onPressed: () => _setMode(CalendarViewMode.month),
          ),
        ],
      },
      A2IconAction(
        icon: CupertinoIcons.scope,
        tooltip: l.calendarTodayHint,
        onPressed: _goToToday,
      ),
      if (mode == CalendarViewMode.month)
        A2IconAction(
          icon: CupertinoIcons.settings,
          tooltip: l.settings,
          onPressed: () => context.push('/settings'),
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
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              onSelectDay: _setBrowse,
            ),
          ),
        ],
      ),
      CalendarViewMode.week => _timeGrid(
        days: days,
        selected: browse,
        now: now,
        names: names,
        dayMode: false,
      ),
      CalendarViewMode.day => _timeGrid(
        days: [calDayOf(browse)],
        selected: browse,
        now: now,
        names: names,
        dayMode: true,
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
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              if (mode == CalendarViewMode.month)
                A2Fab(
                  tooltip: l.create,
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
  ) {
    final ds = context.ds;
    final body = switch (mode) {
      CalendarViewMode.month => A2DesktopMonthGrid(
        anchor: browse,
        selected: browse,
        today: calDayOf(now),
        now: now,
        events: widget.events,
        allocations: widget.allocations,
        deadlines: widget.deadlines,
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
        dayMode: false,
      ),
      CalendarViewMode.day => _timeGrid(
        days: [calDayOf(browse)],
        selected: browse,
        now: now,
        names: names,
        dayMode: true,
      ),
    };
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: SizedBox.expand(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: ds.surface,
                border: Border.all(color: ds.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _desktopHead(l, locale, mode, browse, weekStart),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopHead(
    AppLocalizations l,
    String locale,
    CalendarViewMode mode,
    DateTime browse,
    DateTime weekStart,
  ) {
    final ds = context.ds;
    final title = switch (mode) {
      CalendarViewMode.month => _yearMonth(l, browse),
      CalendarViewMode.week =>
        '${DateFormat.MMMd(locale).format(weekStart)} – '
            '${DateFormat.d(locale).format(weekStart.add(const Duration(days: 6)))}',
      CalendarViewMode.day =>
        '${DateFormat.MMMd(locale).format(browse)} '
            '${DateFormat.E(locale).format(browse)}',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _pageText(17, FontWeight.w600, ds.ink, tabular: true),
          ),
          const SizedBox(width: 12),
          _A2TodayButton(label: l.today, onPressed: _goToToday),
          if (mode != CalendarViewMode.month) ...[
            const SizedBox(width: 6),
            _A2HeadIcon(
              icon: CupertinoIcons.chevron_left,
              tooltip: MaterialLocalizations.of(context).previousPageTooltip,
              onPressed: () => _shift(-1),
            ),
            _A2HeadIcon(
              icon: CupertinoIcons.chevron_right,
              tooltip: MaterialLocalizations.of(context).nextPageTooltip,
              onPressed: () => _shift(1),
            ),
          ],
          const Spacer(),
          _A2ModeSegmented(mode: mode, onSelected: _setMode),
        ],
      ),
    );
  }

  Widget _timeGrid({
    required List<DateTime> days,
    required DateTime selected,
    required DateTime now,
    required Map<int, String> names,
    required bool dayMode,
  }) {
    return A2TimeGridView(
      days: days,
      selected: selected,
      now: now,
      events: widget.events,
      allocations: widget.allocations,
      deadlines: widget.deadlines,
      calendarNames: names,
      dayMode: dayMode,
      onSelectDay: _setBrowse,
      onEvent: widget.onEventTapped,
      onAllocation: widget.onAllocationTapped,
      onDeadline: widget.onDeadlineTapped,
      onSlot: widget.onTimeSlotTapped,
      onReschedule: _reschedule,
    );
  }
}

TextStyle _pageText(
  double size,
  FontWeight weight,
  Color color, {
  bool tabular = false,
}) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: tabular ? AppTypography.tabular : null,
  );
  if (AppTypography.fallback.isEmpty) return style;
  return style.copyWith(fontFamilyFallback: AppTypography.fallback);
}

class _A2TodayButton extends StatelessWidget {
  const _A2TodayButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ds.surface,
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: _pageText(12, FontWeight.w500, ds.ink2),
          ),
        ),
      ),
    );
  }
}

class _A2HeadIcon extends StatelessWidget {
  const _A2HeadIcon({
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
            borderRadius: BorderRadius.circular(6),
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(child: Icon(icon, size: 14, color: ds.ink3)),
            ),
          ),
        ),
      ),
    );
  }
}

class _A2ModeSegmented extends StatelessWidget {
  const _A2ModeSegmented({required this.mode, required this.onSelected});

  final CalendarViewMode mode;
  final ValueChanged<CalendarViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final options = <(CalendarViewMode, String)>[
      (CalendarViewMode.month, l.month),
      (CalendarViewMode.week, l.week),
      (CalendarViewMode.day, l.daySegmentLabel),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ds.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(option.$1),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: option.$1 == mode
                      ? BoxDecoration(
                          color: ds.surface,
                          border: Border.all(color: ds.line),
                          borderRadius: BorderRadius.circular(5),
                        )
                      : null,
                  child: Text(
                    option.$2,
                    maxLines: 1,
                    style: _pageText(
                      12,
                      option.$1 == mode ? FontWeight.w600 : FontWeight.w500,
                      option.$1 == mode ? ds.ink : ds.ink2,
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
