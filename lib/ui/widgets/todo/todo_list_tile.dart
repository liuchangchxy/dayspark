import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

/// One todo row. A circle, a name, a quiet meta line, nothing else.
///
/// The calendar colour is metadata the detail explains, not an unlabeled dot
/// glued to the right edge; priority is a property shown in detail, not a
/// stripe that colours a list. Both were the previous UI's loudest signals and
/// neither helped scanning.
class TodoListTile extends ConsumerWidget {
  final String summary;
  final bool isCompleted;
  final int priority;
  final int todoId;
  final DateTime? dueDate;
  final DateTime? startDate;
  final int? index;
  final Widget? dragHandle;
  final Future<void> Function(String? occurrenceId, bool isCompleted)? onToggle;
  final VoidCallback onTap;
  final Todo? todo;
  final bool selected;

  const TodoListTile({
    super.key,
    required this.summary,
    required this.isCompleted,
    required this.priority,
    required this.todoId,
    this.dueDate,
    this.startDate,
    this.index,
    this.dragHandle,
    this.onToggle,
    required this.onTap,
    this.todo,
    this.selected = false,
  });

  String _dueLabel(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (dueDate == null) return l.noDueDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final diff = due.difference(today).inDays;
    final hasTime = dueDate!.hour != 0 || dueDate!.minute != 0;
    final clock = hasTime ? ' ${DateFormatters.formatTime(dueDate!)}' : '';
    if (diff < 0) return '${l.overdue} ${DateFormatters.formatShortDate(dueDate!)}';
    if (diff == 0) return '${l.today}$clock';
    if (diff == 1) return '${l.tomorrow}$clock';
    return DateFormatters.formatShortDate(dueDate!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final tagsAsync = ref.watch(todoTagsProvider(todoId));
    final allocationAsync = ref.watch(taskAllocationsForTodoProvider(todoId));

    final meta = <DsMetaPart>[];
    final calendarName = _calendarName(ref);
    if (calendarName != null) meta.add(DsMetaPart(calendarName));
    final allocation = allocationAsync.valueOrNull?.firstOrNull;
    if (allocation != null) {
      final start = allocation.startAt.toLocal();
      final end = allocation.endAt.toLocal();
      meta.add(
        DsMetaPart(
          '${l.plannedExecution} ${DateFormatters.formatTime(start)}–${DateFormatters.formatTime(end)}',
        ),
      );
    }
    final repeatLabel = _repeatLabel(context);
    if (repeatLabel != null) meta.add(DsMetaPart(repeatLabel));

    final tags = tagsAsync.valueOrNull ?? const [];
    if (tags.isNotEmpty) {
      meta.add(DsMetaPart(tags.take(2).map((t) => t.name).join(' · ')));
    }

    return DsRow(
      title: summary,
      done: isCompleted,
      selected: selected,
      dense: false,
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      onTap: onTap,
      leading: DsCheck(
        checked: isCompleted,
        size: 20,
        label: isCompleted ? l.markIncomplete : l.markComplete,
        onChanged: onToggle == null || isCompleted && todo?.status == 'COMPLETED'
            ? null
            : (_) => _toggle(context, ref),
      ),
      meta: index == null && meta.isEmpty
          ? null
          : Row(
              children: [
                if (index != null) ...[
                  Text(
                    '${index! + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: ds.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: DsMeta(parts: meta)),
              ],
            ),
      trailing: _trailing(context, ref),
    );
  }

  Widget? _trailing(BuildContext context, WidgetRef ref) {
    final due = _dueCapsule(context);
    if (dragHandle == null) return due;
    if (due == null) return dragHandle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [due, const SizedBox(width: 6), dragHandle!],
    );
  }

  /// The deadline as a label at the row's right edge: red for a missed one, a
  /// tinted chip for one that has a clock time, quiet text otherwise.
  ///
  /// The meta line is left to say what the task is about, so scanning the right
  /// edge alone answers "what is due, and how late".
  Widget? _dueCapsule(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final due = dueDate;
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    final hasTime = due.hour != 0 || due.minute != 0;
    TextStyle style(double size) => AppTypography.small.copyWith(
      fontSize: size,
      height: 1,
      fontFeatures: AppTypography.tabular,
    );

    if (!isCompleted && day.isBefore(today)) {
      final days = today.difference(day).inDays;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: ds.dangerSoft,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          l.overdueDays(days),
          style: style(11).copyWith(color: ds.danger, fontWeight: FontWeight.w500),
        ),
      );
    }

    final label = _dueLabel(context);
    if (hasTime) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: ds.surface2,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsDot(color: ds.primary, size: 5),
            const SizedBox(width: 5),
            Text(label, style: style(11).copyWith(color: ds.ink2)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 2, top: 2),
      child: Text(label, style: style(11).copyWith(color: ds.ink3)),
    );
  }

  String? _calendarName(WidgetRef ref) {
    final row = todo;
    if (row == null) return null;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final calendar = calendars.where((c) => c.id == row.calendarId).firstOrNull;
    return calendar?.name;
  }

  String? _repeatLabel(BuildContext context) {
    final rule = todo?.rrule;
    if (rule == null || rule.isEmpty) return null;
    final l = AppLocalizations.of(context)!;
    if (rule.contains('FREQ=DAILY')) return l.repeatDaily;
    if (rule.contains('FREQ=WEEKLY')) return l.repeatWeekly;
    if (rule.contains('FREQ=MONTHLY')) return l.repeatMonthly;
    if (rule.contains('FREQ=YEARLY')) return l.repeatYearly;
    return null;
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final row = todo;
    final toggle = onToggle;
    if (toggle == null) return;
    try {
      if (row?.rrule == null) {
        await toggle(null, !isCompleted);
        return;
      }
      if (row!.status == 'COMPLETED') {
        await toggle(null, false);
        return;
      }
      final selected = await TodoOccurrencePickerSheet.show(
        context,
        ref: ref,
        todo: row,
      );
      if (!context.mounted || selected == null) return;
      await toggle(selected.occurrenceId, !selected.isCompleted);
    } on Object catch (error) {
      if (context.mounted) showCompletionError(context, error);
    }
  }
}
