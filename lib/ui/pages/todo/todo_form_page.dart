import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/todo/legacy_recurrence_dialog.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

/// A subtask the form has staged but not written yet.
class DraftSubtask {
  const DraftSubtask({
    required this.summary,
    this.id,
    this.isCompleted = false,
  });

  final int? id;
  final String summary;
  final bool isCompleted;

  @override
  bool operator ==(Object other) =>
      other is DraftSubtask &&
      other.id == id &&
      other.summary == summary &&
      other.isCompleted == isCompleted;

  @override
  int get hashCode => Object.hash(id, summary, isCompleted);
}

/// Everything the form is holding. Two snapshots difference decides whether
/// leaving has to ask for confirmation.
class _TodoSnapshot {
  const _TodoSnapshot({
    required this.summary,
    required this.description,
    required this.calendarId,
    required this.priority,
    required this.deadline,
    required this.startDate,
    required this.rrule,
    required this.tagIds,
    required this.executions,
    required this.reminders,
    required this.attachments,
    required this.subtasks,
    required this.removedSubtasks,
  });

  final String summary;
  final String description;
  final int? calendarId;
  final int priority;
  final DateTime? deadline;
  final DateTime? startDate;
  final String? rrule;
  final Set<int> tagIds;
  final List<DraftExecution> executions;
  final List<DraftReminder> reminders;
  final List<DraftAttachment> attachments;
  final List<DraftSubtask> subtasks;
  final Set<int> removedSubtasks;

  @override
  bool operator ==(Object other) =>
      other is _TodoSnapshot &&
      other.summary == summary &&
      other.description == description &&
      other.calendarId == calendarId &&
      other.priority == priority &&
      other.deadline == deadline &&
      other.startDate == startDate &&
      other.rrule == rrule &&
      _setEquals(other.tagIds, tagIds) &&
      _listEquals(other.executions, executions) &&
      _listEquals(other.reminders, reminders) &&
      _listEquals(other.attachments, attachments) &&
      _listEquals(other.subtasks, subtasks) &&
      _setEquals(other.removedSubtasks, removedSubtasks);

  @override
  int get hashCode => Object.hash(
    summary,
    description,
    calendarId,
    priority,
    deadline,
    startDate,
    rrule,
    Object.hashAll(tagIds),
    Object.hashAll(executions),
    Object.hashAll(reminders),
    Object.hashAll(attachments),
    Object.hashAll(subtasks),
    Object.hashAll(removedSubtasks),
  );
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One page for "write a todo": creating and editing differ only in whether a
/// row already exists, and splitting them is what made the app feel like two
/// products. Passing [todo] edits it; omitting it creates one.
///
/// Everything in the form is a draft until Save. That is what makes Cancel mean
/// what it says: leaving writes nothing at all, including tags, reminders,
/// attachments and subtasks.
class TodoFormPage extends ConsumerStatefulWidget {
  const TodoFormPage({
    super.key,
    this.todo,
    this.parentId,
    this.source,
    this.initialExecutionStart,
    this.initialExecutionEnd,
  });

  final Todo? todo;
  final int? parentId;
  final String? source;

  /// Set when the form was opened from a calendar slot: the new todo arrives
  /// already scheduled there, in one save instead of create-then-schedule.
  final DateTime? initialExecutionStart;
  final DateTime? initialExecutionEnd;

  @override
  ConsumerState<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends ConsumerState<TodoFormPage> {
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _calendarId;
  int _priority = 0;
  DateTime? _deadline;
  DateTime? _startDate;
  String? _rrule;
  bool _saving = false;
  bool _aiLoading = false;
  Set<int> _tagIds = {};
  List<DraftExecution> _executions = [];
  List<DraftReminder> _reminders = [];
  List<DraftAttachment> _attachments = [];
  List<DraftSubtask> _subtasks = [];
  final Set<int> _removedSubtaskIds = {};

  /// The values the form opened with. Dirty means "differs from these", which
  /// is the only thing that decides whether leaving asks for confirmation.
  /// Null while the existing associations are still being read, because until
  /// then the form has no honest baseline to compare against.
  _TodoSnapshot? _initial;

  bool get _isEditing => widget.todo != null;

  /// An imported recurrence the app cannot interpret yet. Its date fields are
  /// left untouched until the user says what they mean. This affects how the
  /// recurrence fields are read, never whether Save updates or creates.
  bool get _unknownLegacy =>
      _isEditing && TodoRecurrence.fromTodo(widget.todo!).isUnknownLegacy;

  @override
  void initState() {
    super.initState();
    final todo = widget.todo;
    if (todo != null) {
      _calendarId = todo.calendarId;
      _summaryController.text = todo.summary;
      _descriptionController.text = todo.description ?? '';
      _priority = todo.priority;
      _deadline = todo.dueDate;
      _startDate = todo.startDate;
      _rrule = todo.rrule;
      _seedAssociations(todo.id);
    } else {
      final start = widget.initialExecutionStart;
      final end = widget.initialExecutionEnd;
      if (start != null && end != null) {
        _executions = [DraftExecution(start: start, end: end)];
        _deadline = DateTime(start.year, start.month, start.day);
      }
      Future.microtask(() async {
        final calendars = await ref.read(calendarsProvider.future);
        if (calendars.isNotEmpty && mounted) {
          setState(() => _calendarId = calendars.first.id);
        }
        if (mounted) setState(() => _initial = _snapshot());
      });
    }
  }

  /// The existing tags, reminders, attachments and subtasks are the baseline
  /// the draft is compared against. Reading them before the user can type is
  /// what stops a freshly opened form from looking dirty.
  Future<void> _seedAssociations(int todoId) async {
    final tags = await ref.read(todoTagsProvider(todoId).future);
    final reminders = await ref.read(todoRemindersProvider(todoId).future);
    final attachments = await ref.read(todoAttachmentsProvider(todoId).future);
    final executions = await ref.read(
      taskAllocationsForTodoProvider(todoId).future,
    );
    final subtasks = await ref.read(subtasksProvider(todoId).future);
    if (!mounted) return;
    setState(() {
      _tagIds = tags.map((tag) => tag.id).toSet();
      _reminders = [
        for (final row in reminders)
          DraftReminder(id: row.id, triggerTime: row.triggerTime),
      ];
      _attachments = [
        for (final row in attachments) DraftAttachment.fromRow(row),
      ];
      _executions = [
        for (final row in executions.where((row) => row.state == 'active'))
          DraftExecution(
            id: row.id,
            start: row.startAt,
            end: row.endAt,
            occurrenceId: row.occurrenceId,
          ),
      ];
      _subtasks = [
        for (final row in subtasks)
          DraftSubtask(
            id: row.id,
            summary: row.summary,
            isCompleted: row.status == 'COMPLETED',
          ),
      ];
      _initial = _snapshot();
    });
  }

  _TodoSnapshot _snapshot() => _TodoSnapshot(
    summary: _summaryController.text.trim(),
    description: _descriptionController.text.trim(),
    calendarId: _calendarId,
    priority: _priority,
    deadline: _deadline,
    startDate: _startDate,
    rrule: _rrule,
    tagIds: {..._tagIds},
    executions: [..._executions],
    reminders: [..._reminders],
    attachments: [..._attachments],
    subtasks: [..._subtasks],
    removedSubtasks: {..._removedSubtaskIds},
  );

  bool get _isDirty {
    final initial = _initial;
    if (initial == null) return false;
    return _snapshot() != initial;
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  DateTime? get _anchorDate => _startDate ?? _deadline;

  RecurrenceSpec? _recurrenceSpecForSave() {
    final rule = _rrule;
    if (rule == null) return null;
    final date = _anchorDate;
    if (date == null) {
      throw StateError('Recurring Todo requires an anchor date.');
    }
    final local = date.toLocal();
    final asDate = date.hour == 0 && date.minute == 0;
    final existing = _isEditing
        ? TodoRecurrence.fromTodo(widget.todo!).spec
        : null;
    return RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: _startDate != null
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
      // The zone is the device's; the user is never asked for one.
      timeZone: existing?.timeZone ?? _deviceTimeZone,
      rrule: rule.startsWith('RRULE:') ? rule.substring(6) : rule,
    );
  }

  String get _deviceTimeZone {
    if (_isEditing) {
      final spec = TodoRecurrence.fromTodo(widget.todo!).spec;
      if (spec != null) return spec.timeZone;
    }
    // `DateTime.timeZoneName` is an abbreviation ("CST", "GMT+8") on most
    // platforms and cannot be resolved by the tz database, which made saving a
    // recurring todo fail with "Unknown IANA timezone". tz.local is the id the
    // rest of the recurrence code already uses (`recurrenceFromTodoFields`).
    ensureTodoRecurrenceTimeZonesInitialized();
    return tz.local.name;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_saving) return;
    if (_summaryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }
    if (_startDate != null &&
        _deadline != null &&
        _startDate!.isAfter(_deadline!)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.startAfterDeadline)));
      return;
    }

    setState(() => _saving = true);
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (!mounted) return;
      if (calendars.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noCalendar)));
        setState(() => _saving = false);
        return;
      }
      final calendarId = _calendarId ?? calendars.first.id;
      final description = _descriptionController.text.trim();

      // Whether this write updates or creates is decided by one thing only:
      // whether the form was opened on an existing row. A legacy recurrence
      // rule changes how the recurrence fields are interpreted — it must
      // never turn an edit into a second insert, which is how editing an old
      // recurring todo used to leave the original untouched and add a copy.
      final int todoId;
      if (_isEditing) {
        todoId = widget.todo!.id;
        await ref.read(updateTodoProvider)(
          todoId,
          TodosCompanion(
            calendarId: Value(calendarId),
            summary: Value(_summaryController.text.trim()),
            description: Value(description.isEmpty ? null : description),
            priority: Value(_priority),
            dueDate: Value(_deadline),
            startDate: Value(_startDate),
            rrule: Value(_rrule),
            updatedAt: Value(DateTime.now()),
          ),
          recurrenceSpec: _recurrenceSpecForSave(),
          replaceRecurrence: true,
        );
      } else {
        todoId = await ref.read(createTodoProvider)(
          calendarId: calendarId,
          summary: _summaryController.text.trim(),
          priority: _priority,
          status: 'NEEDS-ACTION',
          dueDate: _deadline,
          startDate: _startDate,
          description: description.isEmpty ? null : description,
          rrule: _rrule,
          recurrenceSpec: _recurrenceSpecForSave(),
          parentId: widget.parentId,
        );
      }

      final failures = await _commitDrafts(todoId, calendarId);
      if (!mounted) return;
      if (failures.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
        debugPrint('todo_form: partial save failures: ${failures.join(', ')}');
      }
      context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
        debugPrint('todo_form: save error: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Writes everything the form staged, now that the todo row exists.
  ///
  /// Each block is independent: one failing must not abandon the rest, so the
  /// failures are collected and reported once instead of surfacing a raw
  /// exception from the middle of the commit.
  Future<List<String>> _commitDrafts(int todoId, int calendarId) async {
    final failures = <String>[];

    // Executions, reminders, tags and subtasks are diffed against what the
    // form opened with: a row that survived the draft is untouched, one that
    // vanished is removed, one that appeared is written.
    final initial = _initial;
    final initialExecutions = initial?.executions ?? const <DraftExecution>[];
    for (final item in initialExecutions.where((item) => item.id != null)) {
      if (_executions.any((other) => other.id == item.id)) continue;
      try {
        await ref.read(cancelTaskAllocationProvider)(item.id!);
      } catch (error) {
        debugPrint('todo_form: cancel execution error: $error');
        failures.add('execution');
      }
    }
    for (final item in _executions.where((item) => item.id == null)) {
      try {
        await ref.read(createTaskAllocationProvider)(
          todoId: todoId,
          startAt: item.start,
          endAt: item.end,
          occurrenceId: item.occurrenceId,
        );
      } catch (error) {
        debugPrint('todo_form: execution error: $error');
        failures.add('execution');
      }
    }

    final initialTags = initial?.tagIds ?? const <int>{};
    for (final tagId in _tagIds.difference(initialTags)) {
      try {
        await ref.read(addTagToTodoProvider)(todoId: todoId, tagId: tagId);
      } catch (error) {
        debugPrint('todo_form: addTag error: $error');
        failures.add('tag');
      }
    }
    for (final tagId in initialTags.difference(_tagIds)) {
      try {
        await ref.read(removeTagFromTodoProvider)(todoId: todoId, tagId: tagId);
      } catch (error) {
        debugPrint('todo_form: removeTag error: $error');
        failures.add('tag');
      }
    }

    final initialReminders = initial?.reminders ?? const <DraftReminder>[];
    for (final item in initialReminders.where((item) => item.id != null)) {
      if (_reminders.any((other) => other.id == item.id)) continue;
      try {
        await ref.read(deleteReminderProvider)(item.id!);
      } catch (error) {
        debugPrint('todo_form: removeReminder error: $error');
        failures.add('reminder');
      }
    }
    for (final item in _reminders.where((item) => item.id == null)) {
      try {
        await ref.read(createReminderProvider)(
          parentType: 'todo',
          parentId: todoId,
          triggerTime: item.triggerTime,
        );
      } catch (error) {
        debugPrint('todo_form: reminder error: $error');
        failures.add('reminder');
      }
    }

    final initialAttachments =
        initial?.attachments ?? const <DraftAttachment>[];
    for (final item in initialAttachments.where((item) => item.id != null)) {
      if (_attachments.any((other) => other.id == item.id)) continue;
      try {
        await ref.read(deleteAttachmentProvider)(item.id!);
      } catch (error) {
        debugPrint('todo_form: removeAttachment error: $error');
        failures.add('attachment');
      }
    }
    for (final item in _attachments.where((item) => item.id == null)) {
      try {
        await ref.read(createAttachmentProvider)(
          parentType: 'todo',
          parentId: todoId,
          fileName: item.fileName,
          mimeType: item.mimeType,
          bytes: item.bytes,
          sourcePath: item.sourcePath,
        );
      } catch (error) {
        debugPrint('todo_form: attachment error: $error');
        failures.add('attachment');
      }
    }

    final initialSubtasks = initial?.subtasks ?? const <DraftSubtask>[];
    for (final id in _removedSubtaskIds) {
      try {
        await ref.read(deleteTodoProvider)(id);
      } catch (error) {
        debugPrint('todo_form: removeSubtask error: $error');
        failures.add('subtask');
      }
    }
    for (final item in _subtasks.where((item) => item.id == null)) {
      try {
        await ref.read(createTodoProvider)(
          calendarId: calendarId,
          summary: item.summary,
          priority: 0,
          status: 'NEEDS-ACTION',
          parentId: todoId,
        );
      } catch (error) {
        debugPrint('todo_form: subtask error: $error');
        failures.add('subtask');
      }
    }
    final knownSubtasks = initialSubtasks
        .where((item) => item.id != null)
        .map((item) => item.id!)
        .toSet();
    for (final item in _subtasks.where((item) => item.id != null)) {
      final before = initialSubtasks
          .where((other) => other.id == item.id)
          .firstOrNull;
      if (before != null && before.isCompleted != item.isCompleted) {
        try {
          await ref.read(toggleTodoProvider)(
            id: item.id!,
            isCompleted: item.isCompleted,
          );
        } catch (error) {
          debugPrint('todo_form: toggle subtask error: $error');
          failures.add('subtask');
        }
      }
    }
    debugPrint('todo_form: subtasks kept: ${knownSubtasks.length}');

    return failures;
  }

  Future<void> _aiParse() async {
    final l = AppLocalizations.of(context)!;
    final text = _summaryController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }
    final config = ref.read(aiConfigProvider).value;
    if (config == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.notConfigured)));
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final result = await parseNaturalLanguage(
        config: config,
        input: text,
        type: 'todo',
      );
      if (!mounted) return;
      // The parse only fills fields the user has not answered themselves, so
      // asking the assistant to read the title never silently discards a date
      // that was already picked. Whatever it did fill is named in a snackbar:
      // fields changing without a word is indistinguishable from a bug.
      final filled = <String>[];
      setState(() {
        // The title is the text the user just wrote, so it is never replaced;
        // the assistant only fills what is still empty.
        final due = result['due_date'];
        if (due is String && _deadline == null) {
          final parsedDue = DateTime.tryParse(due);
          if (parsedDue != null) {
            _deadline = parsedDue;
            filled.add(l.deadlineRow);
          }
        }
        final priority = result['priority'];
        if (priority is int && _priority == 0) {
          _priority = priority;
          filled.add(l.priority);
        }
        final description = result['description'];
        if (description is String && _descriptionController.text.isEmpty) {
          _descriptionController.text = description;
          filled.add(l.description);
        }
      });
      if (filled.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.aiFilled(filled.join(', ')))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.aiError)));
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  /// Leaving with unsaved edits asks first. A form that silently throws work
  /// away on Back is the reason people stop trusting Back.
  Future<void> _confirmDiscard() async {
    final l = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.discardChanges),
        content: Text(l.discardChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.keepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l.discard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    // Escape belongs to the form: it goes through the same PopScope path as
    // the back button, so unsaved work is never dropped without asking.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isDirty) {
            Navigator.of(context).maybePop();
          } else {
            _confirmDiscard();
          }
        },
      },
      child: PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: WorkspacePage(
          title: _isEditing ? l.editTodo : l.newTodo,
          maxContentWidth: desktop ? 720 : null,
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(CupertinoIcons.trash, size: 18),
                onPressed: _saving ? null : _delete,
                tooltip: l.moveToTrash,
              ),
            IconButton(
              icon: _aiLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.sparkles, size: 18),
              onPressed: _aiLoading ? null : _aiParse,
              tooltip: l.aiParse,
            ),
            const SizedBox(width: AppSpacing.sm),
            PageSaveButton(label: l.save, saving: _saving, onPressed: _save),
          ],
          child: _form(context, l, desktop),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, AppLocalizations l, bool desktop) {
    final padding = EdgeInsets.fromLTRB(
      desktop ? AppSpacing.xl : AppSpacing.lg,
      AppSpacing.lg,
      desktop ? AppSpacing.xl : AppSpacing.lg,
      AppSpacing.xxl,
    );
    return ListView(
      padding: padding,
      children: [
        TextField(
          controller: _summaryController,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.sentences,
          style: AppTypography.headline,
          onChanged: (_) => setState(() {}),
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
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        if (_unknownLegacy) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildLegacyNotice(context, l),
        ] else ...[
          const SizedBox(height: AppSpacing.sm),
          ScheduleRow(
            label: l.deadlineRow,
            value: _deadline == null
                ? l.noDeadline
                : formatDeadline(context, _deadline!),
            placeholder: _deadline == null,
            emptyValue: l.noDeadline,
            clearTooltip: l.clearDeadline,
            onTap: () => _pickDeadline(context),
            onClear: _deadline == null
                ? null
                : () => setState(() => _deadline = null),
            trailing: _deadline == null
                ? null
                : PopupMenuButton<bool>(
                    tooltip: l.deadlineTime,
                    icon: const Icon(CupertinoIcons.clock, size: 16),
                    padding: EdgeInsets.zero,
                    onSelected: (addTime) =>
                        _pickDeadline(context, withTime: addTime),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: false, child: Text(l.setDeadline)),
                      PopupMenuItem(value: true, child: Text(l.deadlineTime)),
                    ],
                  ),
          ),
          RepeatRow(
            rrule: _rrule,
            anchorDate: _anchorDate,
            anchorLabel: null,
            // A repeat needs a date to count from, and its anchor is a detail
            // of the rule, not a third time field the user has to answer.
            onChanged: (value) => setState(() => _rrule = value),
            onStartDateChanged: (value) => setState(() {
              _startDate = value;
              if (value == null) _rrule = null;
            }),
            startDate: _startDate,
            needsDate: _anchorDate == null,
          ),
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          ExecutionScheduleSection(
            todo: widget.todo,
            draft: _executions,
            onDraftChanged: (value) => setState(() => _executions = value),
            deadline: _deadline,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const RowDivider(),
        _buildPriority(l),
        const SizedBox(height: AppSpacing.lg),
        _buildCalendarRow(l),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _descriptionController,
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
          onChanged: (_) => setState(() {}),
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: AppSpacing.lg),
        TagChips(
          selectedIds: _tagIds,
          onSelectedIdsChanged: (value) => setState(() => _tagIds = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        RemindersSection(
          parentType: 'todo',
          parentId: widget.todo?.id,
          anchorTime: _deadline,
          draft: _reminders,
          onDraftChanged: (value) => setState(() => _reminders = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        AttachmentList(
          parentType: 'todo',
          parentId: widget.todo?.id,
          draft: _attachments,
          onDraftChanged: (value) => setState(() => _attachments = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSubtasks(l),
      ],
    );
  }

  Widget _buildLegacyNotice(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final supported = legacyRuleIsSupported(widget.todo!.rrule ?? '');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            supported ? l.recurringNeedsRepair : l.recurringBroken,
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            supported ? l.recurringNeedsRepairHint : l.recurringBrokenHint,
            style: AppTypography.caption.copyWith(
              color: context.semantic.textSecondary,
            ),
          ),
          if (supported) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: _repairLegacyRecurrence,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(l.recurringNeedsRepair),
            ),
          ],
        ],
      ),
    );
  }

  /// The one question the app genuinely cannot answer for the user: which date
  /// the old series repeats from. Everything else about it is then derived.
  Future<void> _repairLegacyRecurrence() async {
    final repaired = await confirmLegacyRecurrence(context, ref, widget.todo!);
    if (!repaired || !mounted) return;
    final fresh = await ref.read(allTodosProvider.future);
    final row = fresh.where((t) => t.id == widget.todo!.id).firstOrNull;
    if (row == null || !mounted) return;
    setState(() {
      _deadline = row.dueDate;
      _startDate = row.startDate;
      _rrule = row.rrule;
    });
  }

  Widget _buildPriority(AppLocalizations l) {
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
                  selected: _priority == value,
                  onSelected: (_) => setState(() => _priority = value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCalendarRow(AppLocalizations l) {
    final calendarsAsync = ref.watch(calendarsProvider);
    return calendarsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (calendars) {
        if (calendars.isEmpty) return const SizedBox.shrink();
        final selected = _calendarId ?? calendars.first.id;
        final current =
            calendars.where((c) => c.id == selected).firstOrNull ??
            calendars.first;
        return ScheduleRow(
          label: l.calendar,
          value: current.name,
          trailing: const Icon(CupertinoIcons.chevron_down, size: 12),
          onTap: calendars.length == 1
              ? null
              : () async {
                  final picked = await showModalBottomSheet<int>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final calendar in calendars)
                            ListTile(
                              leading: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: ColorUtils.parseHex(calendar.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              title: Text(calendar.name),
                              trailing: calendar.id == selected
                                  ? const Icon(
                                      CupertinoIcons.checkmark,
                                      size: 16,
                                    )
                                  : null,
                              onTap: () => Navigator.of(ctx).pop(calendar.id),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (picked != null) setState(() => _calendarId = picked);
                },
        );
      },
    );
  }

  Widget _buildSubtasks(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          l.subtasks,
          action: TextButton.icon(
            onPressed: () => _showAddSubtaskDialog(l),
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
        if (_subtasks.isEmpty)
          Text(
            l.noSubtasks,
            style: AppTypography.caption.copyWith(
              color: context.semantic.textTertiary,
            ),
          )
        else
          for (final sub in _subtasks)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      sub.isCompleted
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 18,
                      color: sub.isCompleted
                          ? Theme.of(context).colorScheme.primary
                          : context.semantic.textTertiary,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => setState(() {
                      final index = _subtasks.indexOf(sub);
                      _subtasks = [..._subtasks]
                        ..[index] = DraftSubtask(
                          id: sub.id,
                          summary: sub.summary,
                          isCompleted: !sub.isCompleted,
                        );
                    }),
                  ),
                  Expanded(
                    child: Text(
                      sub.summary,
                      style: AppTypography.body.copyWith(
                        decoration: sub.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: sub.isCompleted
                            ? context.semantic.textTertiary
                            : null,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 14),
                    tooltip: l.removeSubtask,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => setState(() {
                      _subtasks = [..._subtasks]..remove(sub);
                      if (sub.id != null) _removedSubtaskIds.add(sub.id!);
                    }),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  void _showAddSubtaskDialog(AppLocalizations l) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.addSubtask),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.subtaskHint),
          onSubmitted: (_) => _addSubtask(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => _addSubtask(ctx, controller.text),
            child: Text(l.add),
          ),
        ],
      ),
    );
  }

  void _addSubtask(BuildContext context, String text) {
    if (text.trim().isEmpty) return;
    setState(
      () => _subtasks = [..._subtasks, DraftSubtask(summary: text.trim())],
    );
    Navigator.of(context).pop();
  }

  Future<void> _pickDeadline(BuildContext context, {bool? withTime}) async {
    final now = DateTime.now();
    final picked = await pickDeadline(
      context,
      initial: _deadline ?? DateTime(now.year, now.month, now.day, 9),
      withTime: withTime ?? (_deadline != null && !_isDateOnly(_deadline!)),
    );
    if (picked != null && mounted) setState(() => _deadline = picked);
  }

  static bool _isDateOnly(DateTime value) =>
      value.hour == 0 && value.minute == 0;

  Future<void> _delete() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
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
    final todoId = widget.todo!.id;
    final restore = ref.read(restoreTodoProvider);
    await ref.read(deleteTodoProvider)(todoId);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(todoId)),
      ),
    );
  }
}
