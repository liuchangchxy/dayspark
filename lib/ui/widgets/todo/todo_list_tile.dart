import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/utils/color_utils.dart';
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

  bool get _isOverdue {
    if (dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final tagsAsync = ref.watch(todoTagsProvider(todoId));
    final allocationAsync = ref.watch(taskAllocationsForTodoProvider(todoId));

    final meta = <DsMetaPart>[];
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
    if (dueDate != null) {
      final overdue = !isCompleted && _isOverdue;
      meta.add(
        DsMetaPart(
          overdue
              ? '${l.overdue} ${DateFormatters.formatShortDate(dueDate!)}'
              : l.deadlinePrefix(_dueLabel(context)),
          color: overdue ? ds.danger : null,
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
      trailing: _trailing(ref),
    );
  }

  Widget? _trailing(WidgetRef ref) {
    final dot = _calendarDot(ref);
    if (dragHandle == null) return dot;
    if (dot == null) return dragHandle;
    return Row(mainAxisSize: MainAxisSize.min, children: [dot, dragHandle!]);
  }

  Widget? _calendarDot(WidgetRef ref) {
    final row = todo;
    if (row == null) return null;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final calendar = calendars.where((c) => c.id == row.calendarId).firstOrNull;
    if (calendar == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: DsDot(color: ColorUtils.parseHex(calendar.color), size: 7),
    );
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
