import 'package:dayspark/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class CalendarDeadline {
  const CalendarDeadline({
    required this.todoId,
    required this.title,
    required this.due,
  });
  final int todoId;
  final String title;
  final DateTime due;
}

class CalendarDeadlineLane extends StatelessWidget {
  const CalendarDeadlineLane({
    super.key,
    required this.dates,
    required this.deadlines,
    this.onTapped,
  });
  final List<DateTime> dates;
  final List<CalendarDeadline> deadlines;
  final ValueChanged<CalendarDeadline>? onTapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 96),
      child: SingleChildScrollView(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                height: 48,
                child: Center(
                  child: Text(
                    l.calendarDeadlineLane,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              ...dates.map((date) {
                final items = deadlines.where(
                  (item) =>
                      item.due.year == date.year &&
                      item.due.month == date.month &&
                      item.due.day == date.day,
                );
                return Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (items.isEmpty) const SizedBox(height: 48),
                      ...items.map(
                        (item) => Tooltip(
                          message: item.title,
                          child: InkWell(
                            onTap: onTapped == null
                                ? null
                                : () => onTapped!(item),
                            mouseCursor: SystemMouseCursors.click,
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 48),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.flag,
                                    size: 12,
                                    color: context.semantic.warning,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      '${DateFormat.Hm().format(item.due)} ${item.title}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: context.semantic.warning,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
