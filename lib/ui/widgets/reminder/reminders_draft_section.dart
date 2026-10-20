import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class RemindersDraftSection extends StatelessWidget {
  const RemindersDraftSection({
    super.key,
    required this.draftReminders,
    required this.onChanged,
    this.defaultTriggerTime,
  });

  final List<DateTime> draftReminders;
  final ValueChanged<List<DateTime>> onChanged;
  final DateTime? defaultTriggerTime;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

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
              onPressed: () => _showAddReminderDialog(context),
            ),
          ],
        ),
        if (draftReminders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              l.noReminders,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          )
        else
          ...draftReminders.asMap().entries.map((entry) {
            final index = entry.key;
            final triggerTime = entry.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(CupertinoIcons.bell, size: 18),
              title: Text(DateFormatters.formatDateTime(triggerTime)),
              trailing: IconButton(
                icon: const Icon(CupertinoIcons.trash, size: 16),
                tooltip: l.delete,
                onPressed: () {
                  final updated = List<DateTime>.from(draftReminders)
                    ..removeAt(index);
                  onChanged(updated);
                },
              ),
            );
          }),
      ],
    );
  }

  Future<void> _showAddReminderDialog(BuildContext context) async {
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

    final updated = List<DateTime>.from(draftReminders)..add(triggerTime);
    onChanged(updated);
  }
}
