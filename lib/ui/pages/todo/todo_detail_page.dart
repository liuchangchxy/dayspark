import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
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
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';

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
    final desktop = isWorkspaceLayout(context);
    // Watch the row so completing it here updates the page in place, and so a
    // row deleted elsewhere stops being rendered as if it still existed.
    final live = ref
        .watch(allTodosProvider)
        .valueOrNull
        ?.where((row) => row.id == todo.id)
        .firstOrNull;
    if (live == null && ref.watch(allTodosProvider).hasValue) {
      return WorkspacePage(
        title: todo.summary,
        maxContentWidth: desktop ? 720 : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l.goneFromHere,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ),
        ),
      );
    }
    final current = live ?? todo;
    final completed = current.status == 'COMPLETED';

    return WorkspacePage(
      title: current.summary,
      maxContentWidth: desktop ? 720 : null,
      actions: [
        TextButton(
          onPressed: () => _complete(context, ref, current, completed),
          child: Text(completed ? l.markIncomplete : l.markComplete),
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
          // The title is the page header. Repeating it here would make the
          // name look like a second, editable field; the body starts with what
          // the object actually says.
          Row(
            children: [
              Icon(
                completed
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 18,
                color: completed
                    ? Theme.of(context).colorScheme.primary
                    : context.semantic.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                completed ? l.completed : l.openTask,
                style: AppTypography.caption.copyWith(
                  color: context.semantic.textSecondary,
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
          if (current.priority != 0) ...[
            const SizedBox(height: AppSpacing.lg),
            const RowDivider(),
            const SizedBox(height: AppSpacing.md),
            ScheduleRow(
              label: l.priority,
              value: _priorityLabel(l, current.priority),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          const SizedBox(height: AppSpacing.md),
          AttachmentList(parentType: 'todo', parentId: current.id),
          const SizedBox(height: AppSpacing.xl),
          const RowDivider(),
          const SizedBox(height: AppSpacing.sm),
          // Destructive lives at the bottom, away from the primary action.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _delete(context, ref, l, current),
              icon: Icon(
                CupertinoIcons.trash,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                minimumSize: const Size(48, 48),
              ),
              label: Text(l.moveToTrash),
            ),
          ),
        ],
      ),
    );
  }

  static String _priorityLabel(AppLocalizations l, int priority) =>
      switch (priority) {
        1 => l.priorityHigh,
        5 => l.priorityMedium,
        9 => l.priorityLow,
        _ => l.priorityNone,
      };

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    Todo current,
    bool completed,
  ) async {
    try {
      await toggleTodoCompletion(
        context,
        ref,
        todo: current,
        completed: !completed,
      );
    } on Object catch (error) {
      if (context.mounted) showCompletionError(context, error);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Todo current,
  ) async {
    final confirmed = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
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
    // Leave the detail page rather than staying on an object that no longer
    // exists; the list underneath is the place the user came from.
    _leaveToSource(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(id)),
      ),
    );
  }
}

/// A deleted object cannot stay on screen. Pop the detail route so the user
/// lands on the list they came from, falling back to Home for deep links.
void _leaveToSource(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    context.pop();
    return;
  }
  router?.go('/');
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
