import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/date_context_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_month_view.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_week_view.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

final calendarNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class CalendarSection extends ConsumerStatefulWidget {
  const CalendarSection({
    super.key,
    required this.events,
    this.deadlines = const [],
    this.onDeadlineTapped,
    this.allocations = const [],
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onEventChanged,
    this.onTaskAllocationTapped,
    this.onTaskAllocationChanged,
    this.onAnchorChanged,
    this.hideHeader = false,
    this.onHeaderChanged,
  });

  final List<CalendaEventAdapter> events;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<CalendarDeadline>? onDeadlineTapped;
  final List<TaskAllocationCalendarAdapter> allocations;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;
  final Future<void> Function(CalendaEventAdapter event)? onEventChanged;
  final void Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationTapped;
  final Future<void> Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationChanged;
  final void Function(DateTime anchor)? onAnchorChanged;
  final bool hideHeader;
  final void Function(String title, String? subtitle)? onHeaderChanged;

  @override
  ConsumerState<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<CalendarSection> {
  String? _lastTitle;
  String? _lastSubtitle;

  CalendarViewMode get _mode => ref.watch(calendarViewModeProvider);

  DateTime get _anchor {
    final viewed = ref.watch(browseDateProvider);
    return DateTime(viewed.year, viewed.month, viewed.day);
  }

  DateTime get _now => ref.watch(calendarNowProvider)();

  DateTime get _weekStart => calWeekStart(_anchor);

  void _setAnchor(DateTime next) {
    final date = calDayOf(next);
    if (date == _anchor) return;
    ref.read(browseDateProvider.notifier).state = date;
    widget.onAnchorChanged?.call(date);
  }

  void _shift(int direction) {
    switch (_mode) {
      case CalendarViewMode.day:
        _setAnchor(_anchor.add(Duration(days: direction)));
      case CalendarViewMode.week:
        _setAnchor(_anchor.add(Duration(days: 7 * direction)));
      case CalendarViewMode.month:
        _setAnchor(DateTime(_anchor.year, _anchor.month + direction, 1));
    }
  }

  void _goToToday() {
    final now = _now;
    _setAnchor(DateTime(now.year, now.month, now.day));
  }

  void _openDay(DateTime day) {
    _setAnchor(day);
    ref.read(calendarViewModeProvider.notifier).setViewMode(
      CalendarViewMode.day,
    );
  }

  bool get _viewingToday {
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    switch (_mode) {
      case CalendarViewMode.day:
        return _anchor == today;
      case CalendarViewMode.week:
        final start = _weekStart;
        return !today.isBefore(start) &&
            today.isBefore(start.add(const Duration(days: 7)));
      case CalendarViewMode.month:
        return _anchor.year == today.year && _anchor.month == today.month;
    }
  }

  String _title(AppLocalizations l) {
    final locale = Localizations.localeOf(context).toString();
    switch (_mode) {
      case CalendarViewMode.day:
        return DateFormat.MMMMEEEEd(locale).format(_anchor);
      case CalendarViewMode.week:
        final end = _weekStart.add(const Duration(days: 6));
        return '${DateFormat.MMMd(locale).format(_weekStart)} – '
            '${DateFormat.MMMd(locale).format(end)}';
      case CalendarViewMode.month:
        return DateFormat.yMMMM(locale).format(_anchor);
    }
  }

  (DateTime, DateTime) _visibleRange() {
    switch (_mode) {
      case CalendarViewMode.day:
        return (_anchor, _anchor.add(const Duration(days: 1)));
      case CalendarViewMode.week:
        return (_weekStart, _weekStart.add(const Duration(days: 7)));
      case CalendarViewMode.month:
        final first = DateTime(_anchor.year, _anchor.month);
        return (first, DateTime(_anchor.year, _anchor.month + 1));
    }
  }

  String? _secondaryTitle(AppLocalizations l) {
    if (_mode == CalendarViewMode.month) return null;
    final (start, end) = _visibleRange();
    final count = widget.events
        .where((event) => !event.start.isBefore(start) && event.start.isBefore(end))
        .length;
    return l.eventsAndFree(count);
  }

  /// Whether the days on screen hold nothing at all. [widget.events] covers a
  /// wide window around the anchor, so `events.isEmpty` stays false as long as
  /// anything at all is scheduled that season; the view's own range is the only
  /// honest question to ask.
  bool get _visibleEmpty {
    final (start, end) = _visibleRange();
    bool overlaps(DateTime from, DateTime to) =>
        from.isBefore(end) && to.isAfter(start);
    return !widget.events.any((event) => overlaps(event.start, event.end)) &&
        !widget.allocations.any(
          (allocation) => overlaps(allocation.start, allocation.end),
        ) &&
        !widget.deadlines.any(
          (deadline) => !deadline.due.isBefore(start) && deadline.due.isBefore(end),
        );
  }

  void _emitHeader() {
    final title = _title(AppLocalizations.of(context)!);
    final locale = Localizations.localeOf(context).toString();
    final subtitle = switch (_mode) {
      CalendarViewMode.day || CalendarViewMode.week =>
        '${DateFormat.Md(locale).format(_anchor)} · '
            '${DateFormat.E(locale).format(_anchor)}',
      CalendarViewMode.month => '${_anchor.month}/${_anchor.year}',
    };
    if (title == _lastTitle && subtitle == _lastSubtitle) return;
    _lastTitle = title;
    _lastSubtitle = subtitle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHeaderChanged?.call(title, subtitle);
    });
  }

  Future<void> _reschedule(CalBlockItem item, int minutes) async {
    if (minutes == 0) return;
    final shift = Duration(minutes: minutes);
    final l = AppLocalizations.of(context)!;
    try {
      if (item.event != null) {
        final event = item.event!;
        final handler = widget.onEventChanged;
        if (handler == null) return;
        await handler(
          event.copyWithData(
            start: event.start.add(shift),
            end: event.end.add(shift),
          ),
        );
      } else {
        final allocation = item.allocation!;
        final handler = widget.onTaskAllocationChanged;
        if (handler == null) return;
        await handler(
          allocation.copyWith(
            start: allocation.start.add(shift),
            end: allocation.end.add(shift),
          ),
        );
      }
    } on Object catch (error) {
      debugPrint('calendar: reschedule failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    _emitHeader();
    final mode = _mode;
    final anchor = _anchor;
    final now = _now;

    final content = switch (mode) {
      CalendarViewMode.month => desktop
          ? CalendarMonthView(
              anchor: anchor,
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              now: now,
              onSelectDay: _setAnchor,
              onOpenDay: _openDay,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onSlot: widget.onTimeSlotTapped,
            )
          : CalendarMobileMonthView(
              anchor: anchor,
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              now: now,
              onSelectDay: _setAnchor,
              onOpenDay: _openDay,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
            ),
      CalendarViewMode.week => desktop
          ? CalendarWeekGrid(
              days: [
                for (var i = 0; i < 7; i++)
                  _weekStart.add(Duration(days: i)),
              ],
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              now: now,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onSlot: widget.onTimeSlotTapped,
              onReschedule: _reschedule,
            )
          : CalendarMobileWeekView(
              weekStart: _weekStart,
              selected: anchor,
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              now: now,
              onSelectDay: _setAnchor,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onSlot: widget.onTimeSlotTapped,
              onReschedule: _reschedule,
            ),
      CalendarViewMode.day => desktop
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: CalendarWeekGrid(
                  days: [anchor],
                  events: widget.events,
                  allocations: widget.allocations,
                  deadlines: widget.deadlines,
                  now: now,
                  onEvent: widget.onEventTapped,
                  onAllocation: widget.onTaskAllocationTapped,
                  onDeadline: widget.onDeadlineTapped,
                  onSlot: widget.onTimeSlotTapped,
                  onReschedule: _reschedule,
                ),
              ),
            )
          : CalendarMobileDayView(
              day: anchor,
              events: widget.events,
              allocations: widget.allocations,
              deadlines: widget.deadlines,
              now: now,
              onSelectDay: _setAnchor,
              onEvent: widget.onEventTapped,
              onAllocation: widget.onTaskAllocationTapped,
              onDeadline: widget.onDeadlineTapped,
              onSlot: widget.onTimeSlotTapped,
              onReschedule: _reschedule,
            ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        desktop
            ? _desktopToolbar(l)
            : _mobileToolbar(l),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              // An empty calendar used to be a bare grid with no affordance,
              // which reads as broken rather than as a week with nothing on it.
              // A month grid already shows every day, so it speaks for itself.
              if (_visibleEmpty && mode != CalendarViewMode.month)
                Positioned.fill(
                  child: IgnorePointer(
                    // Taps fall through to the grid, which is how the empty
                    // state gets used: point at a slot and it becomes an event.
                    child: Align(
                      alignment: const Alignment(0, -0.2),
                      child: Text(
                        l.emptyCalendarHint,
                        textAlign: TextAlign.center,
                        style: AppTypography.small.copyWith(
                          color: context.ds.ink3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktopToolbar(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.s1,
        bottom: AppSpacing.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _title(l),
            style: (_mode == CalendarViewMode.month
                    ? AppTypography.headline
                    : AppTypography.bodyStrong)
                .copyWith(color: context.ds.ink, fontSize: 18),
          ),
          if (_secondaryTitle(l) != null) ...[
            const SizedBox(width: AppSpacing.s2),
            Text(
              _secondaryTitle(l)!,
              style: TextStyle(fontSize: 12, color: context.ds.ink3),
            ),
          ],
          const Spacer(),
          if (!widget.hideHeader) ...[
            DsSegmented<CalendarViewMode>(
              height: 28,
              selected: _mode,
              options: [
                DsSegmentOption(CalendarViewMode.day, l.day),
                DsSegmentOption(CalendarViewMode.week, l.week),
                DsSegmentOption(CalendarViewMode.month, l.month),
              ],
              onSelected: (next) =>
                  ref.read(calendarViewModeProvider.notifier).setViewMode(next),
            ),
            const SizedBox(width: AppSpacing.s2),
          ],
          DsIconButton(
            icon: CupertinoIcons.chevron_left,
            size: 18,
            compact: true,
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: () => _shift(-1),
          ),
          if (!_viewingToday)
            DsButton(
              label: l.today,
              tone: DsButtonTone.ghost,
              small: true,
              onPressed: _goToToday,
            ),
          DsIconButton(
            icon: CupertinoIcons.chevron_right,
            size: 18,
            compact: true,
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: () => _shift(1),
          ),
        ],
      ),
    );
  }

  Widget _mobileToolbar(AppLocalizations l) {
    final ds = context.ds;
    final secondary = _secondaryTitle(l);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s1,
        AppSpacing.s2,
        AppSpacing.s1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                DsIconButton(
                  icon: CupertinoIcons.chevron_left,
                  size: 18,
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(l),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ds.ink,
                        ),
                      ),
                      if (secondary != null)
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: ds.ink3),
                        ),
                    ],
                  ),
                ),
                DsIconButton(
                  icon: CupertinoIcons.chevron_right,
                  size: 18,
                  onPressed: () => _shift(1),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                _MobileModeSwitch(
                  mode: _mode,
                  onSelected: (next) => ref
                      .read(calendarViewModeProvider.notifier)
                      .setViewMode(next),
                ),
                const Spacer(),
                if (!_viewingToday)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _goToToday,
                    child: SizedBox(
                      width: 52,
                      height: 44,
                      child: Center(
                        child: Text(
                          l.today,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ds.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileModeSwitch extends StatelessWidget {
  const _MobileModeSwitch({required this.mode, required this.onSelected});

  final CalendarViewMode mode;
  final ValueChanged<CalendarViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final options = [
      (CalendarViewMode.day, l.day),
      (CalendarViewMode.week, l.week),
      (CalendarViewMode.month, l.month),
    ];
    return Container(
      decoration: BoxDecoration(
        color: ds.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Semantics(
              button: true,
              selected: option.$1 == mode,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(option.$1),
                child: SizedBox(
                  width: 48,
                  height: 44,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: option.$1 == mode ? ds.surface : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      option.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: option.$1 == mode
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: option.$1 == mode ? ds.ink : ds.ink3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

typedef CalendarDeadlineLaneView = CalendarDeadlineLane;
