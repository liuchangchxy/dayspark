import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

class EventTile extends StatelessWidget {
  final CalendaEventAdapter event;
  final VoidCallback? onTap;

  const EventTile({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final defaultColor = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final resolvedColor = event.color ?? defaultColor;

    final tile = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Container(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: resolvedColor, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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

    if (onTap != null) {
      final timeStr = event.isAllDay
          ? ''
          : ' ${DateFormatters.formatTime(event.start)} – ${DateFormatters.formatTime(event.end)}';
      return Semantics(
        label: '${event.title}$timeStr',
        hint: 'Open event details',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: tile,
          ),
        ),
      );
    }
    return tile;
  }
}
