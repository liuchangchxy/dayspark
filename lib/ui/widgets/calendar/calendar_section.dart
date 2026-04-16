import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/event_tile.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/view_switcher.dart';

class CalendarSection extends StatefulWidget {
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;

  const CalendarSection({
    super.key,
    required this.events,
    this.onEventTapped,
    this.onTimeSlotTapped,
  });

  @override
  State<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<CalendarSection> {
  CalendarViewMode _viewMode = CalendarViewMode.week;
  final _calendarController = CalendarController();
  final _eventsController = DefaultEventsController();

  @override
  void initState() {
    super.initState();
    _syncEvents();
  }

  @override
  void didUpdateWidget(CalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != oldWidget.events) {
      _syncEvents();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              TextButton(
                onPressed: () {
                  _calendarController.jumpToDate(DateTime.now());
                },
                child: const Text('Today'),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _calendarController.animateToPreviousPage(),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _calendarController.animateToNextPage(),
              ),
              const SizedBox(width: 8),
              ViewSwitcher(
                currentMode: _viewMode,
                onModeChanged: (mode) => setState(() => _viewMode = mode),
              ),
            ],
          ),
        ),
        Expanded(
          child: CalendarView(
            eventsController: _eventsController,
            calendarController: _calendarController,
            viewConfiguration: _viewConfig(),
            callbacks: CalendarCallbacks(
              onEventTapped: (event, renderBox) {
                if (widget.onEventTapped != null) {
                  widget.onEventTapped!(event as CalendaEventAdapter);
                }
              },
              onTapped: (datetime) {
                if (widget.onTimeSlotTapped != null) {
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
              multiDayTileComponents: _tileComponents(),
            ),
            body: CalendarBody(
              multiDayTileComponents: _tileComponents(),
              monthTileComponents: _tileComponents(),
            ),
          ),
        ),
      ],
    );
  }
}
