import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// Calendar event tile: a tinted block with a saturated stripe on the left.
///
/// The stripe carries the category; the tint stays light enough that several
/// overlapping events still read as separate blocks (DESIGN 日历事件色).
class EventTile extends StatelessWidget {
  final CalendaEventAdapter event;
  final VoidCallback? onTap;

  const EventTile({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stripe =
        event.color ?? (isDark ? AppColors.darkAccent : AppColors.lightAccent);

    final tile = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Container(
        decoration: BoxDecoration(
          color: stripe.withValues(alpha: isDark ? 0.17 : 0.11),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: stripe, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: LayoutBuilder(
          builder: (context, constraints) => ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!event.isAllDay)
                      Text(
                        DateFormatters.formatTime(event.start),
                        style: AppTypography.tiny.copyWith(
                          color: context.semantic.textSecondary,
                        ),
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      final timeStr = event.isAllDay
          ? ''
          : ' ${DateFormatters.formatTime(event.start)} – ${DateFormatters.formatTime(event.end)}';
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          label: '${event.title}$timeStr',
          hint: AppLocalizations.of(context)!.openEventDetails,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: tile,
            ),
          ),
        ),
      );
    }
    return tile;
  }
}
