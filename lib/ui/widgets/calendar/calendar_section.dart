import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';
import 'package:dayspark/ui/widgets/calendar/views/month_calendar_view.dart';
import 'package:dayspark/ui/widgets/calendar/views/week_calendar_view.dart';
import 'package:dayspark/ui/widgets/calendar/views/day_calendar_view.dart';

class CalendarSection extends ConsumerStatefulWidget {
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
  ConsumerState<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<CalendarSection> {
  DateTime _anchorDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);
  }

  CalendarViewMode get _viewMode =>
      ref.watch(calendarViewModeProvider);

  bool get _isViewingToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_viewMode) {
      case CalendarViewMode.day:
        return _anchorDate == today;
      case CalendarViewMode.week:
        final weekday = today.weekday;
        final weekStart = today.subtract(Duration(days: weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return !_anchorDate.isBefore(weekStart) && !_anchorDate.isAfter(weekEnd);
      case CalendarViewMode.month:
        return _anchorDate.year == now.year && _anchorDate.month == now.month;
    }
  }

  String _formatDayHeader() {
    final locale = Localizations.localeOf(context).toString();
    final dateStr = DateFormat.MMMd(locale).format(_anchorDate);
    final weekday = DateFormat.E(locale).format(_anchorDate);
    return '$dateStr  $weekday';
  }

  String _formatWeekHeader() {
    final locale = Localizations.localeOf(context).toString();
    final weekday = _anchorDate.weekday;
    final weekStart = _anchorDate.subtract(Duration(days: weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${DateFormat.Md(locale).format(weekStart)} – ${DateFormat.Md(locale).format(weekEnd)}';
  }

  String _formatMonthHeader() {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMM(locale).format(_anchorDate);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final d = DateTime(picked.year, picked.month, picked.day);
      setState(() => _anchorDate = d);
    }
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() => _anchorDate = today);
  }

  void _navigateBack() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.day:
          _anchorDate = _anchorDate.subtract(const Duration(days: 1));
        case CalendarViewMode.week:
          _anchorDate = _anchorDate.subtract(const Duration(days: 7));
        case CalendarViewMode.month:
          _anchorDate = DateTime(_anchorDate.year, _anchorDate.month - 1, _anchorDate.day);
      }
    });
  }

  void _navigateForward() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.day:
          _anchorDate = _anchorDate.add(const Duration(days: 1));
        case CalendarViewMode.week:
          _anchorDate = _anchorDate.add(const Duration(days: 7));
        case CalendarViewMode.month:
          _anchorDate = DateTime(_anchorDate.year, _anchorDate.month + 1, _anchorDate.day);
      }
    });
  }

  void _handleTap(DateTime datetime) {
    if (widget.onTimeSlotTapped == null) return;
    widget.onTimeSlotTapped!(
      DateTimeRange(
        start: datetime,
        end: datetime.add(const Duration(hours: 1)),
      ),
    );
  }

  void _onPageChanged(DateTime newAnchor) {
    setState(() => _anchorDate = newAnchor);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickDate,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              (switch (_viewMode) {
                                CalendarViewMode.day => _formatDayHeader(),
                                CalendarViewMode.week => _formatWeekHeader(),
                                CalendarViewMode.month => _formatMonthHeader(),
                              }),
                              key: ValueKey(_anchorDate),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            CupertinoIcons.calendar,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_isViewingToday) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: _goToToday,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                      ),
                      child: Text(l.goToToday),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                    onPressed: _navigateBack,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_right, size: 20),
                    onPressed: _navigateForward,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ViewSwitcher(
                currentMode: _viewMode,
                onModeChanged: (mode) =>
                    ref.read(calendarViewModeProvider.notifier).setViewMode(mode),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_viewMode) {
            CalendarViewMode.month => MonthCalendarView(
              anchorDate: _anchorDate,
              events: widget.events,
              onEventTapped: widget.onEventTapped,
              onTimeSlotTapped: (date) => _handleTap(date),
              onPageChanged: _onPageChanged,
            ),
            CalendarViewMode.week => WeekCalendarView(
              anchorDate: _anchorDate,
              events: widget.events,
              onEventTapped: widget.onEventTapped,
              onTimeSlotTapped: (datetime) => _handleTap(datetime),
              onPageChanged: _onPageChanged,
              onEventChanged: (event, newStart) =>
                  _handleEventDrag(event, newStart),
            ),
            CalendarViewMode.day => DayCalendarView(
              anchorDate: _anchorDate,
              events: widget.events,
              onEventTapped: widget.onEventTapped,
              onTimeSlotTapped: (datetime) => _handleTap(datetime),
              onPageChanged: _onPageChanged,
              onEventChanged: (event, newStart) =>
                  _handleEventDrag(event, newStart),
            ),
          },
        ),
      ],
    );
  }

  void _handleEventDrag(CalendaEventAdapter event, DateTime newStart) {
    widget.onEventChanged?.call(event.copyWithData(
      start: newStart,
      end: newStart.add(event.end.difference(event.start)),
    ));
  }
}
