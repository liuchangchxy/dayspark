import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';

/// TaskAllocation tile matching DESIGN.md (6) and VISUAL_POLISH.md:
/// Surface / surface-2 background, 1px dashed outline, hollow square icon.
class TaskAllocationTile extends StatelessWidget {
  const TaskAllocationTile({super.key, required this.allocation, this.onTap});

  final TaskAllocationCalendarAdapter allocation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;

    final tile = CustomPaint(
      foregroundPainter: _DashedBorderPainter(borderColor),
      child: Container(
        constraints: const BoxConstraints(minHeight: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppSpacing.rSm),
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
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.square,
                          size: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            allocation.todoTitle,
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      DateFormatters.formatTaskAllocationRange(
                        allocation.start,
                        allocation.end,
                        includeDate: false,
                      ),
                      style: AppTypography.caption.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant,
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

    if (onTap == null) return tile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: tile),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppSpacing.rSm),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        if (distance + 4.0 <= metric.length) {
          canvas.drawPath(metric.extractPath(distance, distance + 4.0), paint);
        }
        distance += 7.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
