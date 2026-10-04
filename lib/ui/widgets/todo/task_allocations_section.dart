import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class TaskAllocationsSection extends ConsumerWidget {
  const TaskAllocationsSection({super.key, required this.todo});

  final Todo todo;

  bool get _canSchedule =>
      todo.rrule == null &&
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
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.time),
                  title: Text(
                    '${DateFormatters.formatDate(allocation.startAt)}  '
                    '${DateFormatters.formatTime(allocation.startAt)} – '
                    '${DateFormatters.formatTime(allocation.endAt)}',
                  ),
                  subtitle: active ? null : Text(l.cancelledTaskAllocation),
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
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error('$error'))));
      }
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
