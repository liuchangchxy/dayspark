import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
import 'package:dayspark/ui/widgets/schedule/execution_schedule_section.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/widgets/todo/legacy_recurrence_dialog.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

/// One page for "write a todo": creating and editing differ only in whether a
/// row already exists, and splitting them is what made the app feel like two
/// products. Passing [todo] edits it; omitting it creates one.
///
/// The two time questions are the whole form's spine:
///   deadline  — by when it must be done
///   execution — when the user intends to do it
/// Nothing else here exposes a model concept.
class TodoFormPage extends ConsumerStatefulWidget {
  const TodoFormPage({super.key, this.todo, this.parentId, this.source});

  final Todo? todo;
  final int? parentId;
  final String? source;

  @override
  ConsumerState<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends ConsumerState<TodoFormPage> {
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _calendarId;
  int _priority = 5;
  DateTime? _deadline;
  DateTime? _startDate;
  String? _rrule;
  bool _saving = false;
  bool _aiLoading = false;
  final Set<int> _selectedTagIds = {};
  final List<DraftExecution> _draftExecutions = [];

  bool get _isEditing => widget.todo != null;

  /// An imported recurrence the app cannot interpret yet. Its date fields are
  /// left untouched until the user says what they mean.
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
    } else {
      _deadline = null;
      Future.microtask(() async {
        final calendars = await ref.read(calendarsProvider.future);
        if (calendars.isNotEmpty && mounted) {
          setState(() => _calendarId = calendars.first.id);
        }
      });
    }
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
    return DateTime.now().timeZoneName == 'UTC'
        ? 'UTC'
        : _localZoneName();
  }

  static String _localZoneName() {
    try {
      return DateTime.now().timeZoneName;
    } on Object {
      return 'UTC';
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_summaryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }
    if (_startDate != null &&
        _deadline != null &&
        _startDate!.isAfter(_deadline!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.startDate} > ${l.deadlineTime}')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.noCalendar)));
        }
        return;
      }
      final calendarId = _calendarId ?? calendars.first.id;
      final description = _descriptionController.text.trim();

      if (_isEditing && !_unknownLegacy) {
        await ref.read(updateTodoProvider)(
          widget.todo!.id,
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
        await _writeDraftExecutions(widget.todo!.id);
        if (mounted) context.pop();
        return;
      }

      final todoId = await ref
          .read(createTodoProvider)
          .call(
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

      final failures = <String>[];
      for (final tagId in _selectedTagIds) {
        try {
          await ref.read(addTagToTodoProvider)(todoId: todoId, tagId: tagId);
        } catch (e) {
          debugPrint('todo_form: addTag error: $e');
          failures.add('$e');
        }
      }
      await _writeDraftExecutions(todoId, failures: failures);

      if (!mounted) return;
      if (failures.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.failedAction(failures.join(', ')))),
        );
      }
      context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error('$e'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _writeDraftExecutions(
    int todoId, {
    List<String>? failures,
  }) async {
    for (final item in _draftExecutions) {
      try {
        await ref.read(createTaskAllocationProvider)(
          todoId: todoId,
          startAt: item.start,
          endAt: item.end,
        );
      } catch (e) {
        debugPrint('todo_form: execution error: $e');
        failures?.add('$e');
      }
    }
  }

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
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(todoId)),
      ),
    );
  }

  Future<void> _aiParse() async {
    final l = AppLocalizations.of(context)!;
    final text = _summaryController.text.trim();
    if (text.isEmpty) return;
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
      setState(() {
        if (result['summary'] != null) {
          _summaryController.text = result['summary'] as String;
        }
        if (result['due_date'] != null) {
          _deadline = DateTime.parse(result['due_date'] as String);
        }
        if (result['priority'] != null) {
          _priority = result['priority'] as int;
        }
        if (result['description'] != null) {
          _descriptionController.text = result['description'] as String;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.aiError('$e'))));
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    return WorkspacePage(
      title: _isEditing ? l.editTodo : l.newTodo,
      maxContentWidth: desktop ? 720 : null,
      actions: [
        if (_isEditing)
          IconButton(
            icon: const Icon(CupertinoIcons.trash, size: 18),
            onPressed: _saving ? null : _delete,
            tooltip: l.moveToTrash,
            visualDensity: VisualDensity.compact,
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
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: AppSpacing.sm),
        PageSaveButton(
          label: l.save,
          saving: _saving,
          onPressed: _save,
        ),
      ],
      child: _form(context, l, desktop),
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
            label: l.deadline,
            value: _deadline == null
                ? l.noDeadline
                : formatDeadline(context, _deadline!),
            placeholder: _deadline == null,
            emptyValue: l.noDeadline,
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
                    onSelected: (addTime) => _pickDeadline(
                      context,
                      withTime: addTime,
                    ),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: false,
                        child: Text(l.setDeadline),
                      ),
                      PopupMenuItem(
                        value: true,
                        child: Text(l.deadlineTime),
                      ),
                    ],
                  ),
          ),
          // A start date is only meaningful as the anchor a series repeats
          // from. Showing it on every todo would present a third time question
          // the user never asked; a repeat falls back to the deadline instead.
          if (_rrule != null)
            ScheduleRow(
              label: l.startDate,
              value: _startDate == null
                  ? l.notSet
                  : formatDeadline(context, _startDate!),
              placeholder: _startDate == null,
              emptyValue: l.notSet,
              onTap: () => _pickStartDate(context),
              onClear: _startDate == null
                  ? null
                  : () => setState(() => _startDate = null),
            ),
          RepeatRow(
            rrule: _rrule,
            anchorDate: _anchorDate,
            anchorLabel: _anchorDate == null ? null : l.startsAtHint,
            onChanged: (value) => setState(() => _rrule = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          const RowDivider(),
          ExecutionScheduleSection(
            todo: widget.todo,
            draft: _draftExecutions,
            onDraftChanged: (value) =>
                setState(() => _draftExecutions..clear()..addAll(value)),
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
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildTags(l),
        if (_isEditing) ...[
          const SizedBox(height: AppSpacing.lg),
          RemindersSection(
            parentType: 'todo',
            parentId: widget.todo!.id,
            defaultTriggerTime: _deadline,
          ),
          const SizedBox(height: AppSpacing.lg),
          AttachmentList(parentType: 'todo', parentId: widget.todo!.id),
          const SizedBox(height: AppSpacing.lg),
          _buildSubtasks(l),
        ],
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
                minimumSize: const Size(0, 32),
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
    final repaired = await confirmLegacyRecurrence(
      context,
      ref,
      widget.todo!,
    );
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
        final current = calendars.where((c) => c.id == selected).firstOrNull ??
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

  Widget _buildTags(AppLocalizations l) {
    if (_isEditing) {
      return ref
          .watch(todoTagsProvider(widget.todo!.id))
          .when(
            data: (tags) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tags,
                  style: AppTypography.caption.copyWith(
                    color: context.semantic.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TagChips(
                  parentType: 'todo',
                  parentId: widget.todo!.id,
                  assignedTags: tags,
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          );
    }
    final tagsAsync = ref.watch(tagsProvider);
    return tagsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (allTags) {
        if (allTags.isEmpty) {
          return TextButton.icon(
            onPressed: () => context.push('/tags'),
            icon: const Icon(CupertinoIcons.tag, size: 14),
            label: Text(l.createTag),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.tags,
              style: AppTypography.caption.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: allTags.map((tag) {
                final selected = _selectedTagIds.contains(tag.id);
                return FilterChip(
                  label: Text(tag.name),
                  selected: selected,
                  selectedColor: ColorUtils.parseHex(
                    tag.color,
                  ).withValues(alpha: 0.3),
                  checkmarkColor: ColorUtils.parseHex(tag.color),
                  onSelected: (value) => setState(() {
                    if (value) {
                      _selectedTagIds.add(tag.id);
                    } else {
                      _selectedTagIds.remove(tag.id);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubtasks(AppLocalizations l) {
    final subtasksAsync = ref.watch(subtasksProvider(widget.todo!.id));
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
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        subtasksAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (subtasks) {
            if (subtasks.isEmpty) return const SizedBox.shrink();
            return Column(
              children: subtasks.map((sub) {
                final done = sub.status == 'COMPLETED';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          done
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 18,
                          color: done
                              ? Theme.of(context).colorScheme.primary
                              : context.semantic.textTertiary,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref.read(toggleTodoProvider)(
                          id: sub.id,
                          isCompleted: !done,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          sub.summary,
                          style: AppTypography.body.copyWith(
                            decoration: done ? TextDecoration.lineThrough : null,
                            color: done
                                ? context.semantic.textTertiary
                                : null,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          CupertinoIcons.xmark,
                          size: 14,
                          color: context.semantic.textTertiary,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            ref.read(deleteTodoProvider)(sub.id),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
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
          onSubmitted: (_) {
            if (controller.text.trim().isNotEmpty) {
              _createSubtask(controller.text.trim());
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _createSubtask(controller.text.trim());
                Navigator.of(ctx).pop();
              }
            },
            child: Text(l.add),
          ),
        ],
      ),
    );
  }

  Future<void> _createSubtask(String text) async {
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty || !_isEditing) return;
      final parentCalendar = widget.todo!.calendarId;
      final effective = calendars.any((c) => c.id == parentCalendar)
          ? parentCalendar
          : calendars.first.id;
      await ref.read(createTodoProvider)(
        calendarId: effective,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
        parentId: widget.todo!.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await pickDeadline(
      context,
      initial: _startDate ?? _deadline ?? DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  static bool _isDateOnly(DateTime value) =>
      value.hour == 0 && value.minute == 0;
}
