import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart';
import 'package:kalender/src/models/components/components.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/l10n/app_localizations.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/event_tile.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/view_switcher.dart';

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
        _visibleRange = DateTimeRange(
          start: range.start,
          end: range.end,
        );
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

  String _formatVisibleDate() {
    if (_visibleRange == null) {
      return DateFormat.yMMMM(Localizations.localeOf(context).toString()).format(DateTime.now());
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tileComponents = _tileComponents();
    final locale = Localizations.localeOf(context).toString();

    return Column(
      children: [
        // Custom header: date display + navigation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Date display (tappable to go to today)
              GestureDetector(
                onTap: () => _calendarController.jumpToDate(DateTime.now()),
                child: Text(
                  _formatVisibleDate(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              // Today button
              TextButton(
                onPressed: () => _calendarController.jumpToDate(DateTime.now()),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: Text(l.today),
              ),
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
              const SizedBox(width: 8),
              // View switcher
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
            header: CalendarHeader(
              multiDayTileComponents: tileComponents,
            ),
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
