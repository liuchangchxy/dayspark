import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/ui/widgets/calendar/scrollable_page.dart';
import 'package:dayspark/core/utils/date_formatters.dart';

class DayCalendarView extends StatefulWidget {
  final DateTime anchorDate;
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter)? onEventTapped;
  final void Function(DateTime datetime)? onTimeSlotTapped;
  final void Function(DateTime newAnchor)? onPageChanged;
  final void Function(CalendaEventAdapter event, DateTime newStart)? onEventChanged;

  const DayCalendarView({
    super.key,
    required this.anchorDate,
    this.events = const [],
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onPageChanged,
    this.onEventChanged,
  });

  @override
  State<DayCalendarView> createState() => _DayCalendarViewState();
}

class _DayCalendarViewState extends State<DayCalendarView> {
  static const double _hourHeight = 48.0;
  static const double _timelineWidth = 48.0;
  static const int _totalDays = 20000;
  static const int _epochDay = 10000;
  static const Duration _scrollTarget = Duration(hours: 8);

  late PageController _pageController;
  bool _isAnimating = false;
  final _columnKey = GlobalKey();

  bool get _isDesktop => defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _dayToIndex(widget.anchorDate),
    );
  }

  @override
  void didUpdateWidget(covariant DayCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _dayToIndex(oldWidget.anchorDate);
    final newIndex = _dayToIndex(widget.anchorDate);
    if (oldIndex != newIndex && _pageController.hasClients) {
      final currentPage =
          _pageController.page?.round() ?? oldIndex;
      if (currentPage != newIndex) {
        _isAnimating = true;
        _pageController.animateToPage(
          newIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ).whenComplete(() {
          if (mounted) _isAnimating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return widget.events.where((e) {
      if (e.isAllDay) return false;
      return e.start.isBefore(dayEnd) && e.end.isAfter(dayStart);
    }).toList();
  }

  List<CalendaEventAdapter> _allDayEvents(DateTime date) {
    return widget.events.where((e) {
      if (!e.isAllDay) return false;
      final s = DateTime(e.start.year, e.start.month, e.start.day);
      final end = DateTime(e.end.year, e.end.month, e.end.day);
      return !s.isAfter(date) && !end.isBefore(date);
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
              if (!_isAnimating) {
                widget.onPageChanged?.call(_indexToDay(index));
              }
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
                    borderRadius: BorderRadius.circular(6),
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

    return Stack(
      children: [
        CalendarScrollablePage(
          targetOffset: _scrollTarget.inMinutes / 60.0 * _hourHeight,
          totalHeight: totalHeight,
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
        _buildNowIndicator(theme, date, totalHeight),
      ],
    );
  }

  Widget _buildNowIndicator(ThemeData theme, DateTime date, double totalHeight) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    if (_dateOnly(date) != today) return const SizedBox.shrink();

    final top = (now.hour + now.minute / 60) * _hourHeight;
    return Positioned(
      top: top,
      left: _timelineWidth,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.colorScheme.error,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(height: 2, color: theme.colorScheme.error),
          ),
        ],
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

  Widget _buildDraggableEvent({
    required CalendaEventAdapter event,
    required Widget feedback,
    required Widget childWhenDragging,
    required Widget child,
  }) {
    if (_isDesktop) {
      return Draggable<CalendaEventAdapter>(
        data: event,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: child,
      );
    }
    return LongPressDraggable<CalendaEventAdapter>(
      data: event,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }

  Widget _buildEventColumn(
    ThemeData theme,
    DateTime date,
    List<CalendaEventAdapter> events,
    double totalHeight,
  ) {
    return DragTarget<CalendaEventAdapter>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final offset = details.offset;
        final renderBox =
            _columnKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final local = renderBox.globalToLocal(offset);
        final newHour = (local.dy / _hourHeight).clamp(0.0, 23.5);
        final newStart = DateTime(
          date.year,
          date.month,
          date.day,
          newHour.floor(),
          ((newHour % 1) * 60).round(),
        );
        widget.onEventChanged?.call(details.data, newStart);
      },
      builder: (context, candidateData, rejectedData) {
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
            key: _columnKey,
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
                ..._layoutEvents(events, date).map((entry) {
                  final canDrag = entry.event.rrule == null && !entry.event.isAllDay;
                  return Positioned(
                    top: entry.top,
                    left: entry.left,
                    width: entry.width,
                    height: entry.height,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: canDrag
                          ? _buildDraggableEvent(
                              event: entry.event,
                              feedback: Opacity(
                                opacity: 0.7,
                                child: SizedBox(
                                  width: entry.width,
                                  child: EventTile(event: entry.event),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: EventTile(event: entry.event),
                              ),
                              child: GestureDetector(
                                onTap: () =>
                                    widget.onEventTapped?.call(entry.event),
                                child: EventTile(event: entry.event),
                              ),
                            )
                          : GestureDetector(
                              onTap: () =>
                                  widget.onEventTapped?.call(entry.event),
                              child: EventTile(event: entry.event),
                            ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_EventLayout> _layoutEvents(List<CalendaEventAdapter> events, DateTime date) {
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
      final eventStartDate = _dateOnly(event.start);
      final eventEndDate = _dateOnly(event.end);
      final startMinutes = eventStartDate.isBefore(date)
          ? 0.0
          : event.start.hour * 60.0 + event.start.minute;
      final endMinutes = eventEndDate.isAfter(date)
          ? 24.0 * 60.0
          : event.end.hour * 60.0 + event.end.minute;
      var placed = false;

      for (var col = 0; col < columns.length; col++) {
        final lastInCol = columns[col].last;
        if (startMinutes >= lastInCol.endMinutes) {
          columns[col].add(
            _EventLayout(
              event: event,
              top: startMinutes / 60.0 * _hourHeight,
              height: _eventHeight(event, date),
              left: 0,
              width: 0,
              endMinutes: endMinutes,
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
            height: _eventHeight(event, date),
            left: 0,
            width: 0,
            endMinutes: endMinutes,
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

  double _eventHeight(CalendaEventAdapter event, DateTime date) {
    final eventStartDate = _dateOnly(event.start);
    final eventEndDate = _dateOnly(event.end);
    final startMinutes = eventStartDate.isBefore(date)
        ? 0.0
        : event.start.hour * 60.0 + event.start.minute;
    final endMinutes = eventEndDate.isAfter(date)
        ? 24.0 * 60.0
        : event.end.hour * 60.0 + event.end.minute;
    final duration = (endMinutes - startMinutes).clamp(20, 24 * 60);
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
