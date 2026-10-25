import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

class TodoListTile extends ConsumerWidget {
  final String summary;
  final bool isCompleted;
  final int priority;
  final int todoId;
  final DateTime? dueDate;
  final DateTime? startDate;

  /// Shown only where an explicit order is the point (Six Things); everywhere
  /// else the number would be an invented rank that changes as rows move.
  final int? index;

  /// Desktop passes a handle: dragging a whole row fights with the row's own
  /// tap target, so reordering gets its own small grip.
  final Widget? dragHandle;

  /// Omitted by surfaces that must stay read-only, such as search results,
  /// where a tap means "open this" and nothing else.
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

  Color _priorityColor(Brightness brightness) {
    if (isCompleted) {
      return brightness == Brightness.dark
          ? AppColors.darkDisabled
          : AppColors.lightDisabled;
    }
    if (priority == 1) {
      return brightness == Brightness.dark
          ? AppColors.darkError
          : AppColors.lightError;
    }
    if (priority >= 2 && priority <= 4) {
      return brightness == Brightness.dark
          ? AppColors.darkWarning
          : AppColors.lightWarning;
    }
    return Colors.transparent;
  }

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

    // Show date range when startDate differs from dueDate by > 1 day
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
    final tagsAsync = ref.watch(todoTagsProvider(todoId));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit, not layout mode: whether the date can sit next to the title at
        // this row width. The app's layout breakpoint stays kWorkspaceBreakpoint.
        final compact = constraints.maxWidth < 600;
        final date = Text(
          _dueDateLabel(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: !isCompleted && _isOverdue
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.45),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 2,
                  height: 18,
                  child: Semantics(
                    label: priority == 1 ? l.highPriority : l.mediumPriority,
                    excludeSemantics:
                        _priorityColor(theme.brightness) == Colors.transparent,
                    child: ColoredBox(color: _priorityColor(theme.brightness)),
                  ),
                ),
                MouseRegion(
                  cursor: onToggle == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: Semantics(
                    button: onToggle != null,
                    label: isCompleted ? l.markIncomplete : l.markComplete,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: onToggle == null
                          ? Center(
                              child: Icon(
                                isCompleted
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 20,
                                color: isCompleted
                                    ? theme.colorScheme.primary
                                    : context.semantic.textTertiary,
                              ),
                            )
                          : Checkbox(
                              value: isCompleted,
                              onChanged: (_) => _toggle(context, ref),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              visualDensity: VisualDensity.standard,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                    ),
                  ),
                ),
                if (index != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${index! + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(
                  child: Semantics(
                    button: true,
                    hint: l.openTodoDetails,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: InkWell(
                        onTap: onTap,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              summary,
                                              style: TextStyle(
                                                fontSize:
                                                    AppTypography.body.fontSize,
                                                color: textColor,
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
                                              padding: const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              child: Icon(
                                                CupertinoIcons.repeat,
                                                size: 14,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (compact && dueDate != null) ...[
                                        const SizedBox(height: 4),
                                        date,
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                tagsAsync.when(
                                  data: (tags) => _tagDots(context, tags),
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, __) => const SizedBox.shrink(),
                                ),
                                if (!compact && dueDate != null) ...[
                                  const SizedBox(width: 16),
                                  Flexible(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: date,
                                    ),
                                  ),
                                ],
                                if (dragHandle != null) dragHandle!,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tagDots(BuildContext context, List tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tags.take(3).map<Widget>((tag) {
        final color = ColorUtils.parseHex(tag.color);
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Semantics(
            label: AppLocalizations.of(context)!.tagWith(tag.name),
            child: Tooltip(
              message: tag.name,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      }).toList(),
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
