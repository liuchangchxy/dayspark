import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/ui/design/a2.dart' show FocusableTap;
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

/// A todo that is editable where it is read.
///
/// The same [TodoDetailPane] is the mobile page body and the desktop right-hand
/// pane, so the two platforms cannot drift apart. Edits are a draft: only the
/// footer's save writes them, and cancel discards them.
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
    this.inlineSummary = false,
    this.onClose,
    this.onDeleted,
    this.clock,
  });

  final Todo todo;

  /// True inside the desktop split view: no page chrome, a close affordance.
  final bool embedded;

  /// The wide-desktop inline column opens on a read-only summary and only
  /// shows the draft editor after its edit action, so reading never writes.
  final bool inlineSummary;

  final VoidCallback? onClose;
  final VoidCallback? onDeleted;
  final DateTime Function()? clock;

  @override
  ConsumerState<TodoDetailPane> createState() => _TodoDetailPaneState();
}

class _DraftSubtaskItem {
  final int? id;
  final String summary;
  final bool isCompleted;
  const _DraftSubtaskItem({this.id, required this.summary, this.isCompleted = false});

  @override
  bool operator ==(Object other) =>
      other is _DraftSubtaskItem &&
      other.id == id &&
      other.summary == summary &&
      other.isCompleted == isCompleted;

  @override
  int get hashCode => Object.hash(id, summary, isCompleted);
}

class _TodoDetailPaneState extends ConsumerState<TodoDetailPane> {
  final _summary = TextEditingController();
  final _description = TextEditingController();
  final _summaryFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  late _TodoDraft _snapshot;
  late _TodoDraft _draft;
  bool _dirty = false;
  bool _saving = false;
  bool _titleError = false;
  bool _repeatError = false;
  bool _saveFailed = false;
  bool _deleting = false;
  bool _deletedNotified = false;
  bool _editing = false;
  Set<int> _tagDraft = const {};
  List<DraftReminder> _reminderDraft = const [];
  List<DraftExecution> _scheduleDraft = const [];
  List<_DraftSubtaskItem> _subtaskDraft = const [];
  Set<int> _deletedSubtaskIds = const {};
  List<DraftAttachment>? _attachmentDraft;
  List<DraftAttachment> _initialAttachments = const [];

  String get _todoId => '${widget.todo.id}';

  @override
  void initState() {
    super.initState();
    _snapshot = _TodoDraft.fromTodo(widget.todo);
    _draft = _snapshot;
    _summary.text = _draft.summary;
    _description.text = _draft.description;
    _editing = !(widget.inlineSummary || widget.embedded);
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initDraftItems(widget.todo);
      });
    }
  }

  Future<void> _initDraftItems(Todo live) async {
    final subtasksFuture = ref.read(subtasksProvider(live.id).future);
    final attachmentsFuture = ref.read(todoAttachmentsProvider(live.id).future);
    final tagsFuture = ref.read(todoTagsProvider(live.id).future);
    final remindersFuture = ref.read(todoRemindersProvider(live.id).future);
    final allocationsFuture = ref.read(
      taskAllocationsForTodoProvider(live.id).future,
    );
    final currentSubtasks = await subtasksFuture;
    final currentAttachments = await attachmentsFuture;
    final assigned = await tagsFuture;
    final reminders = await remindersFuture;
    final allocations = await allocationsFuture;
    if (!mounted || _dirty) return;
    final attachmentDraftList = [
      for (final a in currentAttachments) DraftAttachment.fromRow(a),
    ];
    setState(() {
      _tagDraft = assigned.map((tag) => tag.id).toSet();
      _reminderDraft = _reminderDraftsFrom(reminders);
      _scheduleDraft = _scheduleDraftsFrom(allocations);
      _subtaskDraft = [
        for (final s in currentSubtasks)
          _DraftSubtaskItem(
            id: s.id,
            summary: s.summary,
            isCompleted: s.status == 'COMPLETED',
          ),
      ];
      _deletedSubtaskIds = const {};
      _initialAttachments = attachmentDraftList;
      _attachmentDraft = List.of(attachmentDraftList);
    });
  }

  List<DraftReminder> _reminderDraftsFrom(List<Reminder> reminders) => [
    for (final reminder in reminders)
      DraftReminder(triggerTime: reminder.triggerTime, id: reminder.id),
  ];

  List<DraftExecution> _scheduleDraftsFrom(List<TaskAllocation> allocations) => [
    for (final allocation in allocations)
      if (allocation.state == 'active')
        DraftExecution(
          id: allocation.id,
          start: allocation.startAt,
          end: allocation.endAt,
          occurrenceId: allocation.occurrenceId,
        ),
  ];

  @override
  void dispose() {
    _summaryFocus.dispose();
    _descriptionFocus.dispose();
    _summary.dispose();
    _description.dispose();
    super.dispose();
  }

  void _syncFromLive(Todo live) {
    if (_dirty || _saving || _deleting) return;
    final next = _TodoDraft.fromTodo(live);
    if (_sameDraft(next, _draft)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dirty || _saving) return;
      setState(() {
        _snapshot = next;
        _draft = next;
      });
      if (!_summaryFocus.hasFocus && _summary.text != next.summary) {
        _summary.text = next.summary;
      }
      if (!_descriptionFocus.hasFocus &&
          _description.text != next.description) {
        _description.text = next.description;
      }
    });
  }

  void _setDraft(_TodoDraft next) {
    setState(() {
      _draft = next;
      _dirty = true;
      _saveFailed = false;
    });
  }

  _TodoDraft _withDraft({
    String? summary,
    String? description,
    Object? dueDate = _unsetDraft,
    Object? startDate = _unsetDraft,
    Object? rrule = _unsetDraft,
    int? calendarId,
    int? priority,
  }) {
    return _TodoDraft(
      summary: summary ?? _draft.summary,
      description: description ?? _draft.description,
      dueDate: identical(dueDate, _unsetDraft)
          ? _draft.dueDate
          : dueDate as DateTime?,
      startDate: identical(startDate, _unsetDraft)
          ? _draft.startDate
          : startDate as DateTime?,
      rrule: identical(rrule, _unsetDraft) ? _draft.rrule : rrule as String?,
      calendarId: calendarId ?? _draft.calendarId,
      priority: priority ?? _draft.priority,
    );
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_dirty) return true;
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (ctx) => DsDialog(
        title: l.discardChanges,
        width: 380,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.discard,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(l.discardChangesBody),
      ),
    );
    return confirmed ?? false;
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
      if (all.hasError) {
        return _loadFailure(context, l, () => ref.invalidate(allTodosProvider));
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
        .where((calendar) => calendar.id == _draft.calendarId)
        .firstOrNull;
    final calendarColor = currentCalendar == null
        ? ds.ink3
        : ColorUtils.parseHex(currentCalendar.color);
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = _draft.dueDate == null
        ? null
        : DateTime(
            _draft.dueDate!.year,
            _draft.dueDate!.month,
            _draft.dueDate!.day,
          );
    final days = dueDay?.difference(today).inDays;
    final String status;
    final Color statusColor;
    if (live.status == 'CANCELLED') {
      status = l.cancelledTaskAllocation;
      statusColor = ds.ink3;
    } else if (completed) {
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
    final startLabel = _draft.startDate == null
        ? null
        : formatDeadline(context, _draft.startDate!);
    final dueLabel = _draft.dueDate == null
        ? null
        : formatDeadline(context, _draft.dueDate!);
    final leftDate = startLabel ?? dueLabel;
    final rightDate = startLabel == null ? null : dueLabel;
    final recurring = live.rrule != null || live.recurrenceRule != null;
    final isSummary = (widget.inlineSummary || widget.embedded) && !_editing;
    final summaryTags = isSummary
        ? ref.watch(todoTagsProvider(live.id)).valueOrNull
        : null;
    final summaryReminders = isSummary
        ? ref.watch(todoRemindersProvider(live.id)).valueOrNull
        : null;
    final allocations = isSummary
        ? ref.watch(taskAllocationsForTodoProvider(live.id)).valueOrNull
        : null;

    final pageContent = isSummary
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _drawerHead(context, l),
              Expanded(
                child: _summaryBody(
                  context,
                  l,
                  live,
                  completed: completed,
                  recurring: recurring,
                  status: status,
                  statusColor: statusColor,
                  leftDate: leftDate,
                  rightDate: rightDate,
                  currentCalendar: currentCalendar,
                  calendarColor: calendarColor,
                  tags: summaryTags ?? const <Tag>[],
                  reminders: summaryReminders ?? const <Reminder>[],
                  allocations: allocations ?? const <TaskAllocation>[],
                ),
              ),
              _summaryFooter(context, l, live),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.embedded) _drawerHead(context, l),
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
              if (_saveFailed) _saveErrorBanner(context, l),
              _header(
                context,
                l,
                live,
                currentCalendar?.name,
                calendarColor,
                recurring,
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
              _deadlineRow(context, l, rowHeight, mobile),
              const SizedBox(height: 8),
              if (legacy) ...[
                _legacyNotice(context, l, live),
              ] else ...[
                ExecutionScheduleSection(
                  todo: live,
                  draft: _scheduleDraft,
                  onDraftChanged: (value) {
                    setState(() {
                      _scheduleDraft = value;
                      _dirty = true;
                      _saveFailed = false;
                    });
                  },
                  deadline: _draft.dueDate,
                  enabled: !widget.inlineSummary,
                ),
                RepeatRow(
                  rrule: _draft.rrule,
                  anchorDate: _draft.startDate ?? _draft.dueDate,
                  onChanged: (value) => _setDraft(_withDraft(rrule: value)),
                  startDate: _draft.startDate,
                  onStartDateChanged: (value) => _setDraft(
                    _withDraft(
                      startDate: value,
                      rrule: value == null ? null : _draft.rrule,
                    ),
                  ),
                  needsDate: _draft.startDate == null && _draft.dueDate == null,
                ),
                if (_repeatError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _fieldError(context, l.repeatNeedsDate),
                  ),
                if (_draft.rrule != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
                    child: Text(
                      l.repeatSeriesNotice,
                      style: AppTypography.small.copyWith(color: ds.ink3),
                    ),
                  ),
              ],
              RemindersSection(
                parentType: 'todo',
                parentId: live.id,
                anchorTime: _draft.dueDate,
                draft: _reminderDraft,
                onDraftChanged: (value) {
                  setState(() {
                    _reminderDraft = value;
                    _dirty = true;
                    _saveFailed = false;
                  });
                },
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
                  currentCalendar,
                  calendarColor,
                  rowHeight,
                ),
              _priorityRow(context, l, rowHeight),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TagChips(
                  selectedIds: _tagDraft,
                  onSelectedIdsChanged: (value) {
                    setState(() {
                      _tagDraft = value;
                      _dirty = true;
                      _saveFailed = false;
                    });
                  },
                ),
              ),
              DsSectionLabel(
                l.sectionContent,
                padding: const EdgeInsets.only(top: 16, bottom: 6),
              ),
              _notes(context, l),
              const SizedBox(height: 16),
              _subtasks(context, l, live, readOnly: false),
              const SizedBox(height: 12),
              AttachmentList(
                parentType: 'todo',
                parentId: live.id,
                draft: _attachmentDraft,
                onDraftChanged: (items) {
                  setState(() {
                    _attachmentDraft = items;
                    _dirty = true;
                  });
                },
                enabled: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        _footer(context, l, live, completed, recurring, mobile, side),
      ],
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardIfNeeded();
        if (shouldPop && mounted) {
          if (widget.embedded) {
            widget.onClose?.call();
          } else {
            Navigator.of(this.context).pop();
          }
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () async {
            if (_dirty) {
              final shouldPop = await _confirmDiscardIfNeeded();
              if (shouldPop && mounted) {
                if (widget.embedded) {
                  widget.onClose?.call();
                } else {
                  Navigator.of(this.context).maybePop();
                }
              }
            } else {
              if (widget.embedded) {
                widget.onClose?.call();
              } else {
                Navigator.of(this.context).maybePop();
              }
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: pageContent,
        ),
      ),
    );
  }

  Widget _drawerHead(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 18, right: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.inlineSummary && _editing
                ? '${l.todos} · ${l.edit}'
                : l.todos,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.09 * 9.5,
              color: ds.ink3,
            ),
          ),
          _PaneCloseButton(onPressed: widget.onClose, tooltip: l.close),
        ],
      ),
    );
  }

  Widget _summaryBody(
    BuildContext context,
    AppLocalizations l,
    Todo live, {
    required bool completed,
    required bool recurring,
    required String status,
    required Color statusColor,
    required String? leftDate,
    required String? rightDate,
    required Calendar? currentCalendar,
    required Color calendarColor,
    required List<Tag> tags,
    required List<Reminder> reminders,
    required List<TaskAllocation> allocations,
  }) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final anchor = live.dueDate ?? live.startDate;
    final date = anchor == null
        ? null
        : '${DateFormat.MMMd(locale).format(anchor)} '
              '${DateFormat.E(locale).format(anchor)}';
    final eyebrow = [
      currentCalendar?.name ?? l.todoDetails,
      if (date != null) date,
    ].join(' · ');
    final completionLabel = completed
        ? l.markIncomplete
        : recurring
        ? l.completeThisOccurrence
        : l.markComplete;
    final priorityLabels = <int, String>{
      0: l.priorityNone,
      9: l.priorityLow,
      5: l.priorityMedium,
      1: l.priorityHigh,
    };
    final activeAllocations = allocations
        .where((item) => item.state == 'active')
        .toList();
    final plan = activeAllocations.isEmpty
        ? l.notScheduled
        : activeAllocations
              .map(
                (item) =>
                    formatExecutionRange(context, item.startAt, item.endAt),
              )
              .join(' · ');
    final repeatLabel = describeRepeat(
      context,
      live.rrule ?? live.recurrenceRule,
    );
    final reminderLabel = reminders.isEmpty
        ? l.noReminders
        : reminders
              .map((item) => formatDeadline(context, item.triggerTime))
              .join(' · ');
    final tagLabel = tags.isEmpty
        ? l.noTags
        : tags.map((tag) => tag.name).join(' · ');
    final note = (live.description ?? '').trim();
    final side = widget.embedded ? 18.0 : 24.0;
    const rowHeight = 58.0;
    return ListView(
      key: PageStorageKey<String>('todo-summary-$_todoId'),
      padding: EdgeInsets.fromLTRB(side, 18, side, 24),
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
                style: TextStyle(fontSize: 11, height: 16 / 11, color: ds.ink3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          live.summary,
          key: const ValueKey('todo-detail-summary-title'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 26 / 20,
            letterSpacing: 0.2,
            color: completed ? ds.ink3 : ds.ink,
            decoration: completed ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            DsCheck(
              checked: completed,
              size: 18,
              compact: true,
              label: completionLabel,
              onChanged: (_) => _toggleCompletion(live, completed),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                completionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 18 / 12, color: ds.ink3),
              ),
            ),
          ],
        ),
        _status(
          context,
          status,
          statusColor,
          completed ? 1.0 : 0.0,
          leftDate,
          rightDate,
        ),
        const SizedBox(height: 10),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-deadline'),
          label: l.deadline,
          height: rowHeight,
          value: live.dueDate == null
              ? l.noDeadline
              : formatDeadline(context, live.dueDate!),
          leading: Icon(CupertinoIcons.flag, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-plan'),
          label: l.executionSchedule,
          height: rowHeight,
          value: plan,
          leading: Icon(CupertinoIcons.clock, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-repeat'),
          label: l.repeatField,
          height: rowHeight,
          value: repeatLabel,
          leading: Icon(CupertinoIcons.repeat, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-reminders'),
          label: l.reminders,
          height: rowHeight,
          value: reminderLabel,
          leading: Icon(CupertinoIcons.bell, size: 12, color: ds.ink3),
        ),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-calendar'),
          label: l.calendarField,
          height: rowHeight,
          value: currentCalendar?.name ?? l.calendarUnavailable,
          leading: _PaneDot(color: calendarColor, size: 7),
        ),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-priority'),
          label: l.priority,
          height: rowHeight,
          value: priorityLabels[live.priority] ?? l.priorityNone,
        ),
        _PaneFieldRow(
          key: const ValueKey('todo-summary-tags'),
          label: l.tags,
          height: rowHeight,
          value: tagLabel,
        ),
        DsSectionLabel(
          l.notes,
          padding: const EdgeInsets.only(top: 16, bottom: 6),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: ds.bg,
            border: Border.all(color: ds.lineSoft),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            note.isEmpty ? '—' : note,
            key: const ValueKey('todo-summary-notes'),
            style: TextStyle(fontSize: 13, height: 22 / 13, color: ds.ink2),
          ),
        ),
        const SizedBox(height: 16),
        _subtasks(context, l, live, readOnly: true),
        const SizedBox(height: 12),
        AttachmentList(parentType: 'todo', parentId: live.id, enabled: false),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _summaryFooter(BuildContext context, AppLocalizations l, Todo live) {
    final ds = context.ds;
    return Container(
      decoration: BoxDecoration(
        color: ds.surface,
        border: Border(top: BorderSide(color: ds.line)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _PaneButton(
                  key: const ValueKey('todo-detail-edit'),
                  label: l.edit,
                  height: 48,
                  primary: true,
                  onPressed: () => _beginEdit(live),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PaneButton(
                  key: const ValueKey('todo-detail-schedule'),
                  label: l.addTaskAllocation,
                  height: 48,
                  onPressed: () => _scheduleWithPlanPicker(live),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PaneButton(
                  key: const ValueKey('todo-detail-delete-summary'),
                  label: l.deleteToTrashAction,
                  height: 48,
                  danger: true,
                  onPressed: () => _delete(live),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scheduleWithPlanPicker(Todo live) async {
    final now = widget.clock?.call() ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = DateTime(today.year, today.month, today.day, 15, 15);
    final initialEnd = initialStart.add(const Duration(minutes: 45));

    final picked = await SpecPlanPickerDialog.show(
      context,
      title: live.summary,
      initialStart: initialStart,
      initialEnd: initialEnd,
      existingBlocks: (day) async {
        final start = DateTime(day.year, day.month, day.day);
        final end = start.add(const Duration(days: 1));
        final db = ref.read(databaseProvider);
        final events = await db.eventsDao.getEventCandidates(start, end);
        final allocations = await fetchTaskAllocationsInDateRange(db, start, end);
        final blocks = calDayBlocks(
          day: start,
          events: [
            for (final event in events) CalendaEventAdapter.fromDrift(event),
          ],
          allocations: [
            for (final item in allocations)
              if (item.todo.id != live.id)
                TaskAllocationCalendarAdapter.fromItem(item),
          ],
        );
        return [
          for (final b in blocks)
            SpecPlanBlock(start: b.start, end: b.end, title: b.title),
        ];
      },
    );

    if (picked == null || !mounted) return;

    final isRecurring = live.rrule != null && live.rrule!.isNotEmpty;
    String? occurrenceId;
    if (isRecurring) {
      final selectedInstance = await TodoOccurrencePickerSheet.show(
        context,
        ref: ref,
        todo: live,
        anchorDate: picked.$1,
      );
      if (selectedInstance == null || !mounted) return;
      occurrenceId = selectedInstance.occurrenceId;
    }

    try {
      await ref.read(createTaskAllocationProvider)(
        todoId: live.id,
        occurrenceId: occurrenceId,
        startAt: picked.$1,
        endAt: picked.$2,
      );
      ref.invalidate(allActiveTaskAllocationsProvider);
      ref.invalidate(allTodosProvider);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      if (l != null) {
        showSpecToast(context, l.scheduledTodoSuccess(live.summary));
      }
    } catch (e) {
      debugPrint('todo_detail: schedule allocation failed: $e');
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      if (l != null) {
        showSpecToast(context, l.schedulingFailed);
      }
    }
  }

  Future<void> _beginEdit(Todo live) async {
    final assignedFuture = ref.read(todoTagsProvider(live.id).future);
    final remindersFuture = ref.read(todoRemindersProvider(live.id).future);
    final subtasksFuture = ref.read(subtasksProvider(live.id).future);
    final attachmentsFuture = ref.read(todoAttachmentsProvider(live.id).future);
    final allocationsFuture = ref.read(
      taskAllocationsForTodoProvider(live.id).future,
    );
    final assigned = await assignedFuture;
    final reminders = await remindersFuture;
    final currentSubtasks = await subtasksFuture;
    final currentAttachments = await attachmentsFuture;
    final allocations = await allocationsFuture;
    if (!mounted) return;
    final attachmentDraftList = [
      for (final a in currentAttachments) DraftAttachment.fromRow(a),
    ];
    final snapshot = _TodoDraft.fromTodo(live);
    setState(() {
      _snapshot = snapshot;
      _draft = snapshot;
      _summary.text = snapshot.summary;
      _description.text = snapshot.description;
      _tagDraft = assigned.map((tag) => tag.id).toSet();
      _reminderDraft = _reminderDraftsFrom(reminders);
      _scheduleDraft = _scheduleDraftsFrom(allocations);
      _subtaskDraft = [
        for (final s in currentSubtasks)
          _DraftSubtaskItem(
            id: s.id,
            summary: s.summary,
            isCompleted: s.status == 'COMPLETED',
          ),
      ];
      _deletedSubtaskIds = const {};
      _initialAttachments = attachmentDraftList;
      _attachmentDraft = List.of(attachmentDraftList);
      _dirty = false;
      _saving = false;
      _deleting = false;
      _titleError = false;
      _repeatError = false;
      _saveFailed = false;
      _editing = true;
    });
  }

  Widget _fieldError(BuildContext context, String message) {
    return Text(
      message,
      style: TextStyle(fontSize: 11, height: 16 / 11, color: context.ds.danger),
    );
  }

  Widget _saveErrorBanner(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ds.dangerSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.saveFailedNotWritten,
              style: TextStyle(
                fontSize: 12,
                height: 18 / 12,
                fontWeight: FontWeight.w600,
                color: ds.danger,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('todo-detail-retry-save'),
            onPressed: _saving ? null : _save,
            child: Text(l.retrySave),
          ),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    Todo live,
    String? calendarName,
    Color calendarColor,
    bool recurring,
  ) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toString();
    final anchor = _draft.dueDate ?? _draft.startDate;
    final date = anchor == null
        ? null
        : '${DateFormat.MMMd(locale).format(anchor)} '
              '${DateFormat.E(locale).format(anchor)}';
    final eyebrow = [
      calendarName ?? l.todoDetails,
      if (date != null) date,
    ].join(' · ');
    final completionLabel = live.status == 'COMPLETED'
        ? l.markIncomplete
        : recurring
        ? l.completeThisOccurrence
        : l.markComplete;
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
                    label: completionLabel,
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
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (value) {
                        if (!_dirty) {
                          setState(() => _dirty = true);
                        }
                        if (_titleError && value.trim().isNotEmpty) {
                          setState(() => _titleError = false);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: l.title,
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: TextStyle(fontSize: 20, color: ds.ink3),
                        errorText: _titleError ? l.titleRequired : null,
                        errorStyle: TextStyle(
                          fontSize: 11,
                          height: 16 / 11,
                          color: ds.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    double rowHeight,
    bool mobile,
  ) {
    return _PaneFieldRow(
      label: l.deadline,
      height: rowHeight,
      value: _draft.dueDate == null
          ? l.noDeadline
          : formatDeadline(context, _draft.dueDate!),
      onTap: _pickDue,
      showChevron: true,
      trailing: _draft.dueDate == null
          ? null
          : _PaneInlineClear(
              onPressed: _clearDue,
              tooltip: l.clearDeadline,
              size: mobile ? 44 : 32,
            ),
    );
  }

  Widget _calendarRow(
    BuildContext context,
    AppLocalizations l,
    Calendar? currentCalendar,
    Color calendarColor,
    double rowHeight,
  ) {
    return _PaneFieldRow(
      label: l.calendarField,
      height: rowHeight,
      leading: _PaneDot(color: calendarColor, size: 7),
      value: currentCalendar?.name ?? l.calendarUnavailable,
      onTap: _pickCalendar,
      showChevron: true,
    );
  }

  Widget _priorityRow(
    BuildContext context,
    AppLocalizations l,
    double rowHeight,
  ) {
    return _PaneFieldRow(
      key: const ValueKey('todo-priority-row'),
      label: l.priority,
      height: rowHeight,
      valueChild: Align(
        alignment: Alignment.centerLeft,
        child: _priorityChips(context, l),
      ),
    );
  }

  Widget _priorityChips(BuildContext context, AppLocalizations l) {
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
          Semantics(
            button: true,
            selected: _draft.priority == value,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('todo-priority-$value'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _setDraft(_withDraft(priority: value)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Align(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: DsChip(
                      key: ValueKey('todo-priority-visual-$value'),
                      label: labels[value]!,
                      selected: _draft.priority == value,
                      compact: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _notes(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              if (!_dirty) setState(() => _dirty = true);
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
    bool recurring,
    bool mobile,
    double side,
  ) {
    final ds = context.ds;
    final height = mobile ? 48.0 : 36.0;
    final primaryLabel = _saveFailed ? l.retrySave : l.save;
    final save = _PaneButton(
      key: const ValueKey('todo-detail-save'),
      label: primaryLabel,
      height: height,
      primary: true,
      onPressed: _saving ? null : _save,
    );
    final cancel = _PaneButton(
      key: const ValueKey('todo-detail-cancel'),
      label: l.cancel,
      height: height,
      onPressed: _saving ? null : _cancel,
    );
    final remove = _PaneButton(
      key: const ValueKey('todo-detail-delete'),
      label: l.moveToTrash,
      height: height,
      danger: true,
      onPressed: _deleting ? null : () => _delete(live),
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
        child: SizedBox(
          height: height < 48 ? 48 : height,
          child: Row(
            children: [
              Expanded(flex: 2, child: save),
              const SizedBox(width: 8),
              Expanded(child: cancel),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: remove),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCalendar() async {
    final picked = await pickCalendar(
      context,
      ref,
      selectedId: _draft.calendarId,
    );
    if (picked != null && mounted) {
      _setDraft(_withDraft(calendarId: picked));
    }
  }

  bool _isUnknownLegacy(Todo row) {
    try {
      return TodoRecurrence.fromTodo(row).isUnknownLegacy;
    } catch (_) {
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

  Widget _subtasks(
    BuildContext context,
    AppLocalizations l,
    Todo live, {
    bool readOnly = false,
  }) {
    final ds = context.ds;
    final List<_DraftSubtaskItem> items;
    if (readOnly) {
      final liveSubtasks =
          ref.watch(subtasksProvider(live.id)).valueOrNull ?? const [];
      items = [
        for (final s in liveSubtasks)
          _DraftSubtaskItem(
            id: s.id,
            summary: s.summary,
            isCompleted: s.status == 'COMPLETED',
          ),
      ];
    } else {
      items = _subtaskDraft;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.subtasks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.small.copyWith(
                  color: ds.ink2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!readOnly) ...[
              const SizedBox(width: 8),
              Flexible(
                child: DsButton(
                  label: l.addSubtask,
                  tone: DsButtonTone.ghost,
                  small: true,
                  icon: CupertinoIcons.add,
                  onPressed: () => _addSubtask(context, l, live),
                ),
              ),
            ],
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l.noSubtasks,
              style: AppTypography.small.copyWith(color: ds.ink3),
            ),
          )
        else
          for (final sub in items)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  DsCheck(
                    checked: sub.isCompleted,
                    size: 17,
                    compact: true,
                    onChanged: readOnly
                        ? null
                        : (_) => _toggleSubtaskDraft(sub),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      sub.summary,
                      style: AppTypography.body.copyWith(
                        fontSize: 14,
                        decoration: sub.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: sub.isCompleted ? ds.ink3 : ds.ink,
                      ),
                    ),
                  ),
                  if (!readOnly)
                    DsIconButton(
                      icon: CupertinoIcons.xmark,
                      size: 14,
                      compact: true,
                      tooltip: l.removeSubtask,
                      onPressed: () => _removeSubtask(sub),
                    ),
                ],
              ),
            ),
      ],
    );
  }

  void _toggleSubtaskDraft(_DraftSubtaskItem sub) {
    setState(() {
      _subtaskDraft = [
        for (final item in _subtaskDraft)
          if (item == sub)
            _DraftSubtaskItem(
              id: item.id,
              summary: item.summary,
              isCompleted: !item.isCompleted,
            )
          else
            item,
      ];
      _dirty = true;
    });
  }

  void _removeSubtask(_DraftSubtaskItem sub) {
    setState(() {
      _subtaskDraft = _subtaskDraft.where((item) => item != sub).toList();
      if (sub.id != null) {
        _deletedSubtaskIds = {..._deletedSubtaskIds, sub.id!};
      }
      _dirty = true;
    });
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
      builder: (ctx) => DsDialog(
        title: l.addSubtask,
        width: 380,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.add,
            onPressed: () => Navigator.of(ctx).pop(controller.text),
          ),
        ],
        child: DsTextField(
          controller: controller,
          autofocus: true,
          hint: l.subtaskHint,
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
      ),
    );
    controller.dispose();
    final title = text?.trim();
    if (title == null || title.isEmpty) return;
    setState(() {
      _subtaskDraft = [
        ..._subtaskDraft,
        _DraftSubtaskItem(summary: title),
      ];
      _dirty = true;
    });
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

  Future<void> _save() async {
    if (_saving) return;
    final title = _summary.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = true;
        _saveFailed = false;
      });
      _summaryFocus.requestFocus();
      return;
    }
    final anchor = _draft.startDate ?? _draft.dueDate;
    if (_draft.rrule != null && anchor == null) {
      setState(() {
        _repeatError = true;
        _saveFailed = false;
      });
      return;
    }
    final description = _description.text.trim();
    final current = _currentRow ?? widget.todo;
    final legacy = _isUnknownLegacy(current);
    RecurrenceSpec? spec;
    if (!legacy) {
      try {
        spec = _specFor(
          current,
          _draft.rrule,
          _draft.startDate,
          _draft.dueDate,
        );
      } catch (error) {
        debugPrint('todo_detail: recurrence spec failed: $error');
        if (!mounted) return;
        setState(() {
          _saveFailed = true;
          _saving = false;
        });
        return;
      }
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
      _titleError = false;
      _repeatError = false;
    });
    try {
      await ref.read(updateTodoProvider)(
        current.id,
        TodosCompanion(
          summary: Value(title),
          description: Value(description.isEmpty ? null : description),
          dueDate: Value(_draft.dueDate),
          startDate: Value(_draft.startDate),
          rrule: Value(_draft.rrule),
          calendarId: Value(_draft.calendarId),
          priority: Value(_draft.priority),
          updatedAt: Value(DateTime.now()),
        ),
        recurrenceSpec: spec,
        replaceRecurrence: !legacy,
      );
      await _saveAssociations(current.id, _draft.calendarId);
      await _refreshAssociationDrafts(current.id);
    } catch (error) {
      debugPrint('todo_detail: save failed: $error');
      if (!mounted) return;
      setState(() {
        _saveFailed = true;
        _saving = false;
      });
      return;
    }
    if (!mounted) return;
    final saved = _TodoDraft(
      summary: title,
      description: description,
      dueDate: _draft.dueDate,
      startDate: _draft.startDate,
      rrule: _draft.rrule,
      calendarId: _draft.calendarId,
      priority: _draft.priority,
    );
    setState(() {
      _snapshot = saved;
      _draft = saved;
      _dirty = false;
      _saving = false;
      _summary.text = title;
      if (widget.inlineSummary || widget.embedded) {
        _editing = false;
        _subtaskDraft = const [];
        _deletedSubtaskIds = const {};
        _attachmentDraft = null;
        _initialAttachments = const [];
      } else {
        _deletedSubtaskIds = const {};
      }
    });
  }

  Future<void> _saveAssociations(int todoId, int calendarId) async {
    final assigned = await ref.read(todoTagsProvider(todoId).future);
    final assignedIds = assigned.map((tag) => tag.id).toSet();
    final addTag = ref.read(addTagToTodoProvider);
    final removeTag = ref.read(removeTagFromTodoProvider);
    for (final tagId in _tagDraft.difference(assignedIds)) {
      await addTag(todoId: todoId, tagId: tagId);
    }
    for (final tagId in assignedIds.difference(_tagDraft)) {
      await removeTag(todoId: todoId, tagId: tagId);
    }

    final stored = await ref.read(todoRemindersProvider(todoId).future);
    final byId = {for (final reminder in stored) reminder.id: reminder};
    final kept = <int>{};
    for (final draft in _reminderDraft) {
      final id = draft.id;
      if (id == null) {
        await ref.read(createReminderProvider)(
          parentType: 'todo',
          parentId: todoId,
          triggerTime: draft.triggerTime,
        );
        continue;
      }
      kept.add(id);
      final row = byId[id];
      if (row != null && row.triggerTime != draft.triggerTime) {
        await ref.read(updateReminderProvider)(id, draft.triggerTime);
      }
    }
    for (final row in stored) {
      if (!kept.contains(row.id)) {
        await ref.read(deleteReminderProvider)(row.id);
      }
    }

    final storedAllocations = (await ref.read(
      taskAllocationsForTodoProvider(todoId).future,
    )).where((item) => item.state == 'active').toList();
    final allocationsById = {
      for (final item in storedAllocations) item.id: item,
    };
    final keptAllocationIds = <int>{};
    for (final draft in _scheduleDraft) {
      final id = draft.id;
      if (id == null) {
        await ref.read(createTaskAllocationProvider)(
          todoId: todoId,
          startAt: draft.start,
          endAt: draft.end,
          occurrenceId: draft.occurrenceId,
        );
        continue;
      }
      keptAllocationIds.add(id);
      final row = allocationsById[id];
      if (row != null &&
          (row.startAt != draft.start || row.endAt != draft.end)) {
        await ref.read(rescheduleTaskAllocationProvider)(
          id: id,
          startAt: draft.start,
          endAt: draft.end,
        );
      }
    }
    for (final row in storedAllocations) {
      if (!keptAllocationIds.contains(row.id)) {
        await ref.read(cancelTaskAllocationProvider)(row.id);
      }
    }

    // Commit subtask changes
    for (final id in _deletedSubtaskIds) {
      await ref.read(deleteTodoProvider)(id);
    }
    for (final item in _subtaskDraft.where((s) => s.id == null)) {
      await ref.read(createTodoProvider)(
        calendarId: calendarId,
        summary: item.summary,
        priority: 0,
        status: item.isCompleted ? 'COMPLETED' : 'NEEDS-ACTION',
        parentId: todoId,
      );
    }
    for (final item in _subtaskDraft.where((s) => s.id != null)) {
      await ref.read(toggleTodoProvider)(
        id: item.id!,
        isCompleted: item.isCompleted,
      );
    }

    // Commit attachment changes
    if (_attachmentDraft != null) {
      final keptAttachmentIds = _attachmentDraft!
          .map((a) => a.id)
          .whereType<int>()
          .toSet();
      for (final a in _initialAttachments) {
        if (a.id != null && !keptAttachmentIds.contains(a.id)) {
          await ref.read(deleteAttachmentProvider)(a.id!);
        }
      }
      for (final a in _attachmentDraft!.where((item) => item.id == null)) {
        await ref.read(createAttachmentProvider)(
          parentType: 'todo',
          parentId: todoId,
          fileName: a.fileName,
          mimeType: a.mimeType,
          bytes: a.bytes,
          sourcePath: a.sourcePath,
        );
      }
    }
  }

  Future<void> _refreshAssociationDrafts(int todoId) async {
    final db = ref.read(databaseProvider);
    final reminders = await (db.select(db.reminders)..where(
          (row) => row.parentType.equals('todo') & row.parentId.equals(todoId),
        ))
        .get();
    final allocations = await (db.select(
      db.taskAllocations,
    )..where((row) => row.todoId.equals(todoId))).get();
    if (!mounted) return;
    setState(() {
      _reminderDraft = _reminderDraftsFrom(reminders);
      _scheduleDraft = _scheduleDraftsFrom(allocations);
    });
  }

  void _cancel() {
    setState(() {
      _draft = _snapshot;
      _dirty = false;
      _saving = false;
      _titleError = false;
      _repeatError = false;
      _saveFailed = false;
      _summary.text = _snapshot.summary;
      _description.text = _snapshot.description;
      _tagDraft = const {};
      _reminderDraft = const [];
      _scheduleDraft = const [];
      _subtaskDraft = const [];
      _deletedSubtaskIds = const {};
      _attachmentDraft = null;
      _initialAttachments = const [];
      if (widget.inlineSummary || widget.embedded) _editing = false;
    });
    _summaryFocus.unfocus();
    _descriptionFocus.unfocus();
    if (widget.inlineSummary || (widget.embedded && !_editing)) return;
    if (widget.embedded) {
      widget.onClose?.call();
      return;
    }
    _leaveToSource(context);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final initial = _draft.dueDate ?? DateTime(now.year, now.month, now.day, 9);
    final picked = await pickDeadline(
      context,
      initial: initial,
      withTime:
          _draft.dueDate != null &&
          !(_draft.dueDate!.hour == 0 && _draft.dueDate!.minute == 0),
    );
    if (picked == null || !mounted) return;
    _setDraft(_withDraft(dueDate: picked));
  }

  void _clearDue() {
    final rule = _draft.startDate == null ? null : _draft.rrule;
    _setDraft(_withDraft(dueDate: null, rrule: rule));
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
        anchorDate: widget.clock?.call(),
      );
    } catch (error) {
      if (mounted) showCompletionError(context, error);
    }
  }

  Future<void> _delete(Todo live) async {
    if (_deleting) return;
    final l = AppLocalizations.of(context)!;
    final title = _summary.text.trim().isEmpty
        ? live.summary
        : _summary.text.trim();
    final series = live.rrule != null || live.recurrenceRule != null;
    final confirmed = await SpecDeleteConfirmDialog.show(
      context,
      title: l.deleteTodoConfirm(title),
      message: series ? l.deleteSeriesTrashNotice : l.deleteTrashNotice,
      cancelLabel: l.cancel,
      confirmLabel: l.moveToTrash,
    );
    if (confirmed != true || !mounted) return;
    final id = live.id;
    final restore = ref.read(restoreTodoProvider);
    setState(() => _deleting = true);
    try {
      await ref.read(deleteTodoProvider)(id);
    } catch (error) {
      debugPrint('todo_detail: delete failed: $error');
      if (!mounted) return;
      setState(() => _deleting = false);
      _showError();
      return;
    }
    if (!mounted) return;
    _deletedNotified = true;
    showUndoBar(
      context,
      message: l.deleted,
      undoLabel: l.undo,
      onUndo: () => restore(id),
    );
    if (widget.onDeleted != null) {
      widget.onDeleted!();
    } else {
      _leaveToSource(context);
    }
  }

  Widget _loadFailure(
    BuildContext context,
    AppLocalizations l,
    VoidCallback retry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.error,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: retry, child: Text(l.retry)),
                const SizedBox(width: AppSpacing.s2),
                TextButton(onPressed: _leaveFromFailure, child: Text(l.close)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _leaveFromFailure() {
    if (widget.embedded) {
      final close = widget.onClose;
      if (close != null) {
        close();
        return;
      }
    }
    _leaveToSource(context);
  }

  void _showError() {
    if (!mounted) return;
    showSpecToast(context, AppLocalizations.of(context)!.actionFailedRetry);
  }
}

const Object _unsetDraft = Object();

class _TodoDraft {
  const _TodoDraft({
    required this.summary,
    required this.description,
    required this.dueDate,
    required this.startDate,
    required this.rrule,
    required this.calendarId,
    required this.priority,
  });

  factory _TodoDraft.fromTodo(Todo todo) {
    return _TodoDraft(
      summary: todo.summary,
      description: todo.description ?? '',
      dueDate: todo.dueDate,
      startDate: todo.startDate,
      rrule: todo.rrule,
      calendarId: todo.calendarId,
      priority: todo.priority,
    );
  }

  final String summary;
  final String description;
  final DateTime? dueDate;
  final DateTime? startDate;
  final String? rrule;
  final int calendarId;
  final int priority;
}

bool _sameDraft(_TodoDraft a, _TodoDraft b) {
  return a.summary == b.summary &&
      a.description == b.description &&
      a.dueDate == b.dueDate &&
      a.startDate == b.startDate &&
      a.rrule == b.rrule &&
      a.calendarId == b.calendarId &&
      a.priority == b.priority;
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
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              hoverColor: ds.surface2,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Icon(CupertinoIcons.xmark, size: 13, color: ds.ink3),
                ),
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
    super.key,
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
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 16 / 11, color: ds.ink3),
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
    super.key,
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
    final bg = primary ? SpecTokens.ink : ds.surface;
    final fg = primary ? Colors.white : (danger ? ds.danger : ds.ink2);
    final enabled = onPressed != null;
    final visual = Ink(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: primary ? Colors.transparent : ds.line),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: height >= 44 ? 14 : 12,
            fontWeight: height >= 44 ? FontWeight.w600 : FontWeight.w500,
            color: fg,
            height: 1.2,
          ),
        ),
      ),
    );
    return FocusableTap(
      onTap: onPressed,
      semanticsLabel: label,
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(child: visual),
        ),
      ),
    );
  }
}
