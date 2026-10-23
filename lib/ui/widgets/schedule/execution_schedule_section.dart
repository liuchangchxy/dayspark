import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

/// A scheduled block the user has proposed but not saved yet.
class DraftExecution {
  const DraftExecution({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// "When will I do this?" — one row, one sheet.
///
/// Scheduling is a first-class answer rather than an advanced property: it is
/// offered while the todo is still being created, not only after saving and
/// reopening it. The row keeps the relationship explicit by saying what it is
/// relative to the deadline instead of restating a time range.
class ExecutionScheduleSection extends StatelessWidget {
  const ExecutionScheduleSection({
    super.key,
    this.todo,
    this.draft = const [],
    this.onDraftChanged,
    this.deadline,
    this.enabled = true,
  }) : assert(
         todo != null || onDraftChanged != null,
         'either an existing todo or a draft list is required',
       );

  /// Existing todo: blocks are persisted immediately.
  final Todo? todo;

  /// Creation: blocks are collected and written with the todo.
  final List<DraftExecution> draft;
  final ValueChanged<List<DraftExecution>>? onDraftChanged;

  /// Used to suggest a sensible starting point.
  final DateTime? deadline;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (todo != null) {
      return _PersistedExecutions(
        todo: todo!,
        draft: draft,
        onDraftChanged: onDraftChanged,
        deadline: deadline,
        enabled: enabled,
      );
    }
    return _DraftExecutions(
      draft: draft,
      onChanged: onDraftChanged!,
      deadline: deadline,
      enabled: enabled,
    );
  }
}

class _DraftExecutions extends StatelessWidget {
  const _DraftExecutions({
    required this.draft,
    required this.onChanged,
    this.deadline,
    required this.enabled,
  });

  final List<DraftExecution> draft;
  final ValueChanged<List<DraftExecution>> onChanged;
  final DateTime? deadline;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          l.executionSchedule,
          action: enabled
              ? _AddButton(
                  label: l.addExecution,
                  onTap: () => _add(context, l, null),
                )
              : null,
        ),
        if (draft.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              l.executionNone,
              style: AppTypography.caption.copyWith(
                color: context.semantic.textTertiary,
              ),
            ),
          )
        else
          for (final item in draft)
            ScheduleRow(
              label: l.execution,
              value: formatExecutionRange(
                context,
                item.start,
                item.end,
                includeDate: false,
              ),
              onClear: enabled
                  ? () => onChanged(
                      [...draft]..removeWhere((other) => other.start == item.start),
                    )
                  : null,
            ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    AppLocalizations l,
    String? occurrenceId,
  ) async {
    final now = DateTime.now();
    final suggested = deadline != null && deadline!.isAfter(now)
        ? deadline!
        : now.add(const Duration(hours: 1));
    final result = await showExecutionSheet(context, initial: suggested);
    if (result == null || !context.mounted) return;
    onChanged([...draft, result]);
  }
}

class _PersistedExecutions extends ConsumerWidget {
  const _PersistedExecutions({
    required this.todo,
    required this.draft,
    required this.onDraftChanged,
    this.deadline,
    required this.enabled,
  });

  final Todo todo;
  final List<DraftExecution> draft;
  final ValueChanged<List<DraftExecution>>? onDraftChanged;
  final DateTime? deadline;
  final bool enabled;

  bool get _canSchedule =>
      todo.deletedAt == null &&
      todo.status != 'COMPLETED' &&
      todo.status != 'CANCELLED';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final allocationsAsync = ref.watch(
      taskAllocationsForTodoProvider(todo.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          l.executionSchedule,
          action: enabled && _canSchedule
              ? _AddButton(
                  label: l.addExecution,
                  onTap: () => _add(context, ref, l),
                )
              : null,
        ),
        allocationsAsync.when(
          data: (allocations) {
            final active = allocations
                .where((item) => item.state == 'active')
                .toList();
            if (active.isEmpty && draft.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  l.executionNone,
                  style: AppTypography.caption.copyWith(
                    color: context.semantic.textTertiary,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in active)
                  ScheduleRow(
                    label: l.execution,
                    // An orphaned block keeps its time but loses its series
                    // meaning; that is a note on the row, not a second field.
                    value: formatExecutionRange(
                      context,
                      item.startAt,
                      item.endAt,
                      includeDate: false,
                    ),
                    onClear: enabled && _canSchedule
                        ? () => ref.read(cancelTaskAllocationProvider)(item.id)
                        : null,
                  ),
                for (final item in draft)
                  ScheduleRow(
                    label: l.execution,
                    value: formatExecutionRange(
                      context,
                      item.start,
                      item.end,
                      includeDate: false,
                    ),
                    onClear: enabled && onDraftChanged != null
                        ? () => onDraftChanged!(
                            [...draft]
                              ..removeWhere(
                                (other) => other.start == item.start,
                              ),
                          )
                        : null,
                  ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Text(l.error('$error')),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, AppLocalizations l) async {
    String? occurrenceId;
    if (todo.rrule != null && todo.rrule!.isNotEmpty) {
      if (!_isConfirmableOccurrence(todo)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.unsupportedRecurrence)),
        );
        return;
      }
      final selected = await TodoOccurrencePickerSheet.show(
        context,
        ref: ref,
        todo: todo,
      );
      if (selected == null || !context.mounted) return;
      occurrenceId = selected.occurrenceId;
    }
    final result = await showExecutionSheet(
      context,
      initial: deadline ?? DateTime.now().add(const Duration(hours: 1)),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(createTaskAllocationProvider)(
        todoId: todo.id,
        startAt: result.start,
        endAt: result.end,
        occurrenceId: occurrenceId,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error('$error'))));
      }
    }
  }

  static bool _isConfirmableOccurrence(Todo todo) {
    try {
      return !TodoRecurrence.fromTodo(todo).isUnknownLegacy;
    } on Object {
      return false;
    }
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(CupertinoIcons.add, size: 13),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Pick a start and a length. Length is a choice, not an end time the user has
/// to compute.
Future<DraftExecution?> showExecutionSheet(
  BuildContext context, {
  required DateTime initial,
}) async {
  var start = initial;
  var length = kExecutionLengths[1];
  final l = AppLocalizations.of(context)!;
  return showModalBottomSheet<DraftExecution>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.executionSchedule,
                        style: AppTypography.title,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                      tooltip: l.close,
                    ),
                  ],
                ),
              ),
              ScheduleRow(
                label: l.executionWhen,
                value: formatMoment(ctx, start),
                onTap: () async {
                  final picked = await pickDateTime(ctx, initial: start);
                  if (picked != null) setSheetState(() => start = picked);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final option in kExecutionLengths)
                      ChoiceChip(
                        label: Text(formatExecutionLength(ctx, option)),
                        selected: length == option,
                        onSelected: (_) => setSheetState(() => length = option),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(
                    DraftExecution(start: start, end: start.add(length)),
                  ),
                  child: Text(l.save),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
