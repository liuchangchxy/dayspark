import 'package:flutter/material.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';

class TodoListTile extends StatelessWidget {
  final String summary;
  final bool isCompleted;
  final int priority;
  final DateTime? dueDate;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const TodoListTile({
    super.key,
    required this.summary,
    required this.isCompleted,
    required this.priority,
    this.dueDate,
    required this.onToggle,
    required this.onTap,
  });

  Color get _priorityColor {
    if (isCompleted) return Colors.grey;
    if (priority >= 1 && priority <= 1) return AppColors.lightError;
    if (priority >= 2 && priority <= 4) return AppColors.lightWarning;
    return Colors.transparent;
  }

  String get _dueDateLabel {
    if (dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Overdue';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${dueDate!.month}/${dueDate!.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor =
        isCompleted ? theme.disabledColor : theme.textTheme.bodyMedium?.color;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (_priorityColor != Colors.transparent)
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: _priorityColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else
              const SizedBox(width: 4),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isCompleted,
                onChanged: (_) => onToggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dueDate != null)
                    Text(
                      _dueDateLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: _dueDateLabel == 'Overdue'
                            ? AppColors.lightError
                            : theme.textTheme.bodySmall?.color,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
