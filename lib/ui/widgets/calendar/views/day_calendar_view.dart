import 'package:flutter/material.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/core/utils/date_formatters.dart';

class DayCalendarView extends StatefulWidget {
  final DateTime anchorDate;
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter)? onEventTapped;
  final void Function(DateTime datetime)? onTimeSlotTapped;
  final void Function(DateTime newAnchor)? onPageChanged;

  const DayCalendarView({
    super.key,
    required this.anchorDate,
    this.events = const [],
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onPageChanged,
  });

  @override
  State<DayCalendarView> createState() => _DayCalendarViewState();
}

class _DayCalendarViewState extends State<DayCalendarView> {
  static const double _hourHeight = 48.0;
  static const double _timelineWidth = 48.0;
  static const int _totalDays = 24000;
  static const int _epochDay = 12000;
  static const Duration _scrollTarget = Duration(hours: 8);

  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _dayToIndex(widget.anchorDate),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTime();
    });
  }

  @override
  void didUpdateWidget(covariant DayCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _dayToIndex(oldWidget.anchorDate);
    final newIndex = _dayToIndex(widget.anchorDate);
    if (oldIndex != newIndex && _pageController.hasClients) {
      final currentPage =
          _pageController.page?.round() ?? _dayToIndex(oldWidget.anchorDate);
      if (currentPage != newIndex) {
        _pageController.animateToPage(
          newIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTime() {
    if (!_scrollController.hasClients) return;
    final pixels = _scrollTarget.inMinutes / 60.0 * _hourHeight;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(pixels.clamp(0, max));
  }

  static int _dayToIndex(DateTime date) {
    final epoch = DateTime(2000, 1, 1);
    return date.difference(epoch).inDays + _epochDay;
  }

  static DateTime _indexToDay(int index) {
    final epoch = DateTime(2000, 1, 1);
    return epoch.add(Duration(days: index - _epochDay));
  }

  List<CalendaEventAdapter> _timedEvents(DateTime date) {
    return widget.events.where((e) {
      if (e.isAllDay) return false;
      final eventDate = DateTime(e.start.year, e.start.month, e.start.day);
      return eventDate == date;
    }).toList();
  }

  List<CalendaEventAdapter> _allDayEvents(DateTime date) {
    return widget.events.where((e) {
      if (!e.isAllDay) return false;
      final eventDate = DateTime(e.start.year, e.start.month, e.start.day);
      return eventDate == date;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildAllDayBar(context, theme),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _totalDays,
            scrollDirection: Axis.horizontal,
            onPageChanged: (index) {
              widget.onPageChanged?.call(_indexToDay(index));
            },
            itemBuilder: (context, index) {
              final date = _indexToDay(index);
              return _buildDayPage(context, theme, date);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAllDayBar(BuildContext context, ThemeData theme) {
    final allDay = _allDayEvents(_dateOnly(widget.anchorDate));
    if (allDay.isEmpty) {
      return _buildDayHeader(theme, _dateOnly(widget.anchorDate));
    }

    return Column(
      children: [
        _buildDayHeader(theme, _dateOnly(widget.anchorDate)),
        SizedBox(
          height: allDay.length * 24.0,
          child: Column(
            children: allDay.map((e) {
              return GestureDetector(
                onTap: () => widget.onEventTapped?.call(e),
                child: Container(
                  height: 20,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: (e.color ?? theme.colorScheme.primary)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    e.title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: e.color ?? theme.colorScheme.primary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeader(ThemeData theme, DateTime date) {
    final today = _dateOnly(DateTime.now());
    final isToday = date == today;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: _timelineWidth),
          Container(
            width: 34,
            height: 34,
            decoration: isToday
                ? BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  )
                : null,
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: isToday
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormatters.formatDate(date),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayPage(
    BuildContext context,
    ThemeData theme,
    DateTime date,
  ) {
    final totalHeight = 24 * _hourHeight;
    final events = _timedEvents(date);

    return SingleChildScrollView(
      controller: _scrollController,
      child: SizedBox(
        height: totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTimeline(theme, totalHeight),
            Expanded(
              child: _buildEventColumn(theme, date, events, totalHeight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(ThemeData theme, double totalHeight) {
    return SizedBox(
      width: _timelineWidth,
      height: totalHeight,
      child: Stack(
        children: List.generate(24, (hour) {
          return Positioned(
            top: hour * _hourHeight,
            left: 0,
            right: 4,
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              textAlign: TextAlign.right,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEventColumn(
    ThemeData theme,
    DateTime date,
    List<CalendaEventAdapter> events,
    double totalHeight,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final hour = (details.localPosition.dy / _hourHeight).floor();
        final tappedDate = DateTime(
          date.year,
          date.month,
          date.day,
          hour.clamp(0, 23),
        );
        widget.onTimeSlotTapped?.call(tappedDate);
      },
      child: Container(
        height: totalHeight,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Stack(
          children: [
            ...List.generate(25, (hour) {
              return Positioned(
                top: hour * _hourHeight,
                left: 0,
                right: 0,
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              );
            }),
            ..._layoutEvents(events).map((entry) {
              return Positioned(
                top: entry.top,
                left: entry.left,
                width: entry.width,
                height: entry.height,
                child: GestureDetector(
                  onTap: () => widget.onEventTapped?.call(entry.event),
                  child: EventTile(event: entry.event),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  List<_EventLayout> _layoutEvents(List<CalendaEventAdapter> events) {
    if (events.isEmpty) return [];

    final sorted = List<CalendaEventAdapter>.from(events)
      ..sort((a, b) {
        final cmp = a.start.compareTo(b.start);
        if (cmp != 0) return cmp;
        return b.end.compareTo(a.end);
      });

    final columns = <List<_EventLayout>>[];
    final layouts = <_EventLayout>[];

    for (final event in sorted) {
      final startMinutes = event.start.hour * 60.0 + event.start.minute;
      var placed = false;

      for (var col = 0; col < columns.length; col++) {
        final lastInCol = columns[col].last;
        if (startMinutes >= lastInCol.endMinutes) {
          columns[col].add(
            _EventLayout(
              event: event,
              top: startMinutes / 60.0 * _hourHeight,
              height: _eventHeight(event),
              left: 0,
              width: 0,
              endMinutes: event.end.hour * 60.0 + event.end.minute,
              column: col,
            ),
          );
          placed = true;
          break;
        }
      }

      if (!placed) {
        columns.add([
          _EventLayout(
            event: event,
            top: startMinutes / 60.0 * _hourHeight,
            height: _eventHeight(event),
            left: 0,
            width: 0,
            endMinutes: event.end.hour * 60.0 + event.end.minute,
            column: columns.length,
          ),
        ]);
      }
    }

    final totalColumns = columns.length;
    for (final col in columns) {
      for (final layout in col) {
        final w = 1.0 / totalColumns;
        layouts.add(
          _EventLayout(
            event: layout.event,
            top: layout.top,
            height: layout.height,
            left: layout.column * w,
            width: w,
            endMinutes: layout.endMinutes,
            column: layout.column,
          ),
        );
      }
    }

    return layouts;
  }

  double _eventHeight(CalendaEventAdapter event) {
    final duration =
        event.end.difference(event.start).inMinutes.clamp(20, 24 * 60);
    return (duration / 60.0 * _hourHeight).clamp(20.0, double.infinity);
  }

  static DateTime _dateOnly(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }
}

class _EventLayout {
  final CalendaEventAdapter event;
  final double top;
  final double height;
  final double left;
  final double width;
  final double endMinutes;
  final int column;

  _EventLayout({
    required this.event,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    required this.endMinutes,
    required this.column,
  });
}
