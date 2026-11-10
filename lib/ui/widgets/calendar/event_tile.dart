import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

/// Calendar event tile matching DESIGN.md (6) and VISUAL_POLISH.md:
/// 2px left border of calendar color (no full border);
/// background = calendar color 11% mixed with surface (dark mode 17%);
/// radius 6 (mobile) / 4 (desktop).
class EventTile extends StatelessWidget {
  final CalendaEventAdapter event;
  final VoidCallback? onTap;

  const EventTile({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stripe = event.color ?? (isDark ? AppColors.darkAccent : AppColors.lightAccent);
    final surface = theme.colorScheme.surface;
    final bgColor = Color.alphaBlend(
      stripe.withValues(alpha: isDark ? 0.17 : 0.11),
      surface,
    );

    final tile = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.rSm),
          border: Border(left: BorderSide(color: stripe, width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
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
                        color: theme.colorScheme.onSurface,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!event.isAllDay)
                      Text(
                        DateFormatters.formatTime(event.start),
                        style: AppTypography.caption.copyWith(
                          fontSize: 10.5,
                          color: context.semantic.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
      final l = AppLocalizations.of(context);
      final timeStr = event.isAllDay
          ? ''
          : ' ${DateFormatters.formatTime(event.start)} – ${DateFormatters.formatTime(event.end)}';
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          label: '${event.title}$timeStr',
          hint: l?.openEventDetails,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.rSm),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.rSm),
              child: tile,
            ),
          ),
        ),
      );
    }
    return tile;
  }
}
