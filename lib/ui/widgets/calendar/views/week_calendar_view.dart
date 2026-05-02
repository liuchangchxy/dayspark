import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';

class WeekCalendarView extends StatefulWidget {
  final DateTime anchorDate;
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter)? onEventTapped;
  final void Function(DateTime datetime)? onTimeSlotTapped;
  final void Function(DateTime newAnchor)? onPageChanged;
  final void Function(CalendaEventAdapter event, DateTime newStart)? onEventChanged;

  const WeekCalendarView({
    super.key,
    required this.anchorDate,
    this.events = const [],
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onPageChanged,
    this.onEventChanged,
  });

  @override
  State<WeekCalendarView> createState() => _WeekCalendarViewState();
}

class _WeekCalendarViewState extends State<WeekCalendarView> {
  static const double _hourHeight = 48.0;
  static const double _timelineWidth = 48.0;
  static const int _totalWeeks = 24000;
  static const int _epochWeek = 12000;
  static const Duration _scrollTarget = Duration(hours: 8);

  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _weekToIndex(widget.anchorDate),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTime();
    });
  }

  @override
  void didUpdateWidget(covariant WeekCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _weekToIndex(oldWidget.anchorDate);
    final newIndex = _weekToIndex(widget.anchorDate);
    if (oldIndex != newIndex && _pageController.hasClients) {
      final currentPage =
          _pageController.page?.round() ?? _weekToIndex(oldWidget.anchorDate);
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

  static int _weekToIndex(DateTime date) {
    final monday = _mondayOfWeek(date);
    final epoch = DateTime(2000, 1, 3);
    final diff = epoch.difference(monday).inDays;
    return diff ~/ 7 + _epochWeek;
  }

  static DateTime _indexToWeek(int index) {
    final epoch = DateTime(2000, 1, 3);
    return epoch.add(Duration(days: (index - _epochWeek) * 7));
  }

  static DateTime _mondayOfWeek(DateTime date) {
    return date.subtract(Duration(days: (date.weekday - 1) % 7));
  }

  List<DateTime> _weekDates(DateTime monday) {
    return List.generate(7, (i) => _dateOnly(monday.add(Duration(days: i))));
  }

  List<CalendaEventAdapter> _eventsForDate(DateTime date) {
    return widget.events.where((e) {
      if (e.isAllDay) return false;
      final s = DateTime(e.start.year, e.start.month, e.start.day);
      final end = DateTime(e.end.year, e.end.month, e.end.day);
      return !s.isAfter(date) && date.isBefore(end);
    }).toList();
  }

  List<CalendaEventAdapter> _allDayEventsForDate(DateTime date) {
    return widget.events.where((e) {
      if (!e.isAllDay) return false;
      final s = DateTime(e.start.year, e.start.month, e.start.day);
      final end = DateTime(e.end.year, e.end.month, e.end.day);
      return !s.isAfter(date) && date.isBefore(end);
    }).toList();
  }

  List<CalendaEventAdapter> _allAllDayEvents(List<DateTime> weekDates) {
    final dates = weekDates.toSet();
    return widget.events.where((e) {
      if (!e.isAllDay) return false;
      final eventDate = DateTime(e.start.year, e.start.month, e.start.day);
      return dates.contains(eventDate);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();

    return Column(
      children: [
        _buildAllDayBar(context, theme, locale),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _totalWeeks,
            scrollDirection: Axis.horizontal,
            onPageChanged: (index) {
              widget.onPageChanged?.call(_indexToWeek(index));
            },
            itemBuilder: (context, index) {
              final monday = _indexToWeek(index);
              return _buildWeekPage(context, theme, locale, monday);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAllDayBar(BuildContext context, ThemeData theme, String locale) {
    return Builder(
      builder: (context) {
        final monday = _mondayOfWeek(widget.anchorDate);
        final weekDates = _weekDates(monday);
        final allDayEvents = _allAllDayEvents(weekDates);
        final rowCount = allDayEvents.isEmpty ? 0 : 1;

        return Column(
          children: [
            _buildDayHeaderRow(theme, locale, weekDates),
            if (rowCount > 0)
              SizedBox(
                height: rowCount * 24.0,
                child: Row(
                  children: [
                    const SizedBox(width: _timelineWidth),
                    ...weekDates.map((date) {
                      final dayEvents = _allDayEventsForDate(date);
                      return Expanded(
                        child: Column(
                          children: dayEvents.take(1).map((e) {
                            return GestureDetector(
                              onTap: () => widget.onEventTapped?.call(e),
                              child: Container(
                                height: 20,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: (e.color ?? theme.colorScheme.primary)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  e.title,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: e.color ?? theme.colorScheme.primary,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDayHeaderRow(ThemeData theme, String locale, List<DateTime> weekDates) {
    final today = _dateOnly(DateTime.now());

    return Row(
      children: [
        const SizedBox(width: _timelineWidth),
        ...weekDates.asMap().entries.map((entry) {
          final date = entry.value;
          final isToday = date == today;
          return Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat.E(locale).format(date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 26,
                  height: 26,
                  decoration: isToday
                      ? BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        )
                      : null,
                  alignment: Alignment.center,
                  child: Text(
                    '${date.day}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isToday
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      fontWeight:
                          isToday ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildWeekPage(
    BuildContext context,
    ThemeData theme,
    String locale,
    DateTime monday,
  ) {
    final weekDates = _weekDates(monday);
    final totalHeight = 24 * _hourHeight;

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          child: SizedBox(
            height: totalHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimeline(theme, totalHeight),
                ...weekDates.map(
                  (date) => Expanded(
                    child: _buildDayColumn(theme, date, totalHeight),
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildNowIndicator(theme, weekDates, totalHeight),
      ],
    );
  }

  Widget _buildNowIndicator(
    ThemeData theme,
    List<DateTime> weekDates,
    double totalHeight,
  ) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    if (!weekDates.contains(today)) return const SizedBox.shrink();

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
            right: 0,
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

  Widget _buildDayColumn(
    ThemeData theme,
    DateTime date,
    double totalHeight,
  ) {
    final events = _eventsForDate(date);

    return DragTarget<CalendaEventAdapter>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final offset = details.offset;
        final renderBox = context.findRenderObject() as RenderBox;
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
                ...events.map((e) {
                  final startMinutes =
                      e.start.hour * 60.0 + e.start.minute;
                  final endMinutes = e.end.hour * 60.0 + e.end.minute;
                  final duration = (endMinutes - startMinutes).clamp(20.0, double.infinity);
                  final top = startMinutes / 60.0 * _hourHeight;
                  final height = (duration / 60.0 * _hourHeight).clamp(20.0, double.infinity);

                  final canDrag = e.rrule == null && !e.isAllDay;
                  return Positioned(
                    top: top,
                    left: 2,
                    right: 2,
                    height: height,
                    child: canDrag
                        ? LongPressDraggable<CalendaEventAdapter>(
                            data: e,
                            feedback: Opacity(
                              opacity: 0.7,
                              child: EventTile(event: e),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: EventTile(event: e),
                            ),
                            child: GestureDetector(
                              onTap: () => widget.onEventTapped?.call(e),
                              child: EventTile(event: e),
                            ),
                          )
                        : GestureDetector(
                            onTap: () => widget.onEventTapped?.call(e),
                            child: EventTile(event: e),
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

  static DateTime _dateOnly(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }
}
