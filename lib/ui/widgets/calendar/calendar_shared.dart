import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';

DateTime calDayOf(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool calSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime calWeekStart(DateTime value) {
  final day = calDayOf(value);
  return day.subtract(Duration(days: day.weekday - 1));
}

String calWeekdayShort(String locale, DateTime date) {
  final full = DateFormat.E(locale).format(date);
  if (locale.startsWith('zh') && full.isNotEmpty) {
    return full.substring(full.length - 1);
  }
  return full;
}

String calDuration(AppLocalizations l, Duration duration) {
  final minutes = duration.inMinutes;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours > 0 && rest > 0) return l.durationHoursMinutes(hours, rest);
  if (hours > 0) return l.durationHours(hours);
  return l.durationMinutes(rest);
}

String calTimeRange(DateTime start, DateTime end) =>
    '${DateFormatters.formatTime(start)} – '
    '${DateFormatters.formatTime(end)}';

class CalBlockItem {
  CalBlockItem.event(this.event) : allocation = null;

  CalBlockItem.allocation(this.allocation) : event = null;

  final CalendaEventAdapter? event;
  final TaskAllocationCalendarAdapter? allocation;

  DateTime get start => event?.start ?? allocation!.start;
  DateTime get end => event?.end ?? allocation!.end;
  String get title => event?.title ?? allocation!.todoTitle;
  Color? get color => event?.color;
  bool get isAllocation => allocation != null;
  bool get isAllDay => event?.isAllDay ?? false;

  bool get canDrag {
    final value = event;
    if (value == null) return true;
    return value.rrule == null &&
        !value.isRecurringOccurrence &&
        !value.isAllDay;
  }
}

List<CalBlockItem> calDayBlocks({
  required DateTime day,
  required List<CalendaEventAdapter> events,
  required List<TaskAllocationCalendarAdapter> allocations,
}) {
  final items =
      <CalBlockItem>[
        for (final event in events)
          if (!event.isAllDay &&
              calSameDay(event.start, event.end) &&
              calSameDay(event.start, day))
            CalBlockItem.event(event),
        for (final allocation in allocations)
          if (calSameDay(allocation.start, day))
            CalBlockItem.allocation(allocation),
      ]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });
  return items;
}

List<CalendaEventAdapter> calAllDayEvents({
  required DateTime day,
  required List<CalendaEventAdapter> events,
}) {
  return [
    for (final event in events)
      if (_spansDay(event, day)) event,
  ]..sort((a, b) {
    if (a.isAllDay != b.isAllDay) return a.isAllDay ? -1 : 1;
    return a.start.compareTo(b.start);
  });
}

bool _spansDay(CalendaEventAdapter event, DateTime day) {
  final target = calDayOf(day);
  final startDay = calDayOf(event.start);
  final endDay = event.end.isAfter(event.start)
      ? calDayOf(event.end.subtract(const Duration(minutes: 1)))
      : startDay;
  final multiDay = !calSameDay(event.start, event.end);
  if (!event.isAllDay && !multiDay) return false;
  return !target.isBefore(startDay) && !target.isAfter(endDay);
}

class CalLane {
  const CalLane(this.lane, this.lanes);

  final int lane;
  final int lanes;
}

List<CalLane> calPackLanes(List<CalBlockItem> items) {
  final result = List<CalLane>.filled(items.length, const CalLane(0, 1));
  var index = 0;
  while (index < items.length) {
    final cluster = <int>[index];
    var clusterEnd = items[index].end;
    var next = index + 1;
    while (next < items.length && items[next].start.isBefore(clusterEnd)) {
      cluster.add(next);
      if (items[next].end.isAfter(clusterEnd)) {
        clusterEnd = items[next].end;
      }
      next++;
    }
    final laneEnds = <DateTime>[];
    final laneIndexes = <int>[];
    for (final itemIndex in cluster) {
      var lane = laneEnds.indexWhere(
        (end) => !end.isAfter(items[itemIndex].start),
      );
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(items[itemIndex].end);
      } else {
        laneEnds[lane] = items[itemIndex].end;
      }
      laneIndexes.add(lane);
    }
    for (var i = 0; i < cluster.length; i++) {
      result[cluster[i]] = CalLane(laneIndexes[i], laneEnds.length);
    }
    index = next;
  }
  return result;
}

class CalGap {
  const CalGap(this.start, this.end);

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

List<CalGap> calFreeGaps({
  required DateTime day,
  required List<CalBlockItem> items,
  required int startHour,
  required int endHour,
  Duration minGap = const Duration(minutes: 30),
}) {
  final windowStart = DateTime(day.year, day.month, day.day, startHour);
  final windowEnd = DateTime(day.year, day.month, day.day, endHour);
  final intervals = <({DateTime start, DateTime end})>[];
  for (final item in items) {
    final start = item.start.isBefore(windowStart) ? windowStart : item.start;
    final end = item.end.isAfter(windowEnd) ? windowEnd : item.end;
    if (end.isAfter(start)) intervals.add((start: start, end: end));
  }
  intervals.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({DateTime start, DateTime end})>[];
  for (final interval in intervals) {
    if (merged.isEmpty || !interval.start.isBefore(merged.last.end)) {
      merged.add(interval);
    } else if (interval.end.isAfter(merged.last.end)) {
      merged[merged.length - 1] = (start: merged.last.start, end: interval.end);
    }
  }
  final gaps = <CalGap>[];
  for (var i = 1; i < merged.length; i++) {
    final start = merged[i - 1].end;
    final end = merged[i].start;
    if (end.difference(start) >= minGap) gaps.add(CalGap(start, end));
  }
  return gaps;
}

class CalEdgeBox extends StatelessWidget {
  const CalEdgeBox({
    super.key,
    required this.edgeColor,
    required this.child,
    this.background,
    this.radius = 6,
    this.edgeWidth = 3,
    this.padding = EdgeInsets.zero,
  });

  final Color edgeColor;
  final Color? background;
  final double radius;
  final double edgeWidth;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: edgeWidth,
            child: ColoredBox(color: edgeColor),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class CalBlockTile extends StatefulWidget {
  const CalBlockTile({
    super.key,
    required this.item,
    required this.color,
    required this.hourHeight,
    required this.now,
    required this.onTap,
    this.onReschedule,
    this.mobile = false,
    this.visualHeight,
  });

  final CalBlockItem item;
  final Color color;
  final double hourHeight;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<int>? onReschedule;
  final bool mobile;
  final double? visualHeight;

  @override
  State<CalBlockTile> createState() => _CalBlockTileState();
}

class _CalBlockTileState extends State<CalBlockTile> {
  double _dragDy = 0;

  bool get _canDrag => widget.onReschedule != null && widget.item.canDrag;

  void _finishDrag() {
    final minutes = (_dragDy / widget.hourHeight * 60).round();
    setState(() => _dragDy = 0);
    final snapped = (minutes / 30).round() * 30;
    if (snapped != 0) widget.onReschedule!(snapped);
  }

  String _meta(AppLocalizations l) {
    final item = widget.item;
    if (item.isAllocation) return l.scheduledLabel;
    final location = item.event?.location;
    if (location != null && location.isNotEmpty) return location;
    return calDuration(l, item.end.difference(item.start));
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final item = widget.item;
    final now = widget.now;
    final inProgress =
        !item.isAllocation && now.isAfter(item.start) && now.isBefore(item.end);
    final remaining = inProgress
        ? l.remainingMinutes(item.end.difference(now).inMinutes)
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: _canDrag ? (_) => setState(() => _dragDy = 0) : null,
        onLongPressMoveUpdate: _canDrag
            ? (details) => setState(() => _dragDy = details.offsetFromOrigin.dy)
            : null,
        onLongPressEnd: _canDrag ? (_) => _finishDrag() : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentHeight = widget.visualHeight ?? constraints.maxHeight;
            return Transform.translate(
              offset: Offset(0, _dragDy),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: contentHeight,
                  width: constraints.maxWidth,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: item.isAllocation
                          ? Colors.transparent
                          : ds.tint(widget.color),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: item.isAllocation
                            ? Colors.transparent
                            : ds.lineSoft,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 3,
                          child: ColoredBox(
                            color: item.isAllocation ? ds.ink3 : widget.color,
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: item.isAllocation
                                ? _CalDashedPainter(ds.line)
                                : null,
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final height = constraints.maxHeight;
                            final lineHeight = widget.mobile ? 15.0 : 14.5;
                            final withTime =
                                !widget.mobile &&
                                !item.isAllocation &&
                                height >= 27;
                            final timeHeight = withTime ? 12.5 : 0.0;
                            final metaBlock = widget.mobile
                                ? true
                                : remaining != null || item.isAllocation;
                            final showMeta =
                                metaBlock &&
                                height >=
                                    (widget.mobile
                                        ? lineHeight + 13
                                        : timeHeight + lineHeight + 14.5);
                            final metaHeight = showMeta ? 12.5 : 0.0;
                            // The tile's own 3/2 vertical padding comes out of
                            // the same height, so a block that "fits" two lines
                            // by the arithmetic alone would still have its
                            // second line sliced in half by the clip.
                            final rawLines =
                                (height - timeHeight - metaHeight - 5) /
                                lineHeight;
                            final titleLines = rawLines < 1
                                ? 1
                                : rawLines > 2
                                ? 2
                                : rawLines.floor();
                            return ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: 0,
                                maxWidth: constraints.maxWidth,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    6,
                                    3,
                                    4,
                                    2,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.mobile)
                                        _mobileHead(
                                          l,
                                          item,
                                          showMeta,
                                          remaining,
                                          titleLines,
                                        )
                                      else
                                        _desktopHead(
                                          l,
                                          item,
                                          withTime,
                                          showMeta,
                                          remaining,
                                          titleLines,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _desktopHead(
    AppLocalizations l,
    CalBlockItem item,
    bool showTime,
    bool showMeta,
    String? remaining,
    int titleLines,
  ) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTime && !item.isAllocation)
          Text(
            DateFormatters.formatTime(item.start),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.25,
              color: ds.ink3,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        Text(
          item.title,
          maxLines: titleLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: ds.ink,
          ),
        ),
        if (remaining != null && showMeta)
          Text(
            remaining,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.25,
              color: ds.primary,
              fontFeatures: AppTypography.tabular,
            ),
          )
        else if (item.isAllocation && showMeta)
          Text(
            l.scheduledLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, height: 1.25, color: ds.ink3),
          ),
      ],
    );
  }

  Widget _mobileHead(
    AppLocalizations l,
    CalBlockItem item,
    bool showMeta,
    String? remaining,
    int titleLines,
  ) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: ds.ink,
                ),
              ),
            ),
            if (showMeta) ...[
              const SizedBox(width: 6),
              Text(
                _meta(l),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, height: 1.25, color: ds.ink3),
              ),
            ],
          ],
        ),
        if (remaining != null && showMeta)
          Text(
            remaining,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.25,
              color: ds.primary,
              fontFeatures: AppTypography.tabular,
            ),
          ),
      ],
    );
  }
}

class _CalDashedPainter extends CustomPainter {
  _CalDashedPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CalDashedPainter oldDelegate) =>
      oldDelegate.color != color;
}
