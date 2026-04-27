import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class TodoListTile extends ConsumerWidget {
  final String summary;
  final bool isCompleted;
  final int priority;
  final int todoId;
  final DateTime? dueDate;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const TodoListTile({
    super.key,
    required this.summary,
    required this.isCompleted,
    required this.priority,
    required this.todoId,
    this.dueDate,
    required this.onToggle,
    required this.onTap,
  });

  Color get _priorityColor {
    if (isCompleted) return Colors.grey;
    if (priority == 1) return AppColors.lightError;
    if (priority >= 2 && priority <= 4) return AppColors.lightWarning;
    return Colors.transparent;
  }

  String _dueDateLabel(BuildContext context) {
    if (dueDate == null) return '';
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return l.overdue;
    if (diff == 0) return l.today;
    if (diff == 1) return l.tomorrow;
    return '${dueDate!.month}/${dueDate!.day}';
  }

  bool get _isOverdue {
    if (dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textColor =
        isCompleted ? theme.disabledColor : theme.textTheme.bodyMedium?.color;
    final tagsAsync = ref.watch(todoTagsProvider(todoId));

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
                  Row(
                    children: [
                      if (dueDate != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            _dueDateLabel(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: _isOverdue
                                  ? AppColors.lightError
                                  : theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      tagsAsync.when(
                        data: (tags) => _tagDots(tags),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagDots(List tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tags.take(3).map<Widget>((tag) {
        final color = ColorUtils.parseHex(tag.color);
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: tag.name,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
