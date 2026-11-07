import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
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
  const TodoDetailPage({super.key, required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    return WorkspacePage(
      title: l.todos,
      maxContentWidth: desktop ? 720 : null,
      child: TodoDetailPane(todo: todo),
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
  });

  final Todo todo;

  /// True inside the desktop split view: no page chrome, a close affordance.
  final bool embedded;

  final VoidCallback? onClose;
  final VoidCallback? onDeleted;

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
    final horizontal = widget.embedded ? AppSpacing.lg : AppSpacing.lg;

    return ListView(
      key: PageStorageKey<String>('todo-detail-$_todoId'),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.lg,
        horizontal,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('todo-detail-title'),
                controller: _summary,
                focusNode: _summaryFocus,
                style: AppTypography.headline,
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
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppTypography.headline.copyWith(
                    color: context.semantic.textTertiary,
                  ),
                ),
              ),
            ),
            if (widget.embedded)
              IconButton(
                icon: const Icon(CupertinoIcons.xmark, size: 16),
                tooltip: l.close,
                onPressed: widget.onClose,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Icon(
              completed
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 16,
              color: completed
                  ? Theme.of(context).colorScheme.primary
                  : context.semantic.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                completed ? l.completed : l.openTask,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: context.semantic.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _toggleCompletion(live, completed),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(completed ? l.markIncomplete : l.markComplete),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const RowDivider(),
        SectionLabel(l.sectionTime),
        if (legacy) ...[
          const SizedBox(height: AppSpacing.md),
          _legacyNotice(context, l, live),
        ] else ...[
          ScheduleRow(
            label: l.deadline,
            value: live.dueDate == null
                ? l.noDeadline
                : formatDeadline(context, live.dueDate!),
            placeholder: live.dueDate == null,
            emptyValue: l.noDeadline,
            clearTooltip: l.clearDeadline,
            onTap: () => _pickDue(live),
            onClear: live.dueDate == null
                ? null
                : () => _saveSchedule(setDue: true),
          ),
          RepeatRow(
            rrule: live.rrule,
            anchorDate: live.startDate ?? live.dueDate,
            onChanged: (value) => _saveSchedule(setRule: true, rule: value),
            startDate: live.startDate,
            onStartDateChanged: (value) => _saveSchedule(
              setStart: true,
              start: value,
              setRule: value == null,
              rule: value == null ? null : live.rrule,
            ),
            needsDate: live.startDate == null && live.dueDate == null,
          ),
          ExecutionScheduleSection(todo: live, deadline: live.dueDate),
        ],
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        SectionLabel(l.sectionReminder),
        RemindersSection(
          parentType: 'todo',
          parentId: live.id,
          anchorTime: live.dueDate,
        ),
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        SectionLabel(l.sectionOrganize),
        _calendar(context, l, live),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l.calendarExplanation,
          style: AppTypography.caption.copyWith(
            color: context.semantic.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _priority(context, l, live),
        const SizedBox(height: AppSpacing.sm),
        _tags(context, live),
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        SectionLabel(l.sectionContent),
        TextField(
          controller: _description,
          focusNode: _descriptionFocus,
          decoration: InputDecoration(
            hintText: l.description,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: AppTypography.body.copyWith(
              color: context.semantic.textTertiary,
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
        const SizedBox(height: AppSpacing.sm),
        _subtasks(context, l, live),
        const SizedBox(height: AppSpacing.lg),
        AttachmentList(parentType: 'todo', parentId: live.id),
        const SizedBox(height: AppSpacing.xl),
        const RowDivider(),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _delete(live),
            icon: Icon(
              CupertinoIcons.trash,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size(48, 48),
            ),
            label: Text(l.moveToTrash),
          ),
        ),
      ],
    );
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

  Widget _calendar(BuildContext context, AppLocalizations l, Todo live) {
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    if (calendars.isEmpty) return const SizedBox.shrink();
    final current = calendars.where((c) => c.id == live.calendarId).firstOrNull;
    return ScheduleRow(
      label: l.calendarField,
      value: current?.name ?? l.calendarUnavailable,
      trailing: const Icon(CupertinoIcons.chevron_down, size: 12),
      onTap: () async {
        final picked = await pickCalendar(
          context,
          ref,
          selectedId: live.calendarId,
        );
        if (picked != null) {
          await _writeBasics(calendarId: picked);
        }
      },
    );
  }

  Widget _subtasks(BuildContext context, AppLocalizations l, Todo live) {
    final subtasks = ref.watch(subtasksProvider(live.id)).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          l.subtasks,
          action: TextButton.icon(
            onPressed: () => _addSubtask(context, l, live),
            icon: const Icon(CupertinoIcons.add, size: 13),
            label: Text(l.addSubtask),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (subtasks.isEmpty)
          Text(
            l.noSubtasks,
            style: AppTypography.caption.copyWith(
              color: context.semantic.textTertiary,
            ),
          )
        else
          for (final sub in subtasks)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      sub.status == 'COMPLETED'
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 18,
                      color: sub.status == 'COMPLETED'
                          ? Theme.of(context).colorScheme.primary
                          : context.semantic.textTertiary,
                    ),
                    onPressed: () => ref.read(toggleTodoProvider)(
                      id: sub.id,
                      isCompleted: sub.status != 'COMPLETED',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      sub.summary,
                      style: AppTypography.body.copyWith(
                        decoration: sub.status == 'COMPLETED'
                            ? TextDecoration.lineThrough
                            : null,
                        color: sub.status == 'COMPLETED'
                            ? context.semantic.textTertiary
                            : null,
                      ),
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(CupertinoIcons.xmark, size: 14),
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

  Widget _priority(BuildContext context, AppLocalizations l, Todo live) {
    final labels = {
      0: l.priorityNone,
      9: l.priorityLow,
      5: l.priorityMedium,
      1: l.priorityHigh,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.priority,
          style: AppTypography.caption.copyWith(
            color: context.semantic.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: const [0, 9, 5, 1]
              .map(
                (value) => ChoiceChip(
                  label: Text(labels[value]!),
                  selected: live.priority == value,
                  onSelected: (_) => _savePriority(value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _tags(BuildContext context, Todo live) {
    final assigned =
        ref.watch(todoTagsProvider(live.id)).valueOrNull ?? const [];
    return TagChips(
      parentType: 'todo',
      parentId: live.id,
      assignedTags: assigned,
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
