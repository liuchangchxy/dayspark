import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

class TaskAllocationsSection extends ConsumerWidget {
  const TaskAllocationsSection({super.key, required this.todo});

  final Todo todo;

  bool get _canSchedule =>
      todo.deletedAt == null &&
      todo.status != 'COMPLETED' &&
      todo.status != 'CANCELLED';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final allocationsAsync = ref.watch(taskAllocationsForTodoProvider(todo.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.taskAllocations,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            if (_canSchedule)
              TextButton.icon(
                icon: const Icon(CupertinoIcons.add, size: 16),
                label: Text(l.addTaskAllocation),
                onPressed: () => _create(context, ref),
              ),
          ],
        ),
        allocationsAsync.when(
          data: (allocations) {
            if (allocations.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.noTaskAllocations,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Column(
              children: allocations.map((allocation) {
                final active = allocation.state == 'active';
                final orphan =
                    allocation.occurrenceId != null &&
                    !_isCurrentOccurrence(allocation.occurrenceId!);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.time),
                  title: Text(
                    '${DateFormatters.formatDate(allocation.startAt)}  '
                    '${DateFormatters.formatTime(allocation.startAt)} – '
                    '${DateFormatters.formatTime(allocation.endAt)}',
                  ),
                  subtitle: orphan
                      ? Text(l.orphanTaskAllocation)
                      : active
                      ? null
                      : Text(l.cancelledTaskAllocation),
                  trailing: active
                      ? IconButton(
                          tooltip: l.cancelTaskAllocation,
                          icon: const Icon(CupertinoIcons.xmark_circle),
                          onPressed: () => _cancel(context, ref, allocation.id),
                        )
                      : null,
                );
              }).toList(),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Text(l.error('$error')),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    String? occurrenceId;
    if (todo.rrule != null && todo.rrule!.isNotEmpty) {
      final freshTodo =
          await (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).todos)
                ..where((row) => row.id.equals(todo.id)))
              .getSingle();
      if (!context.mounted) return;
      final TodoOccurrenceExpansion expansion;
      try {
        expansion = expandTodoOccurrences(
          freshTodo,
          startInclusive: now,
          endExclusive: now.add(const Duration(days: 90)),
          maxOccurrences: 100,
        );
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.error('$error'))));
        }
        return;
      }
      if (expansion.status != TodoOccurrenceExpansionStatus.expanded) {
        if (context.mounted) {
          final message = switch (expansion.status) {
            TodoOccurrenceExpansionStatus.requiresLegacyConfirmation =>
              l.legacyRecurrenceRequiresConfirmation,
            TodoOccurrenceExpansionStatus.unsupported =>
              l.unsupportedRecurrence,
            _ => l.noOccurrencesAvailable,
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }
      if (expansion.occurrences.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noOccurrencesAvailable)));
        return;
      }
      final selected = await showDialog<TodoOccurrence>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(l.selectTodoOccurrence),
          children: [
            for (final occurrence in expansion.occurrences)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(occurrence),
                child: Text(_occurrenceLabel(occurrence)),
              ),
          ],
        ),
      );
      if (selected == null || !context.mounted) return;
      occurrenceId = selected.occurrenceId;
    }
    final initialStart = DateTime(now.year, now.month, now.day, now.hour + 1);
    final date = await showDatePicker(
      context: context,
      initialDate: initialStart,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialStart),
    );
    if (startTime == null || !context.mounted) return;
    final initialEnd = initialStart.add(const Duration(hours: 1));
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialEnd),
    );
    if (endTime == null || !context.mounted) return;
    final startAt = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );
    var endAt = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    if (!endAt.isAfter(startAt)) endAt = endAt.add(const Duration(days: 1));
    try {
      await ref.read(createTaskAllocationProvider)(
        todoId: todo.id,
        startAt: startAt,
        endAt: endAt,
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

  String _occurrenceLabel(TodoOccurrence occurrence) {
    final nominal = occurrence.nominalAnchor;
    if (nominal is LocalDate) return nominal.canonical;
    final instant = occurrence.resolvedStartInstant;
    return instant == null
        ? nominal.canonical
        : '${nominal.canonical} (${DateFormatters.formatDate(instant.toLocal())} '
              '${DateFormatters.formatTime(instant.toLocal())})';
  }

  bool _isCurrentOccurrence(String occurrenceId) {
    try {
      return !TodoRecurrence.fromTodo(todo).isUnknownLegacy &&
          isOccurrenceStillValidForSeries(todo, occurrenceId);
    } on FormatException {
      return false;
    } on RecurrenceRuleException {
      return false;
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.cancelTaskAllocation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context)!.cancelTaskAllocation),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(cancelTaskAllocationProvider)(id);
  }
}
