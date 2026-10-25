import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/color_swatch_grid.dart';
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
          tooltip: l.newCalendar,
          onPressed: () => _editCalendar(context, ref, null),
        ),
      ],
      child: calendarsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          debugPrint('calendars: load error: $error');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.actionFailedRetry, style: AppTypography.body),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => ref.invalidate(calendarsProvider),
                  child: Text(l.retry),
                ),
              ],
            ),
          );
        },
        data: (calendars) {
          if (calendars.isEmpty) {
            return EmptyState(
              icon: CupertinoIcons.calendar,
              title: l.noCalendar,
              action: FilledButton(
                onPressed: () => _editCalendar(context, ref, null),
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
              // The row opens the editor: the colour is part of the calendar,
              // and a row that only *looks* clickable is worse than a plain one.
              return ListTile(
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: ColorUtils.parseHex(calendar.color),
                ),
                title: Text(calendar.name),
                onTap: () => _editCalendar(context, ref, calendar),
                trailing: canDelete
                    ? IconButton(
                        icon: const Icon(CupertinoIcons.trash, size: 18),
                        tooltip: l.deleteCalendar,
                        onPressed: () => _confirmDelete(context, ref, calendar),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editCalendar(
    BuildContext context,
    WidgetRef ref,
    Calendar? calendar,
  ) async {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: calendar?.name ?? '');
    var selectedColor = calendar?.color ?? _calendarColors.first;
    String? error;
    var saving = false;

    await showDialog<void>(
    animationStyle: AnimationStyle.noAnimation, context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(calendar == null ? l.newCalendar : l.editCalendar),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l.calendarName,
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              ColorSwatchGrid(
                colors: _calendarColors,
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
                        if (calendar == null) {
                          await ref.read(createCalendarProvider)(
                            name: name,
                            color: selectedColor,
                          );
                        } else {
                          await ref.read(updateCalendarProvider)(
                            id: calendar.id,
                            name: name,
                            color: selectedColor,
                          );
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (failure) {
                        debugPrint('calendars: save error: $failure');
                        if (ctx.mounted) {
                          setState(() {
                            saving = false;
                            error = l.actionFailedRetry;
                          });
                        }
                      }
                    },
              child: Text(calendar == null ? l.create : l.save),
            ),
          ],
        ),
      ),
    );
  }

  /// A calendar holds events and todos. Deleting it must therefore answer the
  /// one question that matters — where do they go — instead of leaving rows
  /// pointing at a calendar that no longer exists.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Calendar calendar,
  ) async {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    final targets = calendars.where((row) => row.id != calendar.id).toList();
    final db = ref.read(databaseProvider);
    final eventCount = await (db.select(
      db.events,
    )..where((row) => row.calendarId.equals(calendar.id))).get();
    final todoCount = await (db.select(
      db.todos,
    )..where((row) => row.calendarId.equals(calendar.id))).get();
    if (!context.mounted) return;
    final contents = eventCount.length + todoCount.length;

    final decision = await showDialog<_DeleteDecision>(
    animationStyle: AnimationStyle.noAnimation, context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteCalendar),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(calendar.name),
            if (contents > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l.calendarHasContents(eventCount.length, todoCount.length),
                style: AppTypography.caption,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          if (contents > 0 && targets.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(const _DeleteDecision.move()),
              child: Text(l.moveContentsTo),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(const _DeleteDecision.deleteAll()),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(contents > 0 ? l.deleteCalendarAndContents : l.delete),
          ),
        ],
      ),
    );
    if (decision == null || !context.mounted) return;

    var targetId = decision.targetId;
    if (decision.move && targets.isNotEmpty && targetId == null) {
      targetId = await showModalBottomSheet<int>(
        context: context,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(l.moveContentsTo, style: AppTypography.title),
              ),
              for (final target in targets)
                ListTile(
                  leading: CircleAvatar(
                    radius: 10,
                    backgroundColor: ColorUtils.parseHex(target.color),
                  ),
                  title: Text(target.name),
                  onTap: () => Navigator.of(ctx).pop(target.id),
                ),
            ],
          ),
        ),
      );
      if (targetId == null || !context.mounted) return;
    }

    try {
      await ref.read(deleteCalendarProvider)(
        calendar.id,
        moveContentsTo: decision.move ? targetId : null,
        deleteContents: !decision.move,
      );
    } catch (error) {
      debugPrint('calendars: delete error: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.cannotDeleteOnlyCalendar)));
      }
    }
  }
}

class _DeleteDecision {
  const _DeleteDecision.move() : move = true, targetId = null;
  const _DeleteDecision.deleteAll() : move = false, targetId = null;

  final bool move;
  final int? targetId;
}
