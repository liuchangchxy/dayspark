import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/color_swatch_grid.dart';

const kCalendarColors = [
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

/// The only calendar picker. It always opens — even with one calendar — so
/// "which calendar is this in?" is answerable before creating a second one.
/// Creating inside the picker returns to it with the new calendar selected.
Future<int?> pickCalendar(
  BuildContext context,
  WidgetRef ref, {
  int? selectedId,
}) async {
  var selected = selectedId;
  while (true) {
    if (!context.mounted) return null;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CalendarPickerSheet(selectedId: selected),
    );
    if (!context.mounted) return null;
    if (result == null) return null;
    if (result is int) return result;
    if (result == _createCalendarSentinel) {
      final created = await _showCreateCalendarDialog(context, ref);
      if (!context.mounted) return null;
      if (created == null) continue;
      selected = created;
    }
  }
}

const _createCalendarSentinel = 'create-calendar';

class _CalendarPickerSheet extends ConsumerWidget {
  const _CalendarPickerSheet({this.selectedId});

  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final selected = selectedId ?? (calendars.isEmpty ? null : calendars.first.id);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(l.calendarField, style: AppTypography.title),
          ),
          for (final calendar in calendars)
            ListTile(
              minVerticalPadding: AppSpacing.sm,
              leading: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: ColorUtils.parseHex(calendar.color),
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(calendar.name),
              trailing: calendar.id == selected
                  ? Icon(
                      CupertinoIcons.checkmark,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(calendar.id),
            ),
          const Divider(height: 1),
          ListTile(
            minVerticalPadding: AppSpacing.sm,
            leading: const Icon(CupertinoIcons.add, size: 18),
            title: Text(l.createCalendarFromPicker),
            onTap: () =>
                Navigator.of(context).pop<Object>(_createCalendarSentinel),
          ),
        ],
      ),
    );
  }
}

Future<int?> _showCreateCalendarDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppLocalizations.of(context)!;
  final nameController = TextEditingController();
  var selectedColor = kCalendarColors.first;
  String? error;
  var saving = false;
  final created = await showDialog<int>(
    animationStyle: AnimationStyle.noAnimation,
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
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.calendarName,
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ColorSwatchGrid(
              colors: kCalendarColors,
              selected: selectedColor,
              onSelected: (hex) => setState(() => selectedColor = hex),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setState(() => error = l.calendarNameRequired);
                      return;
                    }
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final id = await ref.read(createCalendarProvider)(
                        name: name,
                        color: selectedColor,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(id);
                    } catch (failure) {
                      debugPrint('calendar picker: create failed: $failure');
                      if (ctx.mounted) {
                        setState(() {
                          saving = false;
                          error = l.actionFailedRetry;
                        });
                      }
                    }
                  },
            child: Text(l.create),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  return created;
}
