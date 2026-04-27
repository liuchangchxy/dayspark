import 'package:flutter/material.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';
import 'package:calendar_todo_app/core/utils/date_formatters.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

class EventTile extends StatelessWidget {
  final CalendaEventAdapter event;

  const EventTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final bgColor = event.color ?? AppColors.lightAccent;

    return Container(
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: bgColor, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: bgColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!event.isAllDay)
            Text(
              DateFormatters.formatTime(event.dateTimeRange.start),
              style: TextStyle(
                fontSize: 10,
                color: bgColor.withValues(alpha: 0.8),
              ),
              maxLines: 1,
            ),
        ],
      ),
    );
  }
}
