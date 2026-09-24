import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/ui/widgets/calendar/kalender_calendar_event.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

class CalendarSection extends ConsumerStatefulWidget {
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;
  final void Function(CalendaEventAdapter event)? onEventChanged;
  final void Function(DateTime anchor)? onAnchorChanged;

  const CalendarSection({
    super.key,
    required this.events,
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onEventChanged,
    this.onAnchorChanged,
  });

  @override
  ConsumerState<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<CalendarSection> {
  late final CalendarController _calendarController;
  late final DefaultEventsController _eventsController;
  late final CalendarInteraction _interaction;
  late final TileComponents _tileComponents;
  DateTime _anchorDate = DateTime.now();
  String _eventsSignature = '';
  CalendarViewMode? _configMode;
  ViewConfiguration? _viewConfiguration;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);
    _calendarController = CalendarController();
    _eventsController = DefaultEventsController();
    // Creation goes through tap → onTimeSlotTapped → route push, so kalender's
    // drag-to-create gesture must stay off.
    _interaction = CalendarInteraction(allowEventCreation: false);
    _tileComponents = TileComponents(tileBuilder: _buildTile);
    _calendarController.visibleDateTimeRange.addListener(_onVisibleRange);
    _syncEvents();
  }

  @override
  void didUpdateWidget(covariant CalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncEvents();
  }

  @override
  void dispose() {
    _calendarController.visibleDateTimeRange.removeListener(_onVisibleRange);
    _calendarController.dispose();
    _eventsController.dispose();
    super.dispose();
  }

  CalendarViewMode get _viewMode => ref.watch(calendarViewModeProvider);

  bool get _isViewingToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_viewMode) {
      case CalendarViewMode.day:
        return _anchorDate == today;
      case CalendarViewMode.week:
        final weekday = today.weekday;
        final weekStart = today.subtract(Duration(days: weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return !_anchorDate.isBefore(weekStart) && !_anchorDate.isAfter(weekEnd);
      case CalendarViewMode.month:
        return _anchorDate.year == now.year && _anchorDate.month == now.month;
    }
  }

  void _syncEvents() {
    final events = widget.events.map(KalenderCalendarEvent.fromAdapter).toList();
    final signature = events
        .map(
          (e) =>
              '${e.id}|${e.start.microsecondsSinceEpoch}|${e.end.microsecondsSinceEpoch}'
              '|${e.adapter.title}|${e.adapter.color}|${e.adapter.isAllDay}|${e.adapter.rrule}',
        )
        .join(',');
    if (signature == _eventsSignature) return;
    _eventsSignature = signature;
    _eventsController
      ..clearEvents()
      ..addEvents(events);
  }

  DateTime _anchorFromRange(DateTimeRange range, CalendarViewMode mode) {
    switch (mode) {
      case CalendarViewMode.month:
        // The month grid starts up to 6 days before the displayed month;
        // +7d always lands inside that month.
        final d = range.start.add(const Duration(days: 7));
        return DateTime(d.year, d.month, d.day);
      case CalendarViewMode.day:
      case CalendarViewMode.week:
        final s = range.start;
        return DateTime(s.year, s.month, s.day);
    }
  }

  void _onVisibleRange() {
    final range = _calendarController.visibleDateTimeRange.value;
    if (range == null) return;
    _applyVisibleRange(range);
  }

  void _applyVisibleRange(DateTimeRange range) {
    final mode = ref.read(calendarViewModeProvider);
    final anchor = _anchorFromRange(range, mode);
    void apply() {
      if (!mounted || anchor == _anchorDate) return;
      setState(() => _anchorDate = anchor);
      widget.onAnchorChanged?.call(anchor);
      ref.read(viewedDateProvider.notifier).state = anchor;
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _setAnchor(DateTime anchor) {
    if (anchor == _anchorDate) return;
    setState(() => _anchorDate = anchor);
    widget.onAnchorChanged?.call(anchor);
    ref.read(viewedDateProvider.notifier).state = anchor;
  }

  String _formatDayHeader() {
    final locale = Localizations.localeOf(context).toString();
    final dateStr = DateFormat.MMMd(locale).format(_anchorDate);
    final weekday = DateFormat.E(locale).format(_anchorDate);
    return '$dateStr  $weekday';
  }

  String _formatWeekHeader() {
    final locale = Localizations.localeOf(context).toString();
    final weekday = _anchorDate.weekday;
    final weekStart = _anchorDate.subtract(Duration(days: weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${DateFormat.Md(locale).format(weekStart)} – ${DateFormat.Md(locale).format(weekEnd)}';
  }

  String _formatMonthHeader() {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMM(locale).format(_anchorDate);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final d = DateTime(picked.year, picked.month, picked.day);
      _calendarController.jumpToDate(d);
      _setAnchor(d);
    }
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _calendarController.jumpToDate(today);
    _setAnchor(today);
  }

  void _navigateBack() {
    unawaited(_calendarController.animateToPreviousPage());
  }

  void _navigateForward() {
    unawaited(_calendarController.animateToNextPage());
  }

  // kalender's tap details carry wall-clock components marked isUtc (not a
  // real instant). Rebuild as local so the router's
  // millisecondsSinceEpoch → fromMillisecondsSinceEpoch round-trip doesn't
  // shift the prefill by the UTC offset.
  DateTime _asLocalWallClock(DateTime d) =>
      d.isUtc ? DateTime(d.year, d.month, d.day, d.hour, d.minute) : d;

  void _handleTapDetail(TapDetail details) {
    final DateTime raw;
    if (details is DayDetail) {
      raw = details.date;
    } else if (details is MultiDayDetail) {
      raw = details.dateTimeRange.start;
    } else {
      return;
    }
    final start = _asLocalWallClock(raw);
    widget.onTimeSlotTapped?.call(
      DateTimeRange(
        start: start,
        end: start.add(const Duration(hours: 1)),
      ),
    );
  }

  Widget _buildTile(CalendarEvent event, DateTimeRange tileRange) {
    if (event is KalenderCalendarEvent) {
      return EventTile(
        event: event.adapter,
        onTap: () => widget.onEventTapped?.call(event.adapter),
      );
    }
    return const SizedBox.shrink();
  }

  CalendarCallbacks _buildCallbacks() {
    return CalendarCallbacks(
      onEventChanged: (event, updatedEvent) {
        if (event is! KalenderCalendarEvent) return;
        final adapter = event.adapter;
        // S1 guard: never persist drags onto recurring/all-day events.
        if (adapter.rrule != null || adapter.isAllDay) return;
        widget.onEventChanged?.call(
          adapter.copyWithData(
            start: updatedEvent.dateTimeRange.start.toLocal(),
            end: updatedEvent.dateTimeRange.end.toLocal(),
          ),
        );
      },
      onPageChanged: _applyVisibleRange,
      onTappedWithDetail: _handleTapDetail,
    );
  }

  ViewConfiguration _resolveViewConfiguration() {
    final mode = _viewMode;
    if (_viewConfiguration == null || _configMode != mode) {
      _configMode = mode;
      _viewConfiguration = switch (mode) {
        CalendarViewMode.day => MultiDayViewConfiguration.singleDay(
            initialDateTime: _anchorDate,
            initialTimeOfDay: const TimeOfDay(hour: 8, minute: 0),
          ),
        CalendarViewMode.week => MultiDayViewConfiguration.week(
            initialDateTime: _anchorDate,
            initialTimeOfDay: const TimeOfDay(hour: 8, minute: 0),
          ),
        CalendarViewMode.month => MonthViewConfiguration.singleMonth(
            initialDateTime: _anchorDate,
          ),
      };
    }
    return _viewConfiguration!;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final calendarView = CalendarView(
      eventsController: _eventsController,
      calendarController: _calendarController,
      viewConfiguration: _resolveViewConfiguration(),
      callbacks: _buildCallbacks(),
      components: CalendarComponents(
        monthComponents: MonthComponents(
          bodyComponents: MonthBodyComponents(
            // Month day cells carry solar-term labels and statutory
            // holiday / makeup-workday badges.
            monthDayHeaderBuilder: (date, style) => MarkedMonthDayHeader(
              date: date,
              style: style,
              dim:
                  date.year != _anchorDate.year ||
                  date.month != _anchorDate.month,
            ),
          ),
        ),
      ),
      header: CalendarHeader(
        callbacks: _buildCallbacks(),
        interaction: _interaction,
        multiDayTileComponents: _tileComponents,
      ),
      body: CalendarBody(
        callbacks: _buildCallbacks(),
        interaction: _interaction,
        multiDayTileComponents: _tileComponents,
        monthTileComponents: _tileComponents,
        multiDayBodyConfiguration: MultiDayBodyConfiguration(
          eventLayoutStrategy: sideBySideLayoutStrategy,
        ),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: Semantics(
                      button: true,
                      label: (switch (_viewMode) {
                        CalendarViewMode.day => _formatDayHeader(),
                        CalendarViewMode.week => _formatWeekHeader(),
                        CalendarViewMode.month => _formatMonthHeader(),
                      }),
                      child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              (switch (_viewMode) {
                                CalendarViewMode.day => _formatDayHeader(),
                                CalendarViewMode.week => _formatWeekHeader(),
                                CalendarViewMode.month => _formatMonthHeader(),
                              }),
                              key: ValueKey(_anchorDate),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            CupertinoIcons.calendar,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                  ),
                  if (!_isViewingToday) ...[
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: l.goToToday,
                      child: TextButton(
                        onPressed: _goToToday,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                        ),
                        child: Text(l.goToToday),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: l.previousPeriod,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                        onPressed: _navigateBack,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l.nextPeriod,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        icon: const Icon(CupertinoIcons.chevron_right, size: 20),
                        onPressed: _navigateForward,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ViewSwitcher(
                currentMode: _viewMode,
                onModeChanged: (mode) =>
                    ref.read(calendarViewModeProvider.notifier).setViewMode(mode),
              ),
            ],
          ),
        ),
        Expanded(
          // kalender exposes no semantics node for the blank tap-target
          // slots, so the day/week body region carries the button label
          // instead (tiles inside keep their own semantics). The wrapper
          // stays on every mode so CalendarView keeps its state across
          // view switches.
          child: Semantics(
            button: _viewMode != CalendarViewMode.month,
            label:
                _viewMode == CalendarViewMode.month
                    ? null
                    : l.emptySlotSemantics,
            child: calendarView,
          ),
        ),
      ],
    );
  }
}
