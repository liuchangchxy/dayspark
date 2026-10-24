import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';

/// Read a todo without entering edit mode.
///
/// Tapping a todo used to open a form, which made "look at this" and "change
/// this" the same gesture — so an accidental tap could rewrite a row. Detail
/// answers the question; [TodoFormPage] is a deliberate second step.
class TodoDetailPage extends ConsumerWidget {
  const TodoDetailPage({super.key, required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    // Watch the row so completing it here updates the page in place instead of
    // leaving a stale copy of a deleted or completed todo on screen.
    final live = ref
        .watch(allTodosProvider)
        .valueOrNull
        ?.where((row) => row.id == todo.id)
        .firstOrNull;
    final current = live ?? todo;

    return WorkspacePage(
      title: l.todoDetails,
      maxContentWidth: desktop ? 720 : null,
      actions: [
        IconButton(
          icon: const Icon(CupertinoIcons.trash, size: 18),
          tooltip: l.moveToTrash,
          visualDensity: VisualDensity.compact,
          onPressed: () => _delete(context, ref, l, current),
        ),
        const SizedBox(width: AppSpacing.sm),
        PageSaveButton(
          label: l.edit,
          onPressed: () => context.push('/todo/edit', extra: current),
        ),
      ],
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          desktop ? AppSpacing.xl : AppSpacing.lg,
          AppSpacing.lg,
          desktop ? AppSpacing.xl : AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(
                  current.status == 'COMPLETED'
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  size: 22,
                  color: current.status == 'COMPLETED'
                      ? Theme.of(context).colorScheme.primary
                      : context.semantic.textTertiary,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: current.status == 'COMPLETED'
                    ? l.markIncomplete
                    : l.markComplete,
                onPressed: () => _toggle(context, ref, l, current),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    current.summary,
                    style: AppTypography.headline.copyWith(
                      decoration: current.status == 'COMPLETED'
                          ? TextDecoration.lineThrough
                          : null,
                      color: current.status == 'COMPLETED'
                          ? context.semantic.textTertiary
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          const SizedBox(height: AppSpacing.sm),
          ScheduleRow(
            label: l.deadline,
            value: current.dueDate == null
                ? l.noDeadline
                : formatDeadline(context, current.dueDate!),
            placeholder: current.dueDate == null,
            emptyValue: l.noDeadline,
          ),
          // The start date is only the anchor a series repeats from, so it
          // appears exactly when the form asks for it.
          if (current.rrule != null && current.startDate != null)
            ScheduleRow(
              label: l.startDate,
              value: formatDeadline(context, current.startDate!),
            ),
          ScheduleRow(
            label: l.recurrenceRule,
            value: describeRepeat(context, current.rrule),
            placeholder: current.rrule == null,
          ),
          const SizedBox(height: AppSpacing.md),
          _Executions(todo: current),
          if (current.description != null &&
              current.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const RowDivider(),
            const SizedBox(height: AppSpacing.md),
            Text(current.description!, style: AppTypography.body),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Tags(todoId: current.id),
          if (current.priority != 5 && current.priority != 0) ...[
            const SizedBox(height: AppSpacing.lg),
            const RowDivider(),
            const SizedBox(height: AppSpacing.md),
            ScheduleRow(
              label: l.priority,
              value: current.priority == 1 ? l.priorityHigh : l.priorityLow,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const RowDivider(),
          const SizedBox(height: AppSpacing.md),
          AttachmentList(parentType: 'todo', parentId: current.id),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Todo current,
  ) async {
    await ref.read(toggleTodoProvider)(
      id: current.id,
      isCompleted: current.status != 'COMPLETED',
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Todo current,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.moveToTrash),
        content: Text(l.confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.moveToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final id = current.id;
    final restore = ref.read(restoreTodoProvider);
    await ref.read(deleteTodoProvider)(id);
    if (!context.mounted) return;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(id)),
      ),
    );
  }
}

class _Executions extends ConsumerWidget {
  const _Executions({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final allocations = ref
        .watch(taskAllocationsForTodoProvider(todo.id))
        .valueOrNull
        ?.where((item) => item.state == 'active')
        .toList();
    if (allocations == null || allocations.isEmpty) {
      return ScheduleRow(
        label: l.executionSchedule,
        value: l.notScheduled,
        placeholder: true,
        emptyValue: l.notScheduled,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in allocations)
          ScheduleRow(
            label: l.executionSchedule,
            value: formatExecutionRange(
              context,
              item.startAt,
              item.endAt,
              includeDate: false,
            ),
          ),
      ],
    );
  }
}

class _Tags extends ConsumerWidget {
  const _Tags({required this.todoId});

  final int todoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(todoTagsProvider(todoId)).valueOrNull ?? const [];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final tag in tags)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: ColorUtils.parseHex(tag.color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(tag.name, style: AppTypography.caption),
              ],
            ),
        ],
      ),
    );
  }
}
