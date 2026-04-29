import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

class CalendarSection extends StatefulWidget {
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;
  final void Function(CalendaEventAdapter event)? onEventChanged;

  const CalendarSection({
    super.key,
    required this.events,
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onEventChanged,
  });

  @override
  State<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<CalendarSection> {
  CalendarViewMode _viewMode = CalendarViewMode.week;
  final _calendarController = CalendarController();
  final _eventsController = DefaultEventsController();
  DateTimeRange? _visibleRange;
  DateTime? _lastTappedDate;

  @override
  void initState() {
    super.initState();
    _syncEvents();
    _calendarController.visibleDateTimeRange.addListener(_onVisibleChanged);
  }

  @override
  void didUpdateWidget(CalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != oldWidget.events) {
      _syncEvents();
    }
  }

  void _onVisibleChanged() {
    final range = _calendarController.visibleDateTimeRange.value;
    if (range != null && mounted) {
      if (_visibleRange != null &&
          _visibleRange!.start == range.start &&
          _visibleRange!.end == range.end) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _visibleRange = DateTimeRange(start: range.start, end: range.end);
          });
        }
      });
    }
  }

  void _syncEvents() {
    _eventsController.clearEvents();
    for (final event in widget.events) {
      _eventsController.addEvent(event);
    }
  }

  @override
  void dispose() {
    _calendarController.visibleDateTimeRange.removeListener(_onVisibleChanged);
    _calendarController.dispose();
    _eventsController.dispose();
    super.dispose();
  }

  /// Get the user-meaningful "current date" from the visible range.
  /// For month view, use the dominant month date to avoid overflow issues.
  DateTime get _currentDate {
    if (_visibleRange == null) return DateTime.now();
    switch (_viewMode) {
      case CalendarViewMode.day:
        return _visibleRange!.start;
      case CalendarViewMode.week:
        // Use the middle of the week
        return _visibleRange!.start.add(const Duration(days: 3));
      case CalendarViewMode.month:
        // Use dominant month to avoid overflow days causing wrong month
        final start = _visibleRange!.start;
        final end = _visibleRange!.end;
        final mid = start.add(
          Duration(milliseconds: end.difference(start).inMilliseconds ~/ 2),
        );
        return mid;
    }
  }

  ViewConfiguration _viewConfig() {
    final date = _currentDate;
    switch (_viewMode) {
      case CalendarViewMode.day:
        return MultiDayViewConfiguration.singleDay(initialDateTime: date);
      case CalendarViewMode.week:
        return MultiDayViewConfiguration.week(initialDateTime: date);
      case CalendarViewMode.month:
        return MonthViewConfiguration.singleMonth(initialDateTime: date);
    }
  }

  TileComponents _tileComponents() {
    return TileComponents(
      tileBuilder: (event, tileRange) {
        final adapter = event as CalendaEventAdapter;
        return EventTile(event: adapter);
      },
    );
  }

  bool get _isViewingToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_viewMode) {
      case CalendarViewMode.day:
        final d = _currentDate;
        return d.year == now.year && d.month == now.month && d.day == now.day;
      case CalendarViewMode.week:
        if (_visibleRange == null) return false;
        final start = DateTime(
          _visibleRange!.start.year,
          _visibleRange!.start.month,
          _visibleRange!.start.day,
        );
        final end = DateTime(
          _visibleRange!.end.year,
          _visibleRange!.end.month,
          _visibleRange!.end.day,
        );
        return !today.isBefore(start) && !today.isAfter(end);
      case CalendarViewMode.month:
        final d = _currentDate;
        return d.year == now.year && d.month == now.month;
    }
  }

  int _weekOfMonth(DateTime date) {
    final firstDay = DateTime(date.year, date.month, 1);
    final firstWeekday = firstDay.weekday % 7;
    return ((date.day + firstWeekday - 1) / 7).floor() + 1;
  }

  String _formatVisibleDate() {
    final l = AppLocalizations.of(context)!;
    final date = _currentDate;
    final weekNum = _weekOfMonth(date);
    return '${date.year}/${date.month}/${date.day}  ${l.weekOfMonth(weekNum)}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _calendarController.jumpToDate(picked);
    }
  }

  Widget _buildCustomMonthDayHeader(
    InternalDateTime date,
    MonthDayHeaderStyle? style,
  ) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    final visibleDate = _currentDate;
    final isOverflow =
        date.month != visibleDate.month || date.year != visibleDate.year;

    // Tapped date highlight
    final isTapped =
        _lastTappedDate != null &&
        date.year == _lastTappedDate!.year &&
        date.month == _lastTappedDate!.month &&
        date.day == _lastTappedDate!.day;

    if (isToday) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          date.day.toString(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      );
    }

    if (isTapped) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          date.day.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        date.day.toString(),
        style: isOverflow
            ? (style?.numberTextStyle?.copyWith(
                    color: Theme.of(
                      context,
                    ).disabledColor.withValues(alpha: 0.3),
                  ) ??
                  TextStyle(
                    color: Theme.of(
                      context,
                    ).disabledColor.withValues(alpha: 0.3),
                  ))
            : style?.numberTextStyle,
      ),
    );
  }

  Widget _buildCustomDayHeader(InternalDateTime date, DayHeaderStyle? style) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final theme = Theme.of(context);

    final isTapped =
        _lastTappedDate != null &&
        date.year == _lastTappedDate!.year &&
        date.month == _lastTappedDate!.month &&
        date.day == _lastTappedDate!.day;

    final highlight = isToday || isTapped;
    final numberText = Text(
      date.day.toString(),
      style: TextStyle(
        fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
        color: isToday ? theme.colorScheme.onPrimary : null,
      ),
    );

    if (isToday) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(6),
        child: numberText,
      );
    }

    if (isTapped) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(6),
        child: numberText,
      );
    }

    return Padding(padding: const EdgeInsets.all(6), child: numberText);
  }

  void _handleTap(DateTime datetime) {
    if (widget.onTimeSlotTapped == null) return;
    setState(() {
      _lastTappedDate = DateTime(datetime.year, datetime.month, datetime.day);
    });
    // Clear highlight after a short delay and navigate
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _lastTappedDate = null);
      }
    });
    widget.onTimeSlotTapped!(
      DateTimeRange(
        start: datetime,
        end: datetime.add(const Duration(hours: 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tileComponents = _tileComponents();
    final locale = Localizations.localeOf(context).toString();
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              // Row 1: date + pick + today + nav
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickDate,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.08,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _formatVisibleDate(),
                              key: ValueKey(_formatVisibleDate()),
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
                  if (!_isViewingToday) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () =>
                          _calendarController.jumpToDate(DateTime.now()),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                      ),
                      child: Text(l.goToToday),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                    onPressed: () =>
                        _calendarController.animateToPreviousPage(),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_right, size: 20),
                    onPressed: () => _calendarController.animateToNextPage(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Row 2: view switcher
              ViewSwitcher(
                currentMode: _viewMode,
                onModeChanged: (mode) => setState(() => _viewMode = mode),
              ),
            ],
          ),
        ),
        Expanded(
          child: CalendarView(
            locale: locale,
            eventsController: _eventsController,
            calendarController: _calendarController,
            viewConfiguration: _viewConfig(),
            components: CalendarComponents(
              monthComponents: MonthComponents(
                bodyComponents: MonthBodyComponents(
                  monthDayHeaderBuilder: _buildCustomMonthDayHeader,
                ),
              ),
              multiDayComponents: MultiDayComponents(
                headerComponents: MultiDayHeaderComponents(
                  dayHeaderBuilder: _buildCustomDayHeader,
                  weekNumberBuilder: (_, __) => const SizedBox.shrink(),
                ),
              ),
              multiDayComponentStyles: MultiDayComponentStyles(
                bodyStyles: MultiDayBodyComponentStyles(
                  timelineStyle: TimelineStyle(
                    stringBuilder: (time) =>
                        '${time.hour.toString().padLeft(2, '0')}:00',
                  ),
                ),
              ),
              overlayStyles: OverlayStyles(
                multiDayOverlayStyle: MultiDayOverlayStyle(
                  closeIcon: const Icon(CupertinoIcons.xmark, size: 16),
                ),
              ),
            ),
            callbacks: CalendarCallbacks(
              onEventTapped: (event, renderBox) {
                if (widget.onEventTapped != null) {
                  widget.onEventTapped!(event as CalendaEventAdapter);
                }
              },
              onEventChange: (event) {},
              onEventChanged: (event, updatedEvent) {
                if (widget.onEventChanged != null) {
                  final original = event as CalendaEventAdapter;
                  final rescheduled = original.copyWithData(
                    dateTimeRange: updatedEvent.dateTimeRange,
                  );
                  widget.onEventChanged!(rescheduled);
                }
              },
              onTapped: _handleTap,
            ),
            header: CalendarHeader(multiDayTileComponents: tileComponents),
            body: CalendarBody(
              multiDayTileComponents: tileComponents,
              monthTileComponents: tileComponents,
            ),
          ),
        ),
      ],
    );
  }
}
