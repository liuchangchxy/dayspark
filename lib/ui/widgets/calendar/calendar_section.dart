import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart';
import 'package:kalender/src/widgets/components/month_day_header.dart';
import 'package:kalender/src/models/components/components.dart';
import 'package:lunar/lunar.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

class CalendarSection extends StatefulWidget {
  final List<CalendaEventAdapter> events;
  final bool showLunar;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;
  final void Function(CalendaEventAdapter event)? onEventChanged;

  const CalendarSection({
    super.key,
    required this.events,
    this.showLunar = false,
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
    switch (_viewMode) {
      case CalendarViewMode.day:
        return start.year == now.year &&
            start.month == now.month &&
            start.day == now.day;
      case CalendarViewMode.week:
        // Check if today falls within the visible week range
        final end = _visibleRange!.end;
        return !now.isBefore(start) && now.isBefore(end);
      case CalendarViewMode.month:
        return start.year == now.year && start.month == now.month;
    }
  }

  int _weekOfMonth(DateTime date) {
    final firstDay = DateTime(date.year, date.month, 1);
    final firstWeekday = firstDay.weekday % 7; // Sun=0
    return ((date.day + firstWeekday - 1) / 7).floor() + 1;
  }

  String _formatVisibleDate() {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final l = AppLocalizations.of(context)!;
    if (_visibleRange == null) {
      return DateFormat.yMMMM(locale).format(now);
    }
    final start = _visibleRange!.start;
    switch (_viewMode) {
      case CalendarViewMode.day:
        return DateFormat.yMMMMd(locale).format(start);
      case CalendarViewMode.week:
        final weekNum = _weekOfMonth(start);
        final monthStr = DateFormat.M(locale).format(start);
        return l.weekOfMonth(weekNum, monthStr);
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

  Widget _buildCustomMonthDayHeader(
    InternalDateTime date,
    MonthDayHeaderStyle? style,
  ) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    String? lunarText;
    if (widget.showLunar) {
      final solar = Solar.fromYmd(date.year, date.month, date.day);
      final l = solar.getLunar();
      final dayStr = l.getDayInChinese();
      if (l.getDay() == 1) {
        lunarText = l.getMonthInChinese() + '月';
      } else {
        lunarText = dayStr;
      }
    }

    if (isToday) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              date.day.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (lunarText != null)
              Text(
                lunarText,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.8),
                  fontSize: 8,
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(date.day.toString(), style: style?.numberTextStyle),
          if (lunarText != null)
            Text(
              lunarText,
              style: TextStyle(
                fontSize: 8,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
        ],
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
        // Header: two rows to avoid overflow
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Row 1: date + navigation
              Row(
                children: [
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
                  if (!_isViewingToday)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton(
                        onPressed: () =>
                            _calendarController.jumpToDate(DateTime.now()),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                        ),
                        child: Text(l.goToToday),
                      ),
                    ),
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
              const SizedBox(height: 8),
              // Row 2: view switcher (full width)
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
