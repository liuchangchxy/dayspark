import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';

const _calendarColors = [
  '#2563EB',
  '#16A34A',
  '#DC2626',
  '#D97706',
  '#7C3AED',
  '#DB2777',
  '#4B5563',
  '#0D9488',
  '#EA580C',
  '#4F46E5',
];

class CalendarsPage extends ConsumerWidget {
  const CalendarsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final calendarsAsync = ref.watch(calendarsProvider);

    return WorkspacePage(
      title: l.manageCalendars,
      maxContentWidth: 720,
      actions: [
        IconButton(
          icon: const Icon(CupertinoIcons.add, size: 18),
          onPressed: () => _showCreateDialog(context, ref),
          visualDensity: VisualDensity.compact,
        ),
      ],
      child: calendarsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error('$e'))),
        data: (calendars) {
          if (calendars.isEmpty) {
            return EmptyState(
              icon: CupertinoIcons.calendar,
              title: l.noCalendar,
              action: FilledButton(
                onPressed: () => _showCreateDialog(context, ref),
                child: Text(l.create),
              ),
            );
          }

          final canDelete = calendars.length > 1;

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: calendars.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final calendar = calendars[index];
              return ListTile(
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: ColorUtils.parseHex(calendar.color),
                ),
                title: Text(calendar.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.pencil, size: 18),
                      tooltip: l.editCalendar,
                      onPressed: () => _showEditDialog(context, ref, calendar),
                    ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(CupertinoIcons.trash, size: 18),
                        tooltip: l.deleteCalendar,
                        onPressed: () => _confirmDelete(context, ref, calendar),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    var selectedColor = _calendarColors.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.newCalendar),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l.calendarName,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _calendarColors.map((hex) {
                  final isSelected = hex == selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => selectedColor = hex),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ColorUtils.parseHex(hex),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2.5,
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  ref.read(createCalendarProvider)(
                    name: name,
                    color: selectedColor,
                  );
                  Navigator.of(ctx).pop();
                }
              },
              child: Text(l.create),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Calendar calendar) {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: calendar.name);
    var selectedColor = calendar.color;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.editCalendar),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l.calendarName,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _calendarColors.map((hex) {
                  final isSelected = hex == selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => selectedColor = hex),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ColorUtils.parseHex(hex),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2.5,
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  ref.read(updateCalendarProvider)(
                    id: calendar.id,
                    name: name,
                    color: selectedColor,
                  );
                  Navigator.of(ctx).pop();
                }
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Calendar calendar) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteCalendar),
        content: Text(calendar.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(deleteCalendarProvider)(calendar.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.cannotDeleteOnlyCalendar)),
                  );
                }
              }
            },
            child: Text(
              l.delete,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
