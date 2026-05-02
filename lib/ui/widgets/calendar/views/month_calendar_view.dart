import 'package:flutter/material.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class MonthCalendarView extends StatefulWidget {
  final DateTime anchorDate;
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter)? onEventTapped;
  final void Function(DateTime date)? onTimeSlotTapped;
  final void Function(DateTime newAnchor)? onPageChanged;

  const MonthCalendarView({
    super.key,
    required this.anchorDate,
    this.events = const [],
    this.onEventTapped,
    this.onTimeSlotTapped,
    this.onPageChanged,
  });

  @override
  State<MonthCalendarView> createState() => _MonthCalendarViewState();
}

class _MonthCalendarViewState extends State<MonthCalendarView> {
  static const int _epochMonth = 12000;
  static const int _totalMonths = 24000;

  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _monthToIndex(widget.anchorDate),
    );
  }

  @override
  void didUpdateWidget(covariant MonthCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _monthToIndex(oldWidget.anchorDate);
    final newIndex = _monthToIndex(widget.anchorDate);
    if (oldIndex != newIndex && _pageController.hasClients) {
      final currentPage =
          _pageController.page?.round() ?? _monthToIndex(oldWidget.anchorDate);
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
    super.dispose();
  }

  static int _monthToIndex(DateTime date) {
    return (date.year - 2000) * 12 + date.month - 1 + _epochMonth;
  }

  static DateTime _indexToMonth(int index) {
    final absolute = index - _epochMonth;
    final year = 2000 + absolute ~/ 12;
    final month = absolute % 12 + 1;
    return DateTime(year, month, 1);
  }

  List<DateTime> _buildGridDates(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final offset = (firstOfMonth.weekday - 1) % 7;
    final startDate = firstOfMonth.subtract(Duration(days: offset));
    return List.generate(42, (i) => startDate.add(Duration(days: i)));
  }

  List<CalendaEventAdapter> _eventsForDate(DateTime date) {
    return widget.events.where((e) {
      final s = DateTime(e.start.year, e.start.month, e.start.day);
      final end = DateTime(e.end.year, e.end.month, e.end.day);
      return !s.isAfter(date) && date.isBefore(end);
    }).toList();
  }

  static const List<String> _weekdayKeys = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String _weekdayLabel(BuildContext context, int index) {
    final l = AppLocalizations.of(context);
    if (l != null) {
      final locale = l.localeName;
      if (locale == 'zh') {
        const zh = ['一', '二', '三', '四', '五', '六', '日'];
        return zh[index];
      }
    }
    return _weekdayKeys[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildWeekdayHeader(context, theme),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _totalMonths,
            scrollDirection: Axis.horizontal,
            onPageChanged: (index) {
              widget.onPageChanged?.call(_indexToMonth(index));
            },
            itemBuilder: (context, index) {
              final month = _indexToMonth(index);
              return _buildMonthGrid(context, theme, month);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(BuildContext context, ThemeData theme) {
    return Row(
      children: List.generate(7, (i) {
        return Expanded(
          child: Center(
            child: Text(
              _weekdayLabel(context, i),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMonthGrid(
    BuildContext context,
    ThemeData theme,
    DateTime month,
  ) {
    final dates = _buildGridDates(month);
    final today = _dateOnly(DateTime.now());

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.75,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final date = dates[index];
        final isCurrentMonth = date.month == month.month;
        final isToday = date == today;
        final events = _eventsForDate(date);
        return _buildDayCell(context, theme, date, isToday, isCurrentMonth, events);
      },
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    ThemeData theme,
    DateTime date,
    bool isToday,
    bool isCurrentMonth,
    List<CalendaEventAdapter> events,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onTimeSlotTapped?.call(date);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _buildDateNumber(theme, date.day, isToday, isCurrentMonth)),
            const SizedBox(height: 2),
            if (events.isNotEmpty) ...[
              ...events.take(2).map(
                (e) => GestureDetector(
                  onTap: () => widget.onEventTapped?.call(e),
                  child: EventTile(event: e),
                ),
              ),
              if (events.length > 2)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '+${events.length - 2}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateNumber(
    ThemeData theme,
    int day,
    bool isToday,
    bool isCurrentMonth,
  ) {
    if (isToday) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Text(
      '$day',
      style: theme.textTheme.labelMedium?.copyWith(
        color: isCurrentMonth
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    );
  }

  static DateTime _dateOnly(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }
}
