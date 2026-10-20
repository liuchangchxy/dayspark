import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class RemindersSection extends ConsumerWidget {
  const RemindersSection({
    super.key,
    required this.parentType,
    required this.parentId,
    this.defaultTriggerTime,
  });

  final String parentType;
  final int parentId;
  final DateTime? defaultTriggerTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final remindersAsync = parentType == 'event'
        ? ref.watch(eventRemindersProvider(parentId))
        : ref.watch(todoRemindersProvider(parentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.reminders,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: Text(l.addReminder),
              onPressed: () => _showAddReminderDialog(context, ref),
            ),
          ],
        ),
        remindersAsync.when(
          data: (reminders) {
            if (reminders.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  l.noReminders,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reminders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.bell, size: 18),
                  title: Text(
                    DateFormatters.formatDateTime(reminder.triggerTime),
                  ),
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.trash, size: 16),
                    tooltip: l.delete,
                    onPressed: () => ref.read(deleteReminderProvider)(reminder.id),
                  ),
                );
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text(l.error('$e')),
        ),
      ],
    );
  }

  Future<void> _showAddReminderDialog(BuildContext context, WidgetRef ref) async {
    final initial = defaultTriggerTime ?? DateTime.now().add(const Duration(minutes: 15));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !context.mounted) return;

    final triggerTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    await ref.read(createReminderProvider)(
      parentType: parentType,
      parentId: parentId,
      triggerTime: triggerTime,
    );
  }
}
