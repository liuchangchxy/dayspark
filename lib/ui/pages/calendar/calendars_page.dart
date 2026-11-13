import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/color_swatch_grid.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';

class CalendarsPage extends ConsumerWidget {
  const CalendarsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final calendarsAsync = ref.watch(calendarsProvider);

    return WorkspacePage(
      title: l.manageCalendars,
      maxContentWidth: 720,
      child: calendarsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          debugPrint('calendars: load error: $error');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.actionFailedRetry,
                  style: AppTypography.body.copyWith(color: ds.ink2),
                ),
                const SizedBox(height: AppSpacing.s2),
                DsButton(
                  label: l.retry,
                  tone: DsButtonTone.ghost,
                  small: true,
                  onPressed: () => ref.invalidate(calendarsProvider),
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
              action: DsButton(
                label: l.create,
                onPressed: () => _editCalendar(context, ref, null),
              ),
            );
          }

          final canDelete = calendars.length > 1;
          final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];

          return ListView(
            key: const ValueKey('calendars-list'),
            padding: const EdgeInsets.only(bottom: AppSpacing.s6),
            children: [
              DsGroupLabel(l.myCalendars),
              DsGroup(
                children: [
                  for (final calendar in calendars)
                    DsSettingRow(
                      label: calendar.name,
                      value: l.dayItemCount(
                        todos
                            .where(
                              (t) =>
                                  t.calendarId == calendar.id &&
                                  t.status != 'COMPLETED' &&
                                  t.status != 'CANCELLED',
                            )
                            .length,
                      ),
                      leading: DsDot(
                        color: ColorUtils.parseHex(calendar.color),
                        size: 8,
                      ),
                      trailing: canDelete
                          ? DsIconButton(
                              icon: CupertinoIcons.trash,
                              size: 16,
                              compact: true,
                              tooltip: l.deleteCalendar,
                              onPressed: () =>
                                  _confirmDelete(context, ref, calendar),
                            )
                          : null,
                      onTap: () => _editCalendar(context, ref, calendar),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s3,
                  AppSpacing.s4,
                  AppSpacing.s1,
                ),
                child: DsButton(
                  label: l.newCalendar,
                  icon: CupertinoIcons.add,
                  tone: DsButtonTone.secondary,
                  expand: true,
                  onPressed: () => _editCalendar(context, ref, null),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s5,
                  AppSpacing.s3,
                  AppSpacing.s5,
                  AppSpacing.s2,
                ),
                child: Text(
                  l.calendarExplanation,
                  style: AppTypography.caption.copyWith(color: ds.ink3),
                ),
              ),
            ],
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
    final selectedColor = ValueNotifier<String>(
      calendar?.color ?? kCalendarColors.first,
    );
    final error = ValueNotifier<String?>(null);
    final saving = ValueNotifier<bool>(false);

    Future<void> save(BuildContext sheetContext) async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        error.value = l.calendarNameRequired;
        return;
      }
      error.value = null;
      saving.value = true;
      try {
        if (calendar == null) {
          await ref.read(createCalendarProvider)(
            name: name,
            color: selectedColor.value,
          );
        } else {
          await ref.read(updateCalendarProvider)(
            id: calendar.id,
            name: name,
            color: selectedColor.value,
          );
        }
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      } catch (failure) {
        debugPrint('calendars: save error: $failure');
        if (sheetContext.mounted) {
          saving.value = false;
          error.value = l.actionFailedRetry;
        }
      }
    }

    await showDsSheet<void>(
      context: context,
      title: calendar == null ? l.newCalendar : l.editCalendar,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: error,
            builder: (ctx, message, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DsField(
                  label: l.calendarName,
                  child: DsTextField(
                    controller: nameController,
                    autofocus: true,
                    onSubmitted: (_) => save(ctx),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                    child: Text(
                      message,
                      style: AppTypography.small.copyWith(
                        color: context.ds.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: selectedColor,
            builder: (ctx, color, _) => ColorSwatchGrid(
              colors: kCalendarColors,
              selected: color,
              onSelected: (hex) => selectedColor.value = hex,
            ),
          ),
        ],
      ),
      actions: [
        const Spacer(),
        Builder(
          builder: (ctx) => DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).maybePop(),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        ValueListenableBuilder<bool>(
          valueListenable: saving,
          builder: (ctx, isSaving, _) => DsButton(
            label: calendar == null ? l.create : l.save,
            loading: isSaving,
            onPressed: () => save(ctx),
          ),
        ),
      ],
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
      context: context,
      builder: (ctx) => DsDialog(
        title: l.deleteCalendar,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              calendar.name,
              style: AppTypography.body.copyWith(color: context.ds.ink),
            ),
            if (contents > 0) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(
                l.calendarHasContents(eventCount.length, todoCount.length),
                style: AppTypography.caption.copyWith(color: context.ds.ink3),
              ),
            ],
            const SizedBox(height: AppSpacing.s4),
            if (contents > 0 && targets.isNotEmpty) ...[
              DsButton(
                label: l.moveContentsTo,
                tone: DsButtonTone.secondary,
                expand: true,
                onPressed: () =>
                    Navigator.of(ctx).pop(const _DeleteDecision.move()),
              ),
              const SizedBox(height: AppSpacing.s2),
            ],
            DsButton(
              label: contents > 0 ? l.deleteCalendarAndContents : l.delete,
              tone: DsButtonTone.danger,
              expand: true,
              onPressed: () =>
                  Navigator.of(ctx).pop(const _DeleteDecision.deleteAll()),
            ),
          ],
        ),
      ),
    );
    if (decision == null || !context.mounted) return;

    var targetId = decision.targetId;
    if (decision.move && targets.isNotEmpty && targetId == null) {
      targetId = await showDsSheet<int>(
        context: context,
        title: l.moveContentsTo,
        body: Builder(
          builder: (sheetContext) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final target in targets)
                DsSettingRow(
                  label: target.name,
                  leading: DsDot(
                    color: ColorUtils.parseHex(target.color),
                    size: 8,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(target.id),
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
