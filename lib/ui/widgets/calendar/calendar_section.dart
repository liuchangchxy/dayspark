import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_day_header.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_hour_lines.dart';
import 'package:dayspark/ui/widgets/calendar/kalender_calendar_event.dart';
import 'package:dayspark/ui/widgets/calendar/kalender_task_allocation.dart';
import 'package:dayspark/ui/widgets/calendar/task_allocation_tile.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

class CalendarSection extends ConsumerStatefulWidget {
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarAdapter> allocations;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;
  final void Function(CalendaEventAdapter event)? onEventChanged;
  final void Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationTapped;
  final Future<void> Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationChanged;
  final void Function(DateTime anchor)? onAnchorChanged;

  /// When true the section drops its inline date-range title (the host shows
  /// it in the page header instead) but keeps the view switcher and paging
  /// controls (DESIGN 页面主标题).
  final bool hideHeader;

  /// Called whenever the title for the current view/anchor changes, so the
  /// host can put it in the page header.
  final void Function(String title, String? subtitle)? onHeaderChanged;

  const CalendarSection({
    super.key,
    required this.events,
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
        return !_anchorDate.isBefore(weekStart) &&
            !_anchorDate.isAfter(weekEnd);
      case CalendarViewMode.month:
        return _anchorDate.year == now.year && _anchorDate.month == now.month;
    }
  }

  void _syncEvents({bool force = false}) {
    final calendarEvents = <CalendarEvent>[
      ...widget.events.map(KalenderCalendarEvent.fromAdapter),
      ...widget.allocations.map(KalenderTaskAllocation.fromAdapter),
    ];
    final signature = calendarEvents.map(_eventSignature).join(',');
    if (!force && signature == _eventsSignature) return;
    _eventsSignature = signature;
    _eventsController
      ..clearEvents()
      ..addEvents(calendarEvents);
  }

  Future<void> _persistTaskAllocationChange(
    TaskAllocationCalendarAdapter allocation,
  ) async {
    try {
      await widget.onTaskAllocationChanged?.call(allocation);
    } catch (error) {
      if (!mounted) return;
      _syncEvents(force: true);
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(l.error('$error'))));
    }
  }

  String _eventSignature(CalendarEvent event) {
    if (event is KalenderCalendarEvent) {
      final adapter = event.adapter;
      return <Object?>[
        event.id,
        adapter.drifId,
        adapter.calendarId,
        adapter.title,
        adapter.description,
        adapter.location,
        adapter.color?.toARGB32(),
        adapter.isAllDay,
        adapter.rrule,
        adapter.start.microsecondsSinceEpoch,
        adapter.end.microsecondsSinceEpoch,
      ].join('|');
    }
    final allocation = (event as KalenderTaskAllocation).allocation;
    return <Object?>[
      event.id,
      allocation.id,
      allocation.todoId,
      allocation.todoTitle,
      allocation.start.microsecondsSinceEpoch,
      allocation.end.microsecondsSinceEpoch,
    ].join('|');
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

  Widget _buildToolbar(AppLocalizations l) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        widget.hideHeader ? AppSpacing.sm : AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          ViewSwitcher(
            currentMode: _viewMode,
            onModeChanged: (mode) =>
                ref.read(calendarViewModeProvider.notifier).setViewMode(mode),
          ),
          if (!_isViewingToday) ...[
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              button: true,
              label: l.goToToday,
              child: TextButton(
                onPressed: _goToToday,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    );
  }

  /// Title shown in the page header. Day and week carry their range; month
  /// carries only "9月" because the year sits underneath it (DESIGN 页面主标题).
  String get headerTitle => switch (_viewMode) {
    CalendarViewMode.day => _formatDayHeader(),
    CalendarViewMode.week => _formatWeekHeader(),
    CalendarViewMode.month => _formatMonthOnly(),
  };

  /// Subtitle under [headerTitle]; null when the title already carries it.
  String? get headerSubtitle => _viewMode == CalendarViewMode.month
      ? DateFormat.y(
          Localizations.localeOf(context).toString(),
        ).format(_anchorDate)
      : null;

  String _formatMonthOnly() {
    final locale = Localizations.localeOf(context).toString();
    final month = DateFormat.MMM(locale).format(_anchorDate);
    // zh formats as "9月" already; "2026年9月" would duplicate the year.
    return month;
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
      DateTimeRange(start: start, end: start.add(const Duration(hours: 1))),
    );
  }

  Widget _buildTile(CalendarEvent event, DateTimeRange tileRange) {
    if (event is KalenderTaskAllocation) {
      return TaskAllocationTile(
        allocation: event.allocation,
        onTap: () => widget.onTaskAllocationTapped?.call(event.allocation),
      );
    }
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
        if (event is KalenderTaskAllocation) {
          unawaited(
            _persistTaskAllocationChange(
              event.allocation.copyWith(
                start: updatedEvent.dateTimeRange.start.toLocal(),
                end: updatedEvent.dateTimeRange.end.toLocal(),
              ),
            ),
          );
          return;
        }
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
    widget.onHeaderChanged?.call(headerTitle, headerSubtitle);
    final theme = Theme.of(context);

    final calendarView = CalendarView(
      eventsController: _eventsController,
      calendarController: _calendarController,
      viewConfiguration: _resolveViewConfiguration(),
      callbacks: _buildCallbacks(),
      components: CalendarComponents(
        multiDayComponents: MultiDayComponents(
          headerComponents: MultiDayHeaderComponents(
            // kalender's default is a filled tonal IconButton that crowds the
            // time gutter; the gutter carries the timeline, so the week number
            // stays a quiet label (DESIGN Kalender 接管条款).
            weekNumberBuilder: (range, style) => Center(
              child: Text(
                '${range.weekNumbers.$1}',
                style: AppTypography.overline.copyWith(
                  color: context.semantic.textTertiary,
                ),
              ),
            ),
            // Big number + weekday, today in accent (own widget, not
            // kalender's grey IconButton two-liner).
            dayHeaderBuilder: (date, style) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final day = DateTime(date.year, date.month, date.day);
              return CalendarDayHeader(date: day, isToday: day == today);
            },
          ),
          bodyComponents: MultiDayBodyComponents(
            // Full-hour lines only; kalender's adaptive half-hour
            // segments read as prison bars on dark backgrounds.
            hourLines: (heightPerMinute, range, style, timelineStyle) =>
                CalendarHourLines(
                  heightPerMinute: heightPerMinute,
                  timeOfDayRange: range,
                  color: theme.dividerColor.withValues(alpha: 0.35),
                ),
          ),
        ),
        multiDayComponentStyles: MultiDayComponentStyles(
          bodyStyles: MultiDayBodyComponentStyles(
            timeIndicatorStyle: TimeIndicatorStyle(
              lineColor: theme.colorScheme.error,
              circleColor: theme.colorScheme.error,
            ),
            // Grid recedes: derived from divider at ~1/3 so events lead.
            hourLinesStyle: HourLinesStyle(
              color: theme.dividerColor.withValues(alpha: 0.35),
            ),
            daySeparatorStyle: DaySeparatorStyle(
              color: theme.dividerColor.withValues(alpha: 0.35),
            ),
            // Ruler labels: fixed 24h H:mm, self-measuring, no CJK clipping.
            timelineStyle: TimelineStyle(
              stringBuilder: (timeOfDay) =>
                  '${timeOfDay.hour}:${timeOfDay.minute.toString().padLeft(2, '0')}',
              textStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
              // Gutter padding is measured with the text, so labels can
              // never clip at the screen edge. Vertical padding also sets
              // label density: 44 keeps totalItems < 12 at the default
              // 0.7 heightPerMinute, i.e. hourly labels on hourly lines
              // (36 lands exactly on the 30-minute boundary). Zeroing it
              // collapses labels to every 5 minutes.
              textPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 44,
              ),
            ),
          ),
        ),
        monthComponentStyles: MonthComponentStyles(
          headerStyles: MonthHeaderComponentStyles(
            weekDayHeaderStyle: WeekDayHeaderStyle(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              // Weekday names follow the app language, not the browser locale.
              stringBuilder: (date) => DateFormat.E(
                Localizations.localeOf(context).toString(),
              ).format(date),
            ),
          ),
        ),
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
        _buildToolbar(l),
        Expanded(
          child: Stack(
            children: [
              // kalender exposes no semantics node for the blank tap-target
              // slots, so the day/week body region carries the button label
              // instead (tiles inside keep their own semantics). The wrapper
              // stays on every mode so CalendarView keeps its state across
              // view switches.
              Semantics(
                button: _viewMode != CalendarViewMode.month,
                label: _viewMode == CalendarViewMode.month
                    ? null
                    : l.emptySlotSemantics,
                child: calendarView,
              ),
              // Empty grid reads as a dead spreadsheet; float one
              // non-interactive hint instead (taps pass through to slots).
              if (widget.events.isEmpty && _viewMode != CalendarViewMode.month)
                Positioned(
                  // Clears the day-header row so the hint never sits on the
                  // weekday labels.
                  top: 88,
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          l.emptyCalendarHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
