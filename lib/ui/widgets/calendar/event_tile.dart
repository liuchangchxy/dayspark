import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

class EventTile extends StatelessWidget {
  final CalendaEventAdapter event;

  const EventTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final bgColor = event.color ?? AppColors.lightAccent;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final resolvedColor = isDark ? AppColors.darkAccent : bgColor;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Container(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: resolvedColor, width: 2),
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
              color: resolvedColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!event.isAllDay)
            Text(
              DateFormatters.formatTime(event.start),
              style: TextStyle(
                fontSize: 10,
                color: resolvedColor.withValues(alpha: 0.8),
              ),
              maxLines: 1,
            ),
        ],
      ),
      ),
    );
  }
}
