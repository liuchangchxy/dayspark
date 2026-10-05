import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/ui/widgets/time_picker/wheel_time_picker.dart';
import 'package:dayspark/core/l10n/locale_aware_rrule_delegate.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/todo/task_allocations_section.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

class TodoEditPage extends ConsumerStatefulWidget {
  final Todo todo;

  const TodoEditPage({super.key, required this.todo});

  @override
  ConsumerState<TodoEditPage> createState() => _TodoEditPageState();
}

class _TodoEditPageState extends ConsumerState<TodoEditPage> {
  late Todo _todo;
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  int _priority = 5;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  DateTime? _startDate;
  bool _saving = false;
  String? _rrule;
  bool _recurrenceIsDate = false;
  final _recurrenceTimeZoneController = TextEditingController();

  static const _priorityValues = [0, 9, 5, 1];

  bool get _unknownLegacy => TodoRecurrence.fromTodo(_todo).isUnknownLegacy;

  @override
  void initState() {
    super.initState();
    _todo = widget.todo;
    _summaryController.text = _todo.summary;
    _descriptionController.text = _todo.description ?? '';
    _priority = _todo.priority;
    _dueDate = _todo.dueDate;
    if (_dueDate != null && (_dueDate!.hour != 0 || _dueDate!.minute != 0)) {
      _dueTime = TimeOfDay.fromDateTime(_dueDate!);
    }
    _startDate = _todo.startDate;
    _rrule = _todo.rrule;
    _recurrenceIsDate =
        TodoRecurrence.fromTodo(_todo).spec?.anchor.valueType ==
        RecurrenceValueType.date;
    _recurrenceTimeZoneController.text =
        TodoRecurrence.fromTodo(_todo).spec?.timeZone ?? tz.local.name;
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    _recurrenceTimeZoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_summaryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }

    setState(() => _saving = true);
    try {
      // Combine dueDate and dueTime
      if (_dueDate != null && _dueTime != null) {
        _dueDate = DateTime(
          _dueDate!.year,
          _dueDate!.month,
          _dueDate!.day,
          _dueTime!.hour,
          _dueTime!.minute,
        );
      }

      final recurrenceSpec = _unknownLegacy ? null : _recurrenceSpecForSave();
      await ref.read(updateTodoProvider)(
        _todo.id,
        TodosCompanion(
          summary: Value(_summaryController.text.trim()),
          description: Value(
            _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
          ),
          priority: Value(_priority),
          dueDate: _unknownLegacy ? const Value.absent() : Value(_dueDate),
          startDate: _unknownLegacy ? const Value.absent() : Value(_startDate),
          rrule: _unknownLegacy ? const Value.absent() : Value(_rrule),
          updatedAt: Value(DateTime.now()),
        ),
        recurrenceSpec: recurrenceSpec,
        replaceRecurrence: !_unknownLegacy,
      );

      if (mounted) context.pop();
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

  RecurrenceSpec? _recurrenceSpecForSave() {
    final rule = _rrule;
    if (rule == null) return null;
    final recurrence = TodoRecurrence.fromTodo(_todo);
    final existing = recurrence.spec;
    if (existing == null) {
      final date = _startDate ?? _dueDate;
      if (date == null) {
        throw StateError('Recurring Todo requires an anchor date.');
      }
      final local = date.toLocal();
      return RecurrenceSpec.parse(
        anchor: RecurrenceAnchor(
          source: _startDate == null
              ? RecurrenceAnchorSource.due
              : RecurrenceAnchorSource.start,
          value: _recurrenceIsDate
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
        timeZone: _recurrenceTimeZoneController.text.trim(),
        rrule: rule.startsWith('RRULE:') ? rule.substring(6) : rule,
      );
    }
    final canonicalRule = rule.startsWith('RRULE:') ? rule.substring(6) : rule;
    if (canonicalRule == existing.rule.canonical &&
        existing.anchor.valueType ==
            (_recurrenceIsDate
                ? RecurrenceValueType.date
                : RecurrenceValueType.dateTime) &&
        _startDate == _todo.startDate &&
        _dueDate == _todo.dueDate &&
        _recurrenceTimeZoneController.text.trim() == existing.timeZone) {
      return existing;
    }
    final source = existing.anchor.source;
    final date = source == RecurrenceAnchorSource.start ? _startDate : _dueDate;
    if (date == null) {
      throw StateError('Recurring Todo requires an anchor date.');
    }
    final sourceProjectionUnchanged = source == RecurrenceAnchorSource.start
        ? _startDate == _todo.startDate
        : _dueDate == _todo.dueDate;
    final RecurrenceLocalValue value;
    if (sourceProjectionUnchanged &&
        ((existing.anchor.value is LocalDate) == _recurrenceIsDate)) {
      value = existing.anchor.value;
    } else if (_recurrenceIsDate) {
      final fields = sourceProjectionUnchanged
          ? existing.anchor.value is LocalDate
                ? existing.anchor.value as LocalDate
                : (existing.anchor.value as LocalDateTime).date
          : _localDate(date);
      value = fields;
    } else {
      final previous = existing.anchor.value;
      final fields = sourceProjectionUnchanged
          ? existing.anchor.value is LocalDate
                ? existing.anchor.value as LocalDate
                : (existing.anchor.value as LocalDateTime).date
          : _localDate(date);
      final useEditedTime = source == RecurrenceAnchorSource.due;
      final editedLocal = date.toLocal();
      value = LocalDateTime(
        fields.year,
        fields.month,
        fields.day,
        useEditedTime
            ? editedLocal.hour
            : previous is LocalDateTime
            ? previous.hour
            : 0,
        useEditedTime
            ? editedLocal.minute
            : previous is LocalDateTime
            ? previous.minute
            : 0,
        useEditedTime
            ? editedLocal.second
            : previous is LocalDateTime
            ? previous.second
            : 0,
      );
    }
    return RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(source: source, value: value),
      timeZone: _recurrenceTimeZoneController.text.trim(),
      rrule: canonicalRule,
    );
  }

  LocalDate _localDate(DateTime value) {
    final local = value.toLocal();
    return LocalDate(local.year, local.month, local.day);
  }

  Future<void> _confirmLegacyRecurrence() async {
    final l = AppLocalizations.of(context)!;
    if (!TaskAllocationsSection.legacyRuleIsSupported(_todo.rrule ?? '')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.unsupportedLegacyRecurrence)));
      return;
    }
    final confirmed = await TaskAllocationsSection.confirmLegacyRecurrence(
      context,
      ref,
      _todo,
    );
    if (!confirmed || !mounted) return;
    final db = ref.read(databaseProvider);
    final refreshed = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(_todo.id))).getSingle();
    if (!mounted) return;
    setState(() {
      _todo = refreshed;
      _rrule = refreshed.rrule;
      final recurrence = TodoRecurrence.fromTodo(refreshed);
      _recurrenceIsDate =
          recurrence.spec?.anchor.valueType == RecurrenceValueType.date;
      _recurrenceTimeZoneController.text =
          recurrence.spec?.timeZone ?? tz.local.name;
    });
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
            style: TextButton.styleFrom(foregroundColor: AppColors.lightError),
            child: Text(l.moveToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final todoId = _todo.id;
    final restore = ref.read(restoreTodoProvider);
    await ref.read(deleteTodoProvider)(todoId);
    if (!mounted) return;
    context.pop();
    // Show undo SnackBar in the parent page
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.deleted),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: l.undo, onPressed: () => restore(todoId)),
      ),
    );
  }

  void _setQuickDueDate(DateTime date) {
    setState(() => _dueDate = DateTime(date.year, date.month, date.day));
  }

  Future<void> _pickDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _dueDate = DateTime(date.year, date.month, date.day));
    }
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _startDate = DateTime(date.year, date.month, date.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final recurrenceSpec = TodoRecurrence.fromTodo(_todo).spec;
    final priorityLabels = {
      0: l.priorityNone,
      9: l.priorityLow,
      5: l.priorityMedium,
      1: l.priorityHigh,
    };
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.editTodo),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.delete),
            onPressed: _delete,
            tooltip: l.moveToTrash,
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title
          TextField(
            controller: _summaryController,
            decoration: InputDecoration(labelText: l.title),
          ),
          const SizedBox(height: 16),

          if (_unknownLegacy && _todo.rrule != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                key: const ValueKey('confirm-legacy-recurrence'),
                onPressed: _saving ? null : _confirmLegacyRecurrence,
                icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                label: Text(l.confirmLegacyRecurrenceTitle),
              ),
            ),
          if (!_unknownLegacy) ...[
            // Start date
            ListTile(
              leading: const Icon(CupertinoIcons.play),
              title: Text(l.startDate),
              subtitle: _startDate != null
                  ? Text(DateFormatters.formatDate(_startDate!))
                  : Text(l.notSet),
              onTap: _pickStartDate,
              trailing: _startDate != null
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.clear, size: 18),
                      onPressed: () => setState(() => _startDate = null),
                    )
                  : null,
              contentPadding: EdgeInsets.zero,
            ),

            // Due date
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(CupertinoIcons.calendar),
              title: Text(l.dueDate),
              subtitle: _dueDate != null
                  ? Text(DateFormatters.formatDate(_dueDate!))
                  : Text(l.notSet),
              onTap: _pickDueDate,
              trailing: _dueDate != null
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.clear, size: 18),
                      onPressed: () => setState(() => _dueDate = null),
                    )
                  : null,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),

            // Quick date chips
            _buildQuickDateChips(l, now),
            const SizedBox(height: 8),

            // Due time
            ListTile(
              leading: const Icon(CupertinoIcons.clock),
              title: Text(l.dueTime),
              subtitle: _dueTime != null
                  ? Text(
                      '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}',
                    )
                  : Text(l.notSet),
              onTap: () async {
                final time = await showWheelTimePicker(
                  context,
                  initialTime: _dueTime ?? TimeOfDay.now(),
                );
                if (time != null) setState(() => _dueTime = time);
              },
              trailing: _dueTime != null
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.clear, size: 18),
                      onPressed: () => setState(() => _dueTime = null),
                    )
                  : null,
              contentPadding: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 8),
          TaskAllocationsSection(todo: _todo),
          const SizedBox(height: 16),

          // Priority
          Text(
            l.priority,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: AppSpacing.sm,
            children: _priorityValues
                .map(
                  (v) => ChoiceChip(
                    label: Text(
                      priorityLabels[v]!,
                      style: TextStyle(
                        fontSize: AppTypography.caption.fontSize,
                      ),
                    ),
                    selected: _priority == v,
                    onSelected: (_) => setState(() => _priority = v),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(labelText: l.description),
            maxLines: 3,
          ),
          const SizedBox(height: 16),

          // Tags
          ref
              .watch(todoTagsProvider(_todo.id))
              .when(
                data: (tags) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tags,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TagChips(
                      parentType: 'todo',
                      parentId: _todo.id,
                      assignedTags: tags,
                    ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          const SizedBox(height: 16),
          AttachmentList(parentType: 'todo', parentId: _todo.id),
          const SizedBox(height: 16),

          // Subtasks
          _buildSubtasksSection(l),
          const SizedBox(height: 16),

          // Recurrence rule
          if (!_unknownLegacy)
            RRuleGenerator(
              localeBuilder: (_) => LocaleAwareRRuleTextDelegate(context),
              config: RRuleGeneratorConfig(),
              initialRRule: _rrule ?? '',
              withExcludeDates: false,
              onChange: (String rrule) {
                setState(() {
                  _rrule = rrule.isEmpty ? null : rrule;
                });
              },
            ),
          if (!_unknownLegacy && _rrule != null) ...[
            if (recurrenceSpec != null)
              Text(
                '${l.recurrenceAnchor}: '
                '${recurrenceSpec.anchor.source == RecurrenceAnchorSource.start ? l.startDate : l.dueDate} · '
                '${recurrenceSpec.anchor.value.canonical} · '
                '${recurrenceSpec.anchor.valueType == RecurrenceValueType.date ? l.dateOnly : l.dateAndTime}',
              ),
            TextField(
              key: const ValueKey('recurrence-time-zone'),
              decoration: InputDecoration(
                labelText: l.recurrenceTimeZone,
                helperText: l.recurrenceZoneBelongsToSeries,
              ),
              controller: _recurrenceTimeZoneController,
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l.dateOnly),
                  selected: _recurrenceIsDate,
                  onSelected: (_) => setState(() => _recurrenceIsDate = true),
                ),
                ChoiceChip(
                  label: Text(l.dateAndTime),
                  selected: !_recurrenceIsDate,
                  onSelected: (_) => setState(() => _recurrenceIsDate = false),
                ),
              ],
            ),
            Text(
              l.recurrenceEditAllocationWarning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickDateChips(AppLocalizations l, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfter = today.add(const Duration(days: 2));

    return Wrap(
      spacing: 8,
      runSpacing: AppSpacing.sm,
      children: [
        _quickChip(l.today, today),
        _quickChip(l.tomorrow, tomorrow),
        _quickChip(l.dayAfterTomorrow, dayAfter),
        ChoiceChip(
          label: Text(l.noDueDate),
          selected: _dueDate == null,
          onSelected: (_) => setState(() => _dueDate = null),
        ),
        ActionChip(
          label: Text(l.custom),
          avatar: const Icon(CupertinoIcons.calendar, size: 14),
          onPressed: _pickDueDate,
        ),
      ],
    );
  }

  Widget _quickChip(String label, DateTime date) {
    final isSelected =
        _dueDate != null &&
        _dueDate!.year == date.year &&
        _dueDate!.month == date.month &&
        _dueDate!.day == date.day;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setQuickDueDate(date),
    );
  }

  Widget _buildSubtasksSection(AppLocalizations l) {
    final subtasksAsync = ref.watch(subtasksProvider(_todo.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.subtasks,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(CupertinoIcons.add, size: 14),
              label: Text(l.addSubtask),
              onPressed: () => _showAddSubtaskDialog(l),
            ),
          ],
        ),
        const SizedBox(height: 8),
        subtasksAsync.when(
          data: (subtasks) {
            if (subtasks.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.noSubtasks,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: AppTypography.caption.fontSize,
                  ),
                ),
              );
            }
            return Column(
              children: subtasks.map((sub) {
                final done = sub.status == 'COMPLETED';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => ref.read(toggleTodoProvider)(
                          id: sub.id,
                          isCompleted: !done,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            done
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 18,
                            color: done
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sub.summary,
                          style: TextStyle(
                            fontSize: AppTypography.body.fontSize,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : null,
                            color: done
                                ? Theme.of(context).disabledColor
                                : null,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _deleteSubtask(sub.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            CupertinoIcons.delete,
                            size: 14,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _showAddSubtaskDialog(AppLocalizations l) {
    final controller = TextEditingController();
    showDialog(
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
      if (calendars.isEmpty) return;
      await ref.read(createTodoProvider)(
        calendarId: calendars.first.id,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
        parentId: _todo.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteSubtask(int id) async {
    await ref.read(deleteTodoProvider)(id);
  }
}
