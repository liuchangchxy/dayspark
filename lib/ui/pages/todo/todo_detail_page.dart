import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_actions.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

/// A todo that is editable where it is read.
///
/// The old split — list, read-only detail, edit page — made changing a word
/// cost two page transitions. Detail and edit are now the same surface: every
/// field writes as soon as it is committed, and there is no second step to
/// reach. The same [TodoDetailPane] is the mobile page body and the desktop
/// right-hand pane, so the two platforms cannot drift apart.
class TodoDetailPage extends StatelessWidget {
  const TodoDetailPage({super.key, required this.todo, this.clock});

  final Todo todo;

  /// The instant the pane reads its status from. Tests pin it so a capture
  /// does not drift with the wall clock; live screens use the clock.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    return WorkspacePage(
      title: l.todos,
      maxContentWidth: desktop ? 720 : null,
      child: TodoDetailPane(todo: todo, clock: clock),
    );
  }
}

class TodoDetailPane extends ConsumerStatefulWidget {
  const TodoDetailPane({
    super.key,
    required this.todo,
    this.embedded = false,
    this.onClose,
    this.onDeleted,
    this.clock,
  });

  final Todo todo;

  /// True inside the desktop split view: no page chrome, a close affordance.
  final bool embedded;

  final VoidCallback? onClose;
  final VoidCallback? onDeleted;
  final DateTime Function()? clock;

  @override
  ConsumerState<TodoDetailPane> createState() => _TodoDetailPaneState();
}

class _TodoDetailPaneState extends ConsumerState<TodoDetailPane> {
  final _summary = TextEditingController();
  final _description = TextEditingController();
  final _summaryFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  Timer? _summaryTimer;
  Timer? _descriptionTimer;
  late String _savedSummary;
  late String _savedDescription;
  bool _deletedNotified = false;

  String get _todoId => '${widget.todo.id}';

  @override
  void initState() {
    super.initState();
    _savedSummary = widget.todo.summary;
    _savedDescription = widget.todo.description ?? '';
    _summary.text = _savedSummary;
    _description.text = _savedDescription;
    _summaryFocus.addListener(_flushSummary);
    _descriptionFocus.addListener(_flushDescription);
  }

  @override
  void dispose() {
    _flushSummary();
    _flushDescription();
    _summaryTimer?.cancel();
    _descriptionTimer?.cancel();
    _summaryFocus.removeListener(_flushSummary);
    _descriptionFocus.removeListener(_flushDescription);
    _summaryFocus.dispose();
    _descriptionFocus.dispose();
    _summary.dispose();
    _description.dispose();
    super.dispose();
  }

  void _syncFromLive(Todo live) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_summaryFocus.hasFocus &&
          _summary.text == _savedSummary &&
          _summary.text != live.summary) {
        _summary.text = live.summary;
        _savedSummary = live.summary;
      }
      final description = live.description ?? '';
      if (!_descriptionFocus.hasFocus &&
          _description.text == _savedDescription &&
          _description.text != description) {
        _description.text = description;
        _savedDescription = description;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final all = ref.watch(allTodosProvider);
    final live = all.valueOrNull
        ?.where((row) => row.id == widget.todo.id)
        .firstOrNull;
    if (live == null) {
      if (all.hasValue) {
        _notifyDeleted();
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l.goneFromHere,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    _syncFromLive(live);

    final completed = live.status == 'COMPLETED';
    final legacy = _isUnknownLegacy(live);
    final now = widget.clock?.call() ?? DateTime.now();
    final ds = context.ds;
    final mobile = !isWorkspaceLayout(context);
    final side = widget.embedded ? 18.0 : (mobile ? 20.0 : 24.0);
    final rowHeight = mobile ? 56.0 : 58.0;
    final calendars =
        ref.watch(calendarsProvider).valueOrNull ?? const <Calendar>[];
    final currentCalendar = calendars
        .where((calendar) => calendar.id == live.calendarId)
        .firstOrNull;
    final calendarColor = currentCalendar == null
        ? ds.ink3
        : ColorUtils.parseHex(currentCalendar.color);
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = live.dueDate == null
        ? null
        : DateTime(
            live.dueDate!.year,
            live.dueDate!.month,
            live.dueDate!.day,
          );
    final days = dueDay?.difference(today).inDays;
    final String status;
    final Color statusColor;
    if (completed) {
      status = l.completed;
      statusColor = ds.ink3;
    } else if (dueDay == null) {
      status = l.noDeadline;
      statusColor = ds.ink3;
    } else if (days! < 0) {
      status = l.overdueDays(-days);
      statusColor = ds.danger;
    } else if (days == 0) {
      status = l.today;
      statusColor = ds.primaryHover;
    } else {
      status = l.upcoming;
      statusColor = ds.ink3;
    }
    final startLabel = live.startDate == null
        ? null
        : formatDeadline(context, live.startDate!);
    final dueLabel = live.dueDate == null
        ? null
        : formatDeadline(context, live.dueDate!);
    final leftDate = startLabel ?? dueLabel;
    final rightDate = startLabel == null ? null : dueLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: PageStorageKey<String>('todo-detail-$_todoId'),
            padding: EdgeInsets.fromLTRB(
              side,
              widget.embedded ? 18 : 14,
              side,
              24,
            ),
            children: [
              _header(
                context,
                l,
                live,
                currentCalendar?.name,
                calendarColor,
              ),
              _status(
                context,
                status,
                statusColor,
                completed ? 1.0 : 0.0,
                leftDate,
                rightDate,
              ),
              DsSectionLabel(
                l.sectionTime,
                padding: const EdgeInsets.only(top: 16, bottom: 6),
              ),
              Container(height: 1, color: ds.line),
              _deadlineRow(context, l, live, rowHeight, mobile),
              const SizedBox(height: 8),
              if (legacy) ...[
                _legacyNotice(context, l, live),
              ] else ...[
                ExecutionScheduleSection(todo: live, deadline: live.dueDate),
                RepeatRow(
                  rrule: live.rrule,
                  anchorDate: live.startDate ?? live.dueDate,
                  onChanged: (value) =>
                      _saveSchedule(setRule: true, rule: value),
                  startDate: live.startDate,
                  onStartDateChanged: (value) => _saveSchedule(
                    setStart: true,
                    start: value,
                    setRule: value == null,
                    rule: value == null ? null : live.rrule,
                  ),
                  needsDate: live.startDate == null && live.dueDate == null,
                ),
              ],
              RemindersSection(
                parentType: 'todo',
                parentId: live.id,
                anchorTime: live.dueDate,
              ),
              DsSectionLabel(
                l.sectionOrganize,
                padding: const EdgeInsets.only(top: 16, bottom: 6),
              ),
              Container(height: 1, color: ds.line),
              if (calendars.isNotEmpty)
                _calendarRow(
                  context,
                  l,
                  live,
                  currentCalendar,
                  calendarColor,
                  rowHeight,
                ),
              _priorityRow(context, l, live, rowHeight),
              const SizedBox(height: 12),
              _tags(context, live),
              DsSectionLabel(
                l.sectionContent,
                padding: const EdgeInsets.only(top: 16, bottom: 6),
              ),
              _notes(context, l),
              const SizedBox(height: 16),
              _subtasks(context, l, live),
              const SizedBox(height: 12),
              AttachmentList(parentType: 'todo', parentId: live.id),
              const SizedBox(height: 8),
            ],
          ),
        ),
        _footer(context, l, live, completed, mobile, side),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    Todo live,
    String? calendarName,
    Color calendarColor,
  ) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final anchor = live.dueDate ?? live.startDate;
    final date = anchor == null
        ? null
        : '${DateFormat.MMMd(locale).format(anchor)} '
              '${DateFormat.E(locale).format(anchor)}';
    final eyebrow = [
      calendarName ?? l.todoDetails,
      if (date != null) date,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PaneDot(color: calendarColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 16 / 11,
                        color: ds.ink3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  DsCheck(
                    checked: live.status == 'COMPLETED',
                    size: 18,
                    compact: true,
                    label: live.status == 'COMPLETED'
                        ? l.markIncomplete
                        : l.markComplete,
                    onChanged: (_) =>
                        _toggleCompletion(live, live.status == 'COMPLETED'),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('todo-detail-title'),
                      controller: _summary,
                      focusNode: _summaryFocus,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 26 / 20,
                        letterSpacing: 0.2,
                        color: ds.ink,
                      ),
                      strutStyle: const StrutStyle(
                        fontSize: 20,
                        height: 26 / 20,
                        forceStrutHeight: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (value) {
                        _summaryTimer?.cancel();
                        if (value.trim().isEmpty) return;
                        _summaryTimer = Timer(
                          const Duration(milliseconds: 600),
                          _flushSummary,
                        );
                      },
                      onSubmitted: (_) => _flushSummary(),
                      decoration: InputDecoration(
                        hintText: l.title,
                        isDense: true,
                        // The title sits on the page, not in a box: the theme
                        // fills every field, and a white patch behind the one
                        // line of 20px type reads as a stray input.
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: TextStyle(fontSize: 20, color: ds.ink3),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.embedded) ...[
          const SizedBox(width: 8),
          _PaneCloseButton(onPressed: widget.onClose, tooltip: l.close),
        ],
      ],
    );
  }

  Widget _status(
    BuildContext context,
    String status,
    Color statusColor,
    double fraction,
    String? left,
    String? right,
  ) {
    final ds = context.ds;
    final timeStyle = TextStyle(
      fontSize: 11,
      height: 15 / 11,
      color: ds.faint,
      fontFeatures: AppTypography.tabular,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 11),
          child: Row(
            children: [
              _PaneDot(color: statusColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 18 / 12,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        // A todo has no progress to show while it is open: an empty bar under
        // the status reads as a control that failed to load.
        if (fraction > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: ds.surface3)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: ColoredBox(color: ds.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (left != null) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(left, style: timeStyle),
              if (right != null) Text(right, style: timeStyle),
            ],
          ),
        ],
      ],
    );
  }

  Widget _deadlineRow(
    BuildContext context,
    AppLocalizations l,
    Todo live,
    double rowHeight,
    bool mobile,
  ) {
    return _PaneFieldRow(
      label: l.deadline,
      height: rowHeight,
      value: live.dueDate == null
          ? l.noDeadline
          : formatDeadline(context, live.dueDate!),
      onTap: () => _pickDue(live),
      showChevron: true,
      trailing: live.dueDate == null
          ? null
          : _PaneInlineClear(
              onPressed: () => _saveSchedule(setDue: true),
              tooltip: l.clearDeadline,
              size: mobile ? 44 : 32,
            ),
    );
  }

  Widget _calendarRow(
    BuildContext context,
    AppLocalizations l,
    Todo live,
    Calendar? currentCalendar,
    Color calendarColor,
    double rowHeight,
  ) {
    return _PaneFieldRow(
      label: l.calendarField,
      height: rowHeight,
      leading: _PaneDot(color: calendarColor, size: 7),
      value: currentCalendar?.name ?? l.calendarUnavailable,
      onTap: () => _pickCalendar(live),
      showChevron: true,
    );
  }

  Widget _priorityRow(
    BuildContext context,
    AppLocalizations l,
    Todo live,
    double rowHeight,
  ) {
    return _PaneFieldRow(
      label: l.priority,
      height: rowHeight,
      valueChild: Align(
        alignment: Alignment.centerLeft,
        child: _priorityChips(context, l, live),
      ),
    );
  }

  Widget _priorityChips(
    BuildContext context,
    AppLocalizations l,
    Todo live,
  ) {
    final labels = <int, String>{
      0: l.priorityNone,
      9: l.priorityLow,
      5: l.priorityMedium,
      1: l.priorityHigh,
    };
    return Wrap(
      spacing: AppSpacing.s1,
      runSpacing: AppSpacing.s1,
      children: [
        for (final value in const [0, 9, 5, 1])
          DsChip(
            label: labels[value]!,
            selected: live.priority == value,
            compact: true,
            onTap: () => _savePriority(value),
          ),
      ],
    );
  }

  Widget _notes(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The section label above already names this block; a second overline
        // six pixels lower read as a stray duplicate rather than a heading.
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: ds.bg,
            border: Border.all(color: ds.lineSoft),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: _description,
            focusNode: _descriptionFocus,
            style: TextStyle(fontSize: 13, height: 22 / 13, color: ds.ink2),
            strutStyle: const StrutStyle(
              fontSize: 13,
              height: 22 / 13,
              forceStrutHeight: true,
            ),
            cursorColor: ds.primary,
            decoration: InputDecoration(
              hintText: l.description,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: TextStyle(
                fontSize: 13,
                height: 22 / 13,
                color: ds.ink3,
              ),
            ),
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              _descriptionTimer?.cancel();
              _descriptionTimer = Timer(
                const Duration(milliseconds: 600),
                _flushDescription,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l,
    Todo live,
    bool completed,
    bool mobile,
    double side,
  ) {
    final ds = context.ds;
    final height = mobile ? 48.0 : 36.0;
    final primaryLabel = completed ? l.markIncomplete : l.markComplete;
    final primary = _PaneButton(
      label: primaryLabel,
      height: height,
      primary: true,
      onPressed: () => _toggleCompletion(live, completed),
    );
    final schedule = _PaneButton(
      label: l.schedule,
      height: height,
      onPressed: () => scheduleTodoBlock(context, ref, live),
    );
    final edit = _PaneButton(
      label: l.edit,
      height: height,
      onPressed: () => context.push('/todo/edit', extra: live),
    );
    final remove = _PaneButton(
      label: l.moveToTrash,
      height: height,
      danger: true,
      onPressed: () => _delete(live),
    );
    return Container(
      decoration: BoxDecoration(
        color: widget.embedded ? ds.surface : ds.bg,
        border: Border(top: BorderSide(color: ds.line)),
      ),
      padding: EdgeInsets.fromLTRB(side, mobile ? 12 : 14, side, 0),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: mobile ? 12 : 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fontSize = height >= 44 ? 14.0 : 12.0;
            final singleRow =
                _estimatedWidth(primaryLabel, fontSize) +
                    _estimatedWidth(l.schedule, fontSize) +
                    _estimatedWidth(l.edit, fontSize) +
                    _estimatedWidth(l.moveToTrash, fontSize) +
                    24 <=
                constraints.maxWidth;
            if (singleRow) {
              return SizedBox(
                height: height,
                child: Row(
                  children: [
                    Expanded(child: primary),
                    const SizedBox(width: 8),
                    schedule,
                    const SizedBox(width: 8),
                    edit,
                    const SizedBox(width: 8),
                    remove,
                  ],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: height,
                  child: Row(children: [Expanded(child: primary)]),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: height,
                  child: Row(
                    children: [
                      Expanded(child: schedule),
                      const SizedBox(width: 8),
                      Expanded(child: edit),
                      const SizedBox(width: 8),
                      Expanded(child: remove),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _estimatedWidth(String label, double fontSize) =>
      label.runes.length * fontSize + 22;

  Future<void> _pickCalendar(Todo live) async {
    final picked = await pickCalendar(
      context,
      ref,
      selectedId: live.calendarId,
    );
    if (picked != null) await _writeBasics(calendarId: picked);
  }

  bool _isUnknownLegacy(Todo row) {
    try {
      return TodoRecurrence.fromTodo(row).isUnknownLegacy;
    } on Object {
      return false;
    }
  }

  Widget _legacyNotice(BuildContext context, AppLocalizations l, Todo live) {
    return Row(
      children: [
        Expanded(
          child: Text(
            l.recurringNeedsRepairHint,
            style: AppTypography.caption.copyWith(
              color: context.semantic.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.push('/todo/edit', extra: live),
          child: Text(l.edit),
        ),
      ],
    );
  }

  Widget _subtasks(BuildContext context, AppLocalizations l, Todo live) {
    final subtasks = ref.watch(subtasksProvider(live.id)).valueOrNull ?? const [];
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l.subtasks,
              style: AppTypography.small.copyWith(
                color: ds.ink2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            DsButton(
              label: l.addSubtask,
              tone: DsButtonTone.ghost,
              small: true,
              icon: CupertinoIcons.add,
              onPressed: () => _addSubtask(context, l, live),
            ),
          ],
        ),
        if (subtasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l.noSubtasks,
              style: AppTypography.small.copyWith(color: ds.ink3),
            ),
          )
        else
          for (final sub in subtasks)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  DsCheck(
                    checked: sub.status == 'COMPLETED',
                    size: 17,
                    compact: true,
                    onChanged: (_) => ref.read(toggleTodoProvider)(
                      id: sub.id,
                      isCompleted: sub.status != 'COMPLETED',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      sub.summary,
                      style: AppTypography.body.copyWith(
                        fontSize: 14,
                        decoration: sub.status == 'COMPLETED'
                            ? TextDecoration.lineThrough
                            : null,
                        color: sub.status == 'COMPLETED'
                            ? ds.ink3
                            : ds.ink,
                      ),
                    ),
                  ),
                  DsIconButton(
                    icon: CupertinoIcons.xmark,
                    size: 14,
                    compact: true,
                    tooltip: l.removeSubtask,
                    onPressed: () => ref.read(deleteTodoProvider)(sub.id),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _addSubtask(
    BuildContext context,
    AppLocalizations l,
    Todo live,
  ) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.addSubtask),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.subtaskHint),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l.add),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = text?.trim();
    if (title == null || title.isEmpty) return;
    await ref.read(createTodoProvider)(
      calendarId: live.calendarId,
      summary: title,
      priority: 0,
      status: 'NEEDS-ACTION',
      parentId: live.id,
    );
  }

  Widget _tags(BuildContext context, Todo live) {
    final assigned =
        ref.watch(todoTagsProvider(live.id)).valueOrNull ?? const [];
    return Align(
      alignment: Alignment.centerLeft,
      child: TagChips(
        parentType: 'todo',
        parentId: live.id,
        assignedTags: assigned,
      ),
    );
  }

  Todo? get _currentRow {
    final rows = ref.read(allTodosProvider).valueOrNull;
    if (rows == null) return null;
    return rows.where((row) => row.id == widget.todo.id).firstOrNull;
  }

  void _notifyDeleted() {
    if (_deletedNotified) return;
    _deletedNotified = true;
    final callback = widget.onDeleted;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  void _flushSummary() {
    if (!mounted) return;
    _summaryTimer?.cancel();
    _summaryTimer = null;
    final text = _summary.text.trim();
    if (text.isEmpty) {
      _summary.text = _savedSummary;
      return;
    }
    if (text == _savedSummary) return;
    _savedSummary = text;
    unawaited(_writeBasics(summary: text));
  }

  void _flushDescription() {
    if (!mounted) return;
    _descriptionTimer?.cancel();
    _descriptionTimer = null;
    final text = _description.text.trim();
    if (text == _savedDescription) return;
    _savedDescription = text;
    unawaited(_writeBasics(description: text));
  }

  Future<void> _writeBasics({
    String? summary,
    String? description,
    int? priority,
    int? calendarId,
  }) async {
    try {
      await ref.read(updateTodoProvider)(
        widget.todo.id,
        TodosCompanion(
          summary: summary != null ? Value(summary) : const Value.absent(),
          description: description != null
              ? Value(description.isEmpty ? null : description)
              : const Value.absent(),
          priority: priority != null ? Value(priority) : const Value.absent(),
          calendarId: calendarId != null
              ? Value(calendarId)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } on Object catch (error) {
      debugPrint('todo_detail: update failed: $error');
      _showError();
    }
  }

  Future<void> _savePriority(int value) async {
    final current = _currentRow;
    if (current == null || current.priority == value) return;
    await _writeBasics(priority: value);
  }

  Future<void> _pickDue(Todo live) async {
    final now = DateTime.now();
    final picked = await pickDeadline(
      context,
      initial: live.dueDate ?? DateTime(now.year, now.month, now.day, 9),
      withTime:
          live.dueDate != null &&
          !(live.dueDate!.hour == 0 && live.dueDate!.minute == 0),
    );
    if (picked == null || !mounted) return;
    await _saveSchedule(setDue: true, due: picked);
  }

  /// Deadline, start and rule are one projection: a recurring todo refuses a
  /// half-updated anchor, so they are always written together as a spec.
  Future<void> _saveSchedule({
    bool setDue = false,
    DateTime? due,
    bool setStart = false,
    DateTime? start,
    bool setRule = false,
    String? rule,
  }) async {
    final current = _currentRow ?? widget.todo;
    if (_isUnknownLegacy(current)) return;
    final nextDue = setDue ? due : current.dueDate;
    final nextStart = setStart ? start : current.startDate;
    final nextRule = setRule ? rule : current.rrule;
    if (nextRule != null && nextStart == null && nextDue == null) {
      _showMessage(AppLocalizations.of(context)!.repeatNeedsDate);
      return;
    }
    RecurrenceSpec? spec;
    try {
      spec = _specFor(current, nextRule, nextStart, nextDue);
    } on Object catch (error) {
      debugPrint('todo_detail: recurrence spec failed: $error');
      _showError();
      return;
    }
    try {
      await ref.read(updateTodoProvider)(
        current.id,
        TodosCompanion(
          dueDate: Value(nextDue),
          startDate: Value(nextStart),
          rrule: Value(nextRule),
          updatedAt: Value(DateTime.now()),
        ),
        recurrenceSpec: spec,
        replaceRecurrence: true,
      );
    } on Object catch (error) {
      debugPrint('todo_detail: schedule update failed: $error');
      _showError();
    }
  }

  RecurrenceSpec? _specFor(
    Todo current,
    String? rule,
    DateTime? start,
    DateTime? due,
  ) {
    if (rule == null) return null;
    final anchorDate = start ?? due;
    if (anchorDate == null) return null;
    final local = anchorDate.toLocal();
    final asDate = local.hour == 0 && local.minute == 0;
    ensureTodoRecurrenceTimeZonesInitialized();
    final existing = TodoRecurrence.fromTodo(current).spec;
    return RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: start != null
            ? RecurrenceAnchorSource.start
            : RecurrenceAnchorSource.due,
        value: asDate
            ? LocalDate(local.year, local.month, local.day)
            : LocalDateTime(
                local.year,
                local.month,
                local.day,
                local.hour,
                local.minute,
                local.second,
              ),
      ),
      timeZone: existing?.timeZone ?? tz.local.name,
      rrule: rule.startsWith('RRULE:') ? rule.substring(6) : rule,
    );
  }

  Future<void> _toggleCompletion(Todo live, bool completed) async {
    try {
      await toggleTodoCompletion(
        context,
        ref,
        todo: live,
        completed: !completed,
      );
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
    }
  }

  Future<void> _delete(Todo live) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.moveToTrash),
        content: Text(l.confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.moveToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = live.id;
    final restore = ref.read(restoreTodoProvider);
    await ref.read(deleteTodoProvider)(id);
    if (!mounted) return;
    _deletedNotified = true;
    if (widget.onDeleted != null) {
      widget.onDeleted!();
    } else {
      _leaveToSource(context);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(id)),
      ),
    );
  }

  void _showError() {
    if (!mounted) return;
    _showMessage(AppLocalizations.of(context)!.actionFailedRetry);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A deleted object cannot stay on screen. Pop the detail route so the user
/// lands on the list they came from, falling back to Home for deep links.
void _leaveToSource(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    context.pop();
    return;
  }
  router?.go('/');
}

class _PaneDot extends StatelessWidget {
  const _PaneDot({required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _PaneCloseButton extends StatelessWidget {
  const _PaneCloseButton({required this.onPressed, required this.tooltip});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onPressed,
              hoverColor: ds.surface2,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(CupertinoIcons.xmark, size: 16, color: ds.ink3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneInlineClear extends StatelessWidget {
  const _PaneInlineClear({
    required this.onPressed,
    required this.tooltip,
    required this.size,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onPressed,
              hoverColor: ds.surface2,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(CupertinoIcons.xmark, size: 13, color: ds.ink3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneFieldRow extends StatelessWidget {
  const _PaneFieldRow({
    required this.label,
    required this.height,
    this.value,
    this.valueChild,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final String label;
  final double height;
  final String? value;
  final Widget? valueChild;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final content = SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 16 / 11,
                color: ds.ink3,
              ),
            ),
          ),
          Expanded(
            child:
                valueChild ??
                Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        value ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          color: ds.ink,
                        ),
                      ),
                    ),
                  ],
                ),
          ),
          if (trailing != null) trailing!,
          if (showChevron)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                CupertinoIcons.chevron_forward,
                size: 13,
                color: ds.faint,
              ),
            ),
        ],
      ),
    );
    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: content,
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, hoverColor: ds.surface2, child: row),
      ),
    );
  }
}

class _PaneButton extends StatelessWidget {
  const _PaneButton({
    required this.label,
    required this.onPressed,
    required this.height,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final bg = primary ? ds.primary : ds.surface;
    final fg = primary ? ds.onPrimary : (danger ? ds.danger : ds.ink2);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: primary ? Colors.transparent : ds.line,
                  ),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: height >= 44 ? 14 : 12,
                    fontWeight: height >= 44
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: fg,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
