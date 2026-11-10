import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

/// Todo item row matching DESIGN.md 4.1:
/// [44dp touch area / 20dp round checkbox] [Title + Meta ('·' separated)] [Action/Grip]
/// Flat transparent row with hairline bottom divider, no colored end-dots.
class TodoListTile extends ConsumerWidget {
  final String summary;
  final bool isCompleted;
  final int priority;
  final int todoId;
  final DateTime? dueDate;
  final DateTime? startDate;
  final int? index;
  final Widget? dragHandle;
  final Future<void> Function(String? occurrenceId, bool isCompleted)? onToggle;
  final VoidCallback onTap;
  final Todo? todo;

  const TodoListTile({
    super.key,
    required this.summary,
    required this.isCompleted,
    required this.priority,
    required this.todoId,
    this.dueDate,
    this.startDate,
    this.index,
    this.dragHandle,
    this.onToggle,
    required this.onTap,
    this.todo,
  });

  String _dueDateLabel(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (dueDate == null) return l.noDueDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return l.overdue;
    if (diff == 0) return l.today;
    if (diff == 1) return l.tomorrow;

    if (startDate != null) {
      final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
      final span = due.difference(start).inDays;
      if (span > 1) {
        return '${DateFormatters.formatShortDate(start)} – ${DateFormatters.formatShortDate(due)}';
      }
    }

    return DateFormatters.formatShortDate(dueDate!);
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
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final textColor = isCompleted
        ? theme.disabledColor
        : theme.textTheme.bodyMedium?.color;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final dateText = _dueDateLabel(context);
        final dateWidget = dueDate != null
            ? Text(
                dateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: !isCompleted && _isOverdue
                      ? theme.colorScheme.error
                      : context.semantic.textSecondary,
                ),
              )
            : null;

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 48x48 touch area with 20x20 round checkbox (only when onToggle != null)
                if (onToggle != null)
                  Semantics(
                    button: true,
                    label: isCompleted ? l.markIncomplete : l.markComplete,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: InkWell(
                          onTap: () => _toggle(context, ref),
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Opacity 0 Checkbox so standard flutter accessibility / finders recognize completion control
                              Opacity(
                                opacity: 0,
                                child: IgnorePointer(
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Checkbox(
                                      value: isCompleted,
                                      onChanged: null,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCompleted
                                        ? theme.colorScheme.primary
                                        : context.semantic.textTertiary,
                                    width: 1.5,
                                  ),
                                  color: isCompleted
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                ),
                                child: isCompleted
                                    ? const Center(
                                        child: Icon(
                                          CupertinoIcons.checkmark,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: AppSpacing.sm),
                if (index != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Text(
                      '${index! + 1}',
                      style: AppTypography.caption.copyWith(
                        color: context.semantic.textSecondary,
                      ),
                    ),
                  ),
                // Main content: Title + Meta
                Expanded(
                  child: Semantics(
                    button: true,
                    hint: l.openTodoDetails,
                    child: InkWell(
                      onTap: onTap,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            summary,
                                            style: AppTypography.body.copyWith(
                                              color: textColor,
                                              fontWeight: isCompleted
                                                  ? FontWeight.w400
                                                  : FontWeight.w500,
                                              decoration: isCompleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (todo?.rrule != null)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 6),
                                            child: Icon(
                                              CupertinoIcons.repeat,
                                              size: 14,
                                              color: context.semantic.textTertiary,
                                            ),
                                          ),
                                        if (!compact && dateWidget != null) ...[
                                          const SizedBox(width: AppSpacing.md),
                                          dateWidget,
                                        ],
                                      ],
                                    ),
                                    if (compact && dateWidget != null) ...[
                                      const SizedBox(height: 2),
                                      dateWidget,
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (dragHandle != null) dragHandle!,
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final row = todo;
    final toggle = onToggle;
    if (toggle == null) return;
    try {
      if (row?.rrule == null) {
        await toggle(null, !isCompleted);
        return;
      }
      if (row!.status == 'COMPLETED') {
        await toggle(null, false);
        return;
      }
      final selected = await TodoOccurrencePickerSheet.show(
        context,
        ref: ref,
        todo: row,
      );
      if (!context.mounted || selected == null) return;
      await toggle(selected.occurrenceId, !selected.isCompleted);
    } on Object catch (error) {
      if (context.mounted) showCompletionError(context, error);
    }
  }
}
