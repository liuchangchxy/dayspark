import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// Direction C's day timeline: the day drawn to scale, not listed.
///
/// One hour is always the same number of pixels, so a three-hour block looks
/// three times as long as a one-hour block, the empty stretches between them
/// are visible as bands, and the now-line falls where the clock actually is.
/// Everything the day contains is one of three things: an event, a task the
/// user allocated time to, or nothing.
class CDayTimeline extends StatelessWidget {
  const CDayTimeline({
    super.key,
    required this.day,
    required this.now,
    required this.events,
    required this.allocations,
    this.onEventTap,
    this.onAllocationTap,
  });

  final DateTime day;
  final DateTime now;
  final List<CalendaEventAdapter> events;
  final List<TaskAllocationCalendarItem> allocations;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(TaskAllocationCalendarItem item)? onAllocationTap;

  static const int baseStartHour = 7;
  static const int baseEndHour = 22;
  static const double axisWidth = 52;
  static const double gutterWidth = 46;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final blocks = _collect(context, l, ds.work);
    final (startHour, endHour) = _window(blocks, now);

    final dayStart = DateTime(day.year, day.month, day.day, startHour);
    final dayEnd = DateTime(day.year, day.month, day.day, endHour);
    final gaps = _gaps(blocks, dayStart, dayEnd);
    _layoutColumns(blocks);
    final isToday = _sameDay(day, now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minutes = (endHour - startHour) * 60;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : minutes * 0.9;
        final pxPerMinute = height / minutes;
        double top(DateTime t) =>
            t.difference(dayStart).inMinutes * pxPerMinute;
        // The stack sits to the right of the axis column, so the columns have
        // to be measured against what is left after both the axis and the
        // gutter, or blocks run past the hour lines.
        final usable = (constraints.maxWidth - axisWidth - gutterWidth).clamp(
          0.0,
          double.infinity,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: axisWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var h = startHour; h <= endHour; h++)
                    Positioned(
                      top: h == startHour
                          ? 0
                          : h == endHour
                          ? (h - startHour) * 60 * pxPerMinute - 11
                          : (h - startHour) * 60 * pxPerMinute - 6,
                      right: 10,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: AppTypography.small.copyWith(
                          color: ds.ink3,
                          height: 1,
                          fontFeatures: AppTypography.tabular,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var h = startHour; h <= endHour; h++)
                    Positioned(
                      left: 0,
                      right: gutterWidth,
                      top: (h - startHour) * 60 * pxPerMinute,
                      child: Container(height: 1, color: ds.line),
                    ),
                  for (var h = startHour; h < endHour; h++)
                    Positioned(
                      left: 0,
                      right: gutterWidth,
                      top: ((h - startHour) * 60 + 30) * pxPerMinute,
                      child: Container(height: 1, color: ds.lineSoft),
                    ),
                  for (final gap in gaps)
                    _GapBand(
                      top: top(gap.start),
                      height: gap.minutes * pxPerMinute,
                      label: l.freeFor(_span(l, gap.start, gap.end)),
                      range:
                          '${DateFormatters.formatTime(gap.start)} – ${DateFormatters.formatTime(gap.end)}',
                      hideLabel: blocks.isEmpty,
                    ),
                  // A whole free day is one long band, which on its own reads
                  // as an empty grid rather than as a day with room in it.
                  if (blocks.isEmpty)
                    Positioned(
                      left: 0,
                      right: gutterWidth,
                      top: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Center(
                          child: Text(
                            l.actionEmptyDay,
                            style: AppTypography.small.copyWith(
                              color: ds.ink3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Under the blocks: the line should never cut through text.
                  // What is happening now reads from the block's own fill, the
                  // pill on the gutter and the stretches of empty day.
                  if (isToday && now.isAfter(dayStart) && now.isBefore(dayEnd))
                    Positioned(
                      left: 0,
                      right: 0,
                      top: top(now),
                      child: _NowLine(
                        time: DateFormatters.formatTime(now),
                        gutterWidth: gutterWidth,
                      ),
                    ),
                  for (final block in blocks)
                    _Block(
                      top: top(block.start),
                      height: block.minutes * pxPerMinute,
                      left: usable * block.col / block.columns,
                      width:
                          usable / block.columns - (block.columns > 1 ? 4 : 0),
                      block: block,
                      now: now,
                      onTap: block.event != null
                          ? () => onEventTap?.call(block.event!)
                          : block.allocation != null
                          ? () => onAllocationTap?.call(block.allocation!)
                          : null,
                    ),
                  Positioned(
                    right: gutterWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: ds.line),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  (int, int) _window(List<_BlockData> blocks, DateTime now) {
    var start = baseStartHour;
    var end = baseEndHour;
    for (final block in blocks) {
      if (block.start.hour < start) start = block.start.hour;
      if (block.end.hour >= end) {
        end = block.end.minute > 0 ? block.end.hour + 1 : block.end.hour;
      }
    }
    if (_sameDay(now, day)) {
      if (now.hour < start) start = now.hour;
      if (now.hour + 1 > end) end = now.hour + 1;
    }
    return (start.clamp(0, 23), end.clamp(start + 1, 24));
  }

  void _layoutColumns(List<_BlockData> blocks) {
    var cluster = <_BlockData>[];
    DateTime? clusterEnd;
    void flush() {
      if (cluster.isEmpty) return;
      final count =
          cluster.map((b) => b.col).reduce((a, b) => a > b ? a : b) + 1;
      for (final block in cluster) {
        block.columns = count;
      }
      cluster = <_BlockData>[];
      clusterEnd = null;
    }

    for (final block in blocks) {
      // Only a real overlap shares columns. Blocks that merely touch (this one
      // starts exactly when the last ended) are a sequence, not a conflict, and
      // stretching them into a half-width column reads as a gap that isn't
      // there.
      final end = clusterEnd;
      if (end != null && !block.start.isBefore(end)) flush();
      var col = 0;
      while (cluster.any(
        (other) => other.col == col && other.end.isAfter(block.start),
      )) {
        col++;
      }
      block.col = col;
      cluster.add(block);
      final current = clusterEnd;
      if (current == null || block.end.isAfter(current)) {
        clusterEnd = block.end;
      }
    }
    flush();
  }

  List<_BlockData> _collect(
    BuildContext context,
    AppLocalizations l,
    Color workColor,
  ) {
    final out = <_BlockData>[];
    for (final event in events) {
      if (event.isAllDay) continue;
      out.add(
        _BlockData(
          start: event.start,
          end: event.end,
          title: event.title,
          meta: _metaFor(l, event),
          tag: null,
          color: event.color ?? workColor,
          done: false,
          event: event,
        ),
      );
    }
    for (final item in allocations) {
      final start = item.allocation.startAt.toLocal();
      final end = item.allocation.endAt.toLocal();
      final due = item.todo.dueDate?.toLocal();
      out.add(
        _BlockData(
          start: start,
          end: end,
          title: item.todo.summary,
          meta: due == null
              ? _span(l, start, end)
              : '${_span(l, start, end)} · '
                    '${l.deadlinePrefix(formatDeadline(context, due))}',
          tag: null,
          color: workColor,
          done: item.allocation.state == 'completed',
          allocation: item,
        ),
      );
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  String _metaFor(AppLocalizations l, CalendaEventAdapter event) {
    final parts = <String>[];
    if (event.location != null && event.location!.trim().isNotEmpty) {
      parts.add(event.location!.trim());
    }
    parts.add(_span(l, event.start, event.end));
    return parts.join(' · ');
  }

  List<_Gap> _gaps(
    List<_BlockData> blocks,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    final out = <_Gap>[];
    var cursor = dayStart;
    for (final block in blocks) {
      if (block.start.isAfter(cursor)) {
        final minutes = block.start.difference(cursor).inMinutes;
        if (minutes >= 15) {
          out.add(_Gap(start: cursor, end: block.start, minutes: minutes));
        }
      }
      if (block.end.isAfter(cursor)) cursor = block.end;
    }
    // The day does not end with the last block. Without the tail the timeline
    // of an empty day is a bare grid with nothing on it, and every other day
    // loses the stretch after its last appointment.
    if (dayEnd.isAfter(cursor)) {
      final minutes = dayEnd.difference(cursor).inMinutes;
      if (minutes >= 15) {
        out.add(_Gap(start: cursor, end: dayEnd, minutes: minutes));
      }
    }
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

String _span(AppLocalizations l, DateTime start, DateTime end) {
  final minutes = end.difference(start).inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return l.durationMinutes(m);
  if (m == 0) return l.durationHours(h);
  return l.durationHoursMinutes(h, m);
}

class _Gap {
  const _Gap({required this.start, required this.end, required this.minutes});

  final DateTime start;
  final DateTime end;
  final int minutes;
}

class _BlockData {
  _BlockData({
    required this.start,
    required this.end,
    required this.title,
    required this.meta,
    required this.tag,
    required this.color,
    required this.done,
    this.event,
    this.allocation,
  });

  final DateTime start;
  final DateTime end;
  final String title;
  final String meta;
  final String? tag;
  final Color color;
  final bool done;
  final CalendaEventAdapter? event;
  final TaskAllocationCalendarItem? allocation;

  int col = 0;
  int columns = 1;

  int get minutes => end.difference(start).inMinutes;
}

class _GapBand extends StatelessWidget {
  const _GapBand({
    required this.top,
    required this.height,
    required this.label,
    required this.range,
    this.hideLabel = false,
  });

  final double top;
  final double height;
  final String label;
  final String range;

  /// A whole free day is announced by its own line; the band underneath it
  /// would otherwise repeat "free for 15 hours" two centimetres away.
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final showText = height >= 22 && !hideLabel;
    return Positioned(
      left: 0,
      right: CDayTimeline.gutterWidth,
      top: top,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: ds.free,
          border: Border(
            top: BorderSide(color: ds.line),
            bottom: BorderSide(color: ds.line),
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: height >= 80 ? 6 : 0,
        ),
        // A short gap reads best centred; a long one centred puts its label in
        // the middle of the afternoon, where the now-line also is.
        alignment: height >= 80 ? Alignment.topLeft : Alignment.centerLeft,
        child: showText
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 260;
                  return Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ds.faint),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.small.copyWith(color: ds.ink2),
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            range,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.small.copyWith(
                              color: ds.faint,
                              fontFeatures: AppTypography.tabular,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              )
            : null,
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    required this.block,
    required this.now,
    this.onTap,
  });

  final double top;
  final double height;
  final double left;
  final double width;
  final _BlockData block;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final running =
        !block.done && !now.isBefore(block.start) && now.isBefore(block.end);
    final bg = block.done ? ds.doneBg : ds.tint(block.color);
    final border = block.done ? ds.doneLine : ds.line;
    final edge = running
        ? ds.primary
        : block.done
        ? ds.doneInk
        : block.color;
    final remaining = block.end.difference(now).inMinutes;
    final elapsed = running && block.minutes > 0
        ? (now.difference(block.start).inSeconds /
                  block.end.difference(block.start).inSeconds)
              .clamp(0.0, 1.0)
        : 0.0;
    // A 25-minute block still has to say what it is: a nameless bar reads as a
    // rendering fault. Tight blocks drop to a single centred line instead.
    final textTop = height >= 34 ? 3.0 : 2.0;
    final available = height - textTop - 2;
    final showTitle = available >= 11;
    final showMeta = available >= 31 && block.meta.isNotEmpty;
    final showRemaining = running && available >= 52;
    return Positioned(
      left: left,
      width: width,
      top: top,
      height: height,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: running ? ds.primaryTint : bg,
                      border: Border.all(
                        color: running ? ds.primarySoft : border,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                if (running)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: height * elapsed,
                    child: ColoredBox(
                      color: ds.primary.withValues(alpha: 0.09),
                    ),
                  ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: edge),
                ),
                if (showTitle)
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, textTop, 8, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (block.done) ...[
                              const _CheckMark(size: 9),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                block.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.small.copyWith(
                                  color: block.done ? ds.doneInk : ds.ink,
                                  fontWeight: FontWeight.w600,
                                  height: showMeta ? 15 / 12 : 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (showMeta)
                          Text(
                            block.meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.small.copyWith(
                              color: running
                                  ? ds.primaryHover
                                  : block.done
                                  ? ds.doneInk
                                  : ds.ink3,
                              height: 14 / 12,
                            ),
                          ),
                        if (showRemaining)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              l.remainingMinutes(remaining < 0 ? 0 : remaining),
                              style: AppTypography.small.copyWith(
                                color: ds.primary,
                                fontWeight: FontWeight.w500,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 2,
      height: size,
      child: CustomPaint(painter: _CheckPainter(context.ds.doneInk)),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..lineTo(size.width * 0.38, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.time, required this.gutterWidth});

  final String time;
  final double gutterWidth;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return SizedBox(
      height: 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(height: 2, color: ds.primary),
          ),
          Positioned(
            left: -4,
            top: -4,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: ds.primary,
                shape: BoxShape.circle,
                border: Border.all(color: ds.bg, width: 2),
              ),
            ),
          ),
          Positioned(
            right: 1,
            top: -9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: ds.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                time,
                style: AppTypography.small.copyWith(
                  color: ds.onPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
