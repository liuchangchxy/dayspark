import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart';
import 'package:kalender/src/widgets/components/month_day_header.dart';
import 'package:kalender/src/models/components/components.dart';
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
      setState(() {
        _visibleRange = DateTimeRange(start: range.start, end: range.end);
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

  ViewConfiguration _viewConfig() {
    switch (_viewMode) {
      case CalendarViewMode.day:
        return MultiDayViewConfiguration.singleDay();
      case CalendarViewMode.week:
        return MultiDayViewConfiguration.week();
      case CalendarViewMode.month:
        return MonthViewConfiguration.singleMonth();
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
    if (_visibleRange == null) return true;
    final now = DateTime.now();
    final start = _visibleRange!.start;
    return start.year == now.year && start.month == now.month;
  }

  String _formatVisibleDate() {
    if (_visibleRange == null) {
      return DateFormat.yMMMM(
        Localizations.localeOf(context).toString(),
      ).format(DateTime.now());
    }
    final start = _visibleRange!.start;
    final locale = Localizations.localeOf(context).toString();
    switch (_viewMode) {
      case CalendarViewMode.day:
        return DateFormat.yMMMMd(locale).format(start);
      case CalendarViewMode.week:
        final end = _visibleRange!.end;
        if (start.month == end.month) {
          return DateFormat.yMMMM(locale).format(start);
        }
        return '${DateFormat.M(locale).format(start)} - ${DateFormat.yMMMM(locale).format(end)}';
      case CalendarViewMode.month:
        return DateFormat.yMMMM(locale).format(start);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visibleRange?.start ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _calendarController.jumpToDate(picked);
    }
  }

  Widget _buildTodayButton(AppLocalizations l) {
    if (_isViewingToday) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(CupertinoIcons.calendar_badge_plus, size: 20),
      tooltip: l.goToToday,
      onPressed: () => _calendarController.jumpToDate(DateTime.now()),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _buildCustomMonthDayHeader(
    InternalDateTime date,
    MonthDayHeaderStyle? style,
  ) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Text(
          date.day.toString(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      );
    }
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: null,
        icon: Text(date.day.toString(), style: style?.numberTextStyle),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tileComponents = _tileComponents();
    final locale = Localizations.localeOf(context).toString();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Date display (tappable to pick a date)
              GestureDetector(
                onTap: _pickDate,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _formatVisibleDate(),
                        key: ValueKey(_formatVisibleDate()),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.calendar,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              // "Return to today" icon (only when not on today)
              _buildTodayButton(l),
              const Spacer(),
              // Navigation arrows
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                onPressed: () => _calendarController.animateToPreviousPage(),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_right, size: 20),
                onPressed: () => _calendarController.animateToNextPage(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              // View switcher
              FittedBox(
                child: ViewSwitcher(
                  currentMode: _viewMode,
                  onModeChanged: (mode) => setState(() => _viewMode = mode),
                ),
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
              onTapped: (datetime) {
                if (_viewMode == CalendarViewMode.month) {
                  setState(() {
                    _viewMode = CalendarViewMode.day;
                  });
                  _calendarController.jumpToDate(datetime);
                } else if (widget.onTimeSlotTapped != null) {
                  widget.onTimeSlotTapped!(
                    DateTimeRange(
                      start: datetime,
                      end: datetime.add(const Duration(hours: 1)),
                    ),
                  );
                }
              },
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
