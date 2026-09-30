import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

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
    final stripe = event.color ?? (isDark ? AppColors.darkAccent : AppColors.lightAccent);

    final tile = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Container(
        decoration: BoxDecoration(
          color: stripe.withValues(alpha: isDark ? 0.24 : 0.13),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: stripe, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        // kalender gives tiles tight, sometimes very short constraints
        // (e.g. 1h slots, all-day bar); scale content instead of overflowing.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.title,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!event.isAllDay)
                Text(
                  DateFormatters.formatTime(event.start),
                  style: AppTypography.overline.copyWith(
                    color: context.semantic.textSecondary,
                  ),
                  maxLines: 1,
                ),
            ],
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
