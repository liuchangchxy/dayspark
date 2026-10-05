import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';

class TaskAllocationTile extends StatelessWidget {
  const TaskAllocationTile({super.key, required this.allocation, this.onTap});

  final TaskAllocationCalendarAdapter allocation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Container(
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.secondary, width: 3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allocation.todoTitle,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              DateFormatters.formatTaskAllocationRange(
                allocation.start,
                allocation.end,
                includeDate: false,
              ),
              style: AppTypography.overline.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
              maxLines: 1,
            ),
          ],
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
