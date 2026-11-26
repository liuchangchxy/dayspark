import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';

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
              onTap: enabled && _canSchedule && !_deferred && item.id != null
                  ? () => _reschedule(context, ref, l, item)
                  : null,
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
        showSpecToast(context, l.unsupportedRecurrence);
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
    final picked = await SpecPlanPickerDialog.show(
      context,
      title: row?.summary ?? l.executionSchedule,
      initialStart: suggested,
      initialEnd: suggested.add(const Duration(minutes: 45)),
      existingBlocks: (day) => _existingBlocks(ref, day, excludeTodoId: row?.id),
    );
    if (picked == null || !context.mounted) return;

    if (_deferred) {
      onDraftChanged!([
        ...draft,
        DraftExecution(
          start: picked.$1,
          end: picked.$2,
          occurrenceId: occurrenceId,
        ),
      ]);
      return;
    }
    try {
      await ref.read(createTaskAllocationProvider)(
        todoId: row!.id,
        startAt: picked.$1,
        endAt: picked.$2,
        occurrenceId: occurrenceId,
      );
    } catch (error) {
      if (context.mounted) {
        showSpecToast(context, l.schedulingFailed);
      }
    }
  }

  /// The plan picker shows what already occupies the chosen day, so it has to
  /// read the same two sources the calendar does.
  Future<List<SpecPlanBlock>> _existingBlocks(
    WidgetRef ref,
    DateTime day, {
    int? excludeTodoId,
  }) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final db = ref.read(databaseProvider);
    final events = await db.eventsDao.getEventCandidates(start, end);
    final allocations = await fetchTaskAllocationsInDateRange(db, start, end);
    final blocks = calDayBlocks(
      day: start,
      events: [
        for (final event in events) CalendaEventAdapter.fromDrift(event),
      ],
      allocations: [
        for (final item in allocations)
          if (item.todo.id != excludeTodoId)
            TaskAllocationCalendarAdapter.fromItem(item),
      ],
    );
    return [
      for (final block in blocks)
        SpecPlanBlock(
          start: block.start,
          end: block.end,
          title: block.title,
        ),
    ];
  }

  /// Moving an existing block is the same question as adding one, so it reuses
  /// the same spec picker instead of making the user cancel and re-create it.
  Future<void> _reschedule(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    DraftExecution item,
  ) async {
    final id = item.id;
    if (id == null) return;
    // Storage is UTC; the row already shows the local wall time.
    final start = item.start.toLocal();
    final end = item.end.toLocal();
    final picked = await SpecPlanPickerDialog.show(
      context,
      title: todo?.summary ?? l.executionSchedule,
      initialStart: start,
      initialEnd: end,
      existingBlocks: (day) => _existingBlocks(ref, day, excludeTodoId: todo?.id),
      isEditing: true,
    );
    if (picked == null || !context.mounted) return;
    try {
      await ref.read(rescheduleTaskAllocationProvider)(
        id: id,
        startAt: picked.$1,
        endAt: picked.$2,
      );
    } catch (error) {
      if (context.mounted) {
        showSpecToast(context, l.schedulingFailed);
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
    showUndoBar(
      context,
      message: l.cancelledTaskAllocation,
      undoLabel: l.undo,
      onUndo: () => ref.read(createTaskAllocationProvider)(
        todoId: todo!.id,
        startAt: item.start,
        endAt: item.end,
        occurrenceId: item.occurrenceId,
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
