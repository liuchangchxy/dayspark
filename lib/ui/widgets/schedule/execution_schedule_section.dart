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
///
/// [id] is set for a block that already exists, so a form can tell an add from
/// a keep and cancel the ones that disappeared on save.
class DraftExecution {
  const DraftExecution({
    required this.start,
    required this.end,
    this.id,
    this.occurrenceId,
  });

  final DateTime start;
  final DateTime end;
  final int? id;
  final String? occurrenceId;

  @override
  bool operator ==(Object other) =>
      other is DraftExecution &&
      other.id == id &&
      other.occurrenceId == occurrenceId &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, occurrenceId, start, end);
}

/// "When will I do this?" — one row, one sheet.
///
/// Scheduling is a first-class answer rather than an advanced property: it is
/// offered while the todo is still being created, not only after saving and
/// reopening it. The row keeps the relationship explicit by saying what it is
/// relative to the deadline instead of restating a time range.
///
/// With [onDraftChanged] the section edits a form's draft list and writes
/// nothing; without it, [todo]'s blocks are persisted as they are changed.
class ExecutionScheduleSection extends ConsumerWidget {
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

  final Todo? todo;

  /// The blocks the form currently holds. Passing [onDraftChanged] makes the
  /// section deferred: nothing reaches the database until the form saves.
  final List<DraftExecution> draft;
  final ValueChanged<List<DraftExecution>>? onDraftChanged;

  /// Used to suggest a sensible starting point.
  final DateTime? deadline;

  final bool enabled;

  bool get _deferred => onDraftChanged != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final rows = _deferred || todo == null
        ? draft
        : ref
              .watch(taskAllocationsForTodoProvider(todo!.id))
              .valueOrNull
              ?.where((item) => item.state == 'active')
              .map(
                (item) => DraftExecution(
                  id: item.id,
                  start: item.startAt,
                  end: item.endAt,
                  occurrenceId: item.occurrenceId,
                ),
              )
              .toList();

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
        if (rows == null)
          const SizedBox.shrink()
        else
          for (final item in rows)
            ScheduleRow(
              label: l.executionRow,
              // A block on another day cannot be read from a bare clock time,
              // so the date is part of the value, not a hint.
              value: formatExecutionRange(context, item.start, item.end),
              clearTooltip: l.cancelSchedule,
              onClear: enabled && _canSchedule
                  ? () => _clear(context, ref, l, item)
                  : null,
            ),
      ],
    );
  }

  bool get _canSchedule {
    final row = todo;
    if (row == null) return true;
    return row.deletedAt == null &&
        row.status != 'COMPLETED' &&
        row.status != 'CANCELLED';
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final row = todo;
    String? occurrenceId;
    if (row != null && row.rrule != null && row.rrule!.isNotEmpty) {
      if (!_isConfirmableOccurrence(row)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.unsupportedRecurrence)));
        return;
      }
      final selected = await TodoOccurrencePickerSheet.show(
        context,
        ref: ref,
        todo: row,
      );
      if (selected == null || !context.mounted) return;
      occurrenceId = selected.occurrenceId;
    }
    final now = DateTime.now();
    final suggested = deadline != null && deadline!.isAfter(now)
        ? deadline!
        : now.add(const Duration(hours: 1));
    final result = await showExecutionSheet(context, initial: suggested);
    if (result == null || !context.mounted) return;

    if (_deferred) {
      onDraftChanged!([
        ...draft,
        DraftExecution(
          start: result.start,
          end: result.end,
          occurrenceId: occurrenceId,
        ),
      ]);
      return;
    }
    try {
      await ref.read(createTaskAllocationProvider)(
        todoId: row!.id,
        startAt: result.start,
        endAt: result.end,
        occurrenceId: occurrenceId,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.schedulingFailed)));
      }
    }
  }

  /// Cancelling a scheduled block is reversible: the block is a plan, and
  /// plans change. The snackbar says what was cancelled and offers it back.
  Future<void> _clear(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    DraftExecution item,
  ) async {
    if (_deferred) {
      onDraftChanged!([...draft]..remove(item));
      return;
    }
    final id = item.id;
    if (id == null) return;
    await ref.read(cancelTaskAllocationProvider)(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.cancelledTaskAllocation),
        action: SnackBarAction(
          label: l.undo,
          onPressed: () => ref.read(createTaskAllocationProvider)(
            todoId: todo!.id,
            startAt: item.start,
            endAt: item.end,
            occurrenceId: item.occurrenceId,
          ),
        ),
      ),
    );
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
        minimumSize: const Size(0, 48),
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
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.lengthLabel,
                      style: AppTypography.caption.copyWith(
                        color: context.semantic.textSecondary,
                      ),
                    ),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: FilledButton(
                  onPressed: () => Navigator.of(
                    ctx,
                  ).pop(DraftExecution(start: start, end: start.add(length))),
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
