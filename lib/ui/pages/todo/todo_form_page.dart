import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/services/attachment_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/todo/legacy_recurrence_dialog.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
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
    this.initialDueDate,
    this.initialExecutionStart,
    this.initialExecutionEnd,
  });

  final Todo? todo;
  final int? parentId;
  final String? source;

  /// Visible prefill from a context that explicitly carries a date. It is
  /// shown as an editable deadline row, never written silently.
  final DateTime? initialDueDate;

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
  bool _completed = false;
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
      _completed = todo.status == 'COMPLETED';
      _seedAssociations(todo.id);
    } else {
      final start = widget.initialExecutionStart;
      final end = widget.initialExecutionEnd;
      if (start != null && end != null) {
        _executions = [DraftExecution(start: start, end: end)];
      }
      _deadline = widget.initialDueDate;
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

      // Bytes first, and outside the transaction: a source file that has gone
      // missing has to fail the save before anything is written, not halfway
      // through it.
      final staged = <({DraftAttachment draft, Uint8List bytes})>[];
      for (final item in _attachments.where((a) => a.id == null)) {
        staged.add((
          draft: item,
          bytes: await ref.read(stageAttachmentProvider)(
            bytes: item.bytes,
            sourcePath: item.sourcePath,
            fileName: item.fileName,
          ),
        ));
      }

      final db = ref.read(databaseProvider);
      final uploaded = <({int id, List<int>? bytes})>[];
      final residue = <AttachmentResidue?>[];
      final stagedFiles = <String?>[];

      // One scope for the whole draft. Save means "the draft as a whole", so
      // a failure anywhere has to leave the database exactly as it was —
      // otherwise the title lands, the attachment does not, and the page
      // closes on a form that only half exists.
      await RecordScope.run(db, (tx) async {
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

        try {
          await _commitDrafts(
            tx,
            todoId,
            calendarId,
            staged,
            uploaded,
            residue,
            stagedFiles,
          );
        } catch (error) {
          // The row is gone with the rollback, but the file this transaction
          // already wrote is not — and SQLite may hand the same id to a later
          // insert, which would adopt the orphan as its own.
          await ref.read(discardStagedFilesProvider)(stagedFiles);
          rethrow;
        }
      });

      // Past the commit: the network and the filesystem have no business
      // holding a transaction open, and neither can roll one back.
      await ref.read(uploadAttachmentsProvider)(uploaded);
      for (final item in residue) {
        await ref.read(discardAttachmentResidueProvider)(item);
      }
      if (!mounted) return;
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

  /// Writes everything the form staged, inside the caller's transaction.
  ///
  /// Nothing is swallowed here. Save commits the whole draft, so a failed tag
  /// write has to take the title down with it rather than leave a row that is
  /// half of what the user was looking at.
  Future<void> _commitDrafts(
    RecordScope tx,
    int todoId,
    int calendarId,
    List<({DraftAttachment draft, Uint8List bytes})> staged,
    List<({int id, List<int>? bytes})> uploaded,
    List<AttachmentResidue?> residue,
    List<String?> stagedFiles,
  ) async {
    // Executions, reminders, tags and subtasks are diffed against what the
    // form opened with: a row that survived the draft is untouched, one that
    // vanished is removed, one that appeared is written.
    final initial = _initial;
    final initialExecutions = initial?.executions ?? const <DraftExecution>[];
    for (final item in initialExecutions.where((item) => item.id != null)) {
      if (_executions.any((other) => other.id == item.id)) continue;
      await ref.read(cancelTaskAllocationProvider)(item.id!);
    }
    for (final item in _executions.where((item) => item.id == null)) {
      await ref.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: item.start,
        endAt: item.end,
        occurrenceId: item.occurrenceId,
      );
    }

    final initialTags = initial?.tagIds ?? const <int>{};
    for (final tagId in _tagIds.difference(initialTags)) {
      await ref.read(addTagToTodoProvider)(todoId: todoId, tagId: tagId);
    }
    for (final tagId in initialTags.difference(_tagIds)) {
      await ref.read(removeTagFromTodoProvider)(todoId: todoId, tagId: tagId);
    }

    final initialReminders = initial?.reminders ?? const <DraftReminder>[];
    for (final item in initialReminders.where((item) => item.id != null)) {
      if (_reminders.any((other) => other.id == item.id)) continue;
      await ref.read(deleteReminderProvider)(item.id!);
    }
    for (final item in _reminders.where((item) => item.id == null)) {
      await ref.read(createReminderProvider)(
        parentType: 'todo',
        parentId: todoId,
        triggerTime: item.triggerTime,
      );
    }

    final initialAttachments =
        initial?.attachments ?? const <DraftAttachment>[];
    for (final item in initialAttachments.where((item) => item.id != null)) {
      if (_attachments.any((other) => other.id == item.id)) continue;
      residue.add(await ref.read(deleteAttachmentRowProvider)(tx, item.id!));
    }
    for (final item in staged) {
      final stage = await ref.read(insertAttachmentRowProvider)(
        tx,
        parentType: 'todo',
        parentId: todoId,
        fileName: item.draft.fileName,
        mimeType: item.draft.mimeType,
        data: item.bytes,
        onFileWritten: stagedFiles.add,
      );
      uploaded.add((id: stage.id, bytes: item.bytes));
    }

    for (final id in _removedSubtaskIds) {
      await ref.read(deleteTodoProvider)(id);
    }
    for (final item in _subtasks.where((item) => item.id == null)) {
      await ref.read(createTodoProvider)(
        calendarId: calendarId,
        summary: item.summary,
        priority: 0,
        status: 'NEEDS-ACTION',
        parentId: todoId,
      );
    }
    final initialSubtasks = initial?.subtasks ?? const <DraftSubtask>[];
    for (final item in _subtasks.where((item) => item.id != null)) {
      final before = initialSubtasks
          .where((other) => other.id == item.id)
          .firstOrNull;
      if (before != null && before.isCompleted != item.isCompleted) {
        await ref.read(toggleTodoProvider)(
          id: item.id!,
          isCompleted: item.isCompleted,
        );
      }
    }
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
      builder: (ctx) => DsDialog(
        title: l.discardChanges,
        actions: [
          const Spacer(),
          DsButton(
            label: l.keepEditing,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.discard,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          l.discardChangesBody,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: context.ds.ink2,
          ),
        ),
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
              DsIconButton(
                icon: CupertinoIcons.trash,
                size: 18,
                compact: true,
                tooltip: l.moveToTrash,
                onPressed: _saving ? null : _delete,
              ),
            if (_aiLoading)
              const SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              DsIconButton(
                icon: CupertinoIcons.sparkles,
                size: 18,
                compact: true,
                tooltip: l.aiParse,
                onPressed: _aiParse,
              ),
            const SizedBox(width: AppSpacing.s1),
            PageSaveButton(label: l.save, saving: _saving, onPressed: _save),
          ],
          child: _form(context, l, desktop),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, AppLocalizations l, bool desktop) {
    final ds = context.ds;
    return ListView(
      padding: EdgeInsets.only(
        top: desktop ? AppSpacing.s2 : 0,
        bottom: 96,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s1,
          ),
          child: TextField(
            controller: _summaryController,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: ds.ink,
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.title,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintStyle: TextStyle(
                fontSize: 22,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ds.ink3.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        if (_isEditing)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              0,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Row(
              children: [
                DsCheck(
                  checked: _completed,
                  onChanged: (value) => _toggleCompletion(value),
                ),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  _completed ? l.completed : l.openTask,
                  style: TextStyle(fontSize: 13, color: ds.ink2),
                ),
              ],
            ),
          ),
        const DsHairline(),
        DsSectionLabel(l.sectionTime),
        if (_unknownLegacy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: _buildLegacyNotice(context, l),
          )
        else ...[
          DsSettingRow(
            label: l.deadlineRow,
            value: _deadline == null
                ? l.noDeadline
                : formatDeadline(context, _deadline!),
            onTap: () => _pickDeadline(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_deadline != null)
                  DsIconButton(
                    icon: CupertinoIcons.clear,
                    size: 14,
                    compact: true,
                    tooltip: l.clearDeadline,
                    onPressed: () => setState(() => _deadline = null),
                  ),
                if (_deadline != null)
                  PopupMenuButton<bool>(
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    tooltip: l.deadlineTime,
                    icon: Icon(
                      CupertinoIcons.clock,
                      size: 16,
                      color: ds.ink3,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (addTime) =>
                        _pickDeadline(context, withTime: addTime),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: false, child: Text(l.setDeadline)),
                      PopupMenuItem(value: true, child: Text(l.deadlineTime)),
                    ],
                  ),
              ],
            ),
          ),
          RepeatRow(
            rrule: _rrule,
            anchorDate: _anchorDate,
            anchorLabel: null,
            onChanged: (value) => setState(() => _rrule = value),
            onStartDateChanged: (value) => setState(() {
              _startDate = value;
              if (value == null) _rrule = null;
            }),
            startDate: _startDate,
            needsDate: _anchorDate == null,
          ),
          ExecutionScheduleSection(
            todo: widget.todo,
            draft: _executions,
            onDraftChanged: (value) => setState(() => _executions = value),
            deadline: _deadline,
          ),
        ],
        // RemindersSection draws its own heading and add action; a second
        // label above it printed "提醒" twice, six pixels apart.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: RemindersSection(
            parentType: 'todo',
            parentId: widget.todo?.id,
            anchorTime: _deadline,
            draft: _reminders,
            onDraftChanged: (value) => setState(() => _reminders = value),
          ),
        ),
        DsSectionLabel(l.sectionOrganize),
        _buildCalendarRow(l),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s1,
            AppSpacing.s4,
            0,
          ),
          child: Text(
            l.calendarExplanation,
            style: TextStyle(fontSize: 12, height: 1.5, color: ds.ink3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s1,
          ),
          child: Text(
            l.priority,
            style: TextStyle(fontSize: 13, color: ds.ink2),
          ),
        ),
        _buildPriority(l),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            0,
          ),
          child: TagChips(
            selectedIds: _tagIds,
            onSelectedIdsChanged: (value) => setState(() => _tagIds = value),
          ),
        ),
        DsSectionLabel(l.sectionContent),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s2,
            AppSpacing.s4,
            AppSpacing.s1,
          ),
          child: DsTextField(
            controller: _descriptionController,
            hint: l.description,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        _buildSubtasks(l),
        const SizedBox(height: AppSpacing.s3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: AttachmentList(
            parentType: 'todo',
            parentId: widget.todo?.id,
            draft: _attachments,
            onDraftChanged: (value) => setState(() => _attachments = value),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleCompletion(bool completed) async {
    final todo = widget.todo;
    if (todo == null) return;
    try {
      await toggleTodoCompletion(
        context,
        ref,
        todo: todo,
        completed: completed,
      );
      if (mounted) setState(() => _completed = completed);
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
    }
  }

  Widget _buildLegacyNotice(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    final supported = legacyRuleIsSupported(widget.todo!.rrule ?? '');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: ds.warnSoft,
        borderRadius: BorderRadius.circular(AppRadii.sm + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            supported ? l.recurringNeedsRepair : l.recurringBroken,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: ds.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            supported ? l.recurringNeedsRepairHint : l.recurringBrokenHint,
            style: TextStyle(fontSize: 12, height: 1.5, color: ds.ink2),
          ),
          if (supported) ...[
            const SizedBox(height: AppSpacing.s1),
            DsButton(
              label: l.recurringNeedsRepair,
              tone: DsButtonTone.ghost,
              small: true,
              onPressed: _repairLegacyRecurrence,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s1,
        children: [
          for (final value in const [0, 9, 5, 1])
            DsChip(
              label: labels[value]!,
              selected: _priority == value,
              warm: value == 1,
              onTap: () => setState(() => _priority = value),
            ),
        ],
      ),
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
        return DsSettingRow(
          label: l.calendarField,
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ColorUtils.parseHex(current.color),
              shape: BoxShape.circle,
            ),
          ),
          value: current.name,
          onTap: () async {
            final picked = await pickCalendar(
              context,
              ref,
              selectedId: selected,
            );
            if (picked != null) setState(() => _calendarId = picked);
          },
        );
      },
    );
  }

  Widget _buildSubtasks(AppLocalizations l) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s2,
            AppSpacing.s2,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.subtasks,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ds.ink2,
                  ),
                ),
              ),
              DsButton(
                label: l.addSubtask,
                icon: CupertinoIcons.add,
                tone: DsButtonTone.ghost,
                small: true,
                onPressed: () => _showAddSubtaskDialog(l),
              ),
            ],
          ),
        ),
        if (_subtasks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s1,
              AppSpacing.s4,
              0,
            ),
            child: Text(
              l.noSubtasks,
              style: TextStyle(fontSize: 12.5, color: ds.ink3),
            ),
          )
        else
          for (final sub in _subtasks)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.s3),
                  DsCheck(
                    checked: sub.isCompleted,
                    size: 18,
                    compact: true,
                    onChanged: (_) => setState(() {
                      final index = _subtasks.indexOf(sub);
                      _subtasks = [..._subtasks]
                        ..[index] = DraftSubtask(
                          id: sub.id,
                          summary: sub.summary,
                          isCompleted: !sub.isCompleted,
                        );
                    }),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      sub.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: sub.isCompleted ? ds.ink3 : ds.ink,
                        decoration: sub.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  DsIconButton(
                    icon: CupertinoIcons.xmark,
                    size: 14,
                    compact: true,
                    tooltip: l.removeSubtask,
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
      builder: (ctx) => DsDialog(
        title: l.addSubtask,
        width: 420,
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
            tone: DsButtonTone.primary,
            onPressed: () => _addSubtask(ctx, controller.text),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(fontSize: 15, color: context.ds.ink),
          decoration: InputDecoration(hintText: l.subtaskHint),
          onSubmitted: (_) => _addSubtask(ctx, controller.text),
        ),
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
      builder: (ctx) => DsDialog(
        title: l.moveToTrash,
        width: 420,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.moveToTrash,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          l.confirmDelete,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: context.ds.ink2,
          ),
        ),
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
