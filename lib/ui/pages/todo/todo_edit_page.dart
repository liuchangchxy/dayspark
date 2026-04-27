import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';

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
  DateTime? _startDate;
  bool _saving = false;
  String? _rrule;

  static const _priorityValues = [0, 9, 5, 1];

  @override
  void initState() {
    super.initState();
    _todo = widget.todo;
    _summaryController.text = _todo.summary;
    _descriptionController.text = _todo.description ?? '';
    _priority = _todo.priority;
    _dueDate = _todo.dueDate;
    _startDate = _todo.startDate;
    _rrule = _todo.rrule;
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
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
      final db = ref.read(databaseProvider);
      await (db.update(db.todos)..where((t) => t.id.equals(_todo.id))).write(
        TodosCompanion(
          summary: Value(_summaryController.text.trim()),
          description: Value(
            _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
          ),
          priority: Value(_priority),
          dueDate: Value(_dueDate),
          startDate: Value(_startDate),
          rrule: Value(_rrule),
          isDirty: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Reschedule reminders if due date changed
      final oldDue = widget.todo.dueDate;
      if (oldDue != _dueDate) {
        try {
          if (oldDue != null) {
            await ref.read(rescheduleRemindersProvider)(
              parentType: 'todo',
              parentId: _todo.id,
              oldReferenceTime: oldDue,
              newReferenceTime: _dueDate ?? DateTime.now(),
            );
          }
        } catch (_) {}
      }

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

  Future<void> _delete() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.lightError),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(deleteTodoProvider)(_todo.id);
    if (mounted) context.pop();
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
    if (date != null && mounted) setState(() => _dueDate = date);
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _startDate = date);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
            tooltip: l.delete,
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
            decoration: InputDecoration(
              labelText: l.title,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

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
          const SizedBox(height: 16),

          // Priority
          Text(
            l.priority,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: _priorityValues
                .map(
                  (v) =>
                      ButtonSegment(value: v, label: Text(priorityLabels[v]!)),
                )
                .toList(),
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: l.description,
              border: const OutlineInputBorder(),
            ),
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

          // Recurrence rule
          RRuleGenerator(
            locale: RRuleLocale.zh_CN,
            config: RRuleGeneratorConfig(),
            initialRRule: _rrule ?? '',
            withExcludeDates: false,
            onChange: (String rrule) {
              setState(() {
                _rrule = rrule.isEmpty ? null : rrule;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDateChips(AppLocalizations l, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfter = today.add(const Duration(days: 2));
    final nextWeek = today.add(const Duration(days: 7));

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _quickChip(l.today, today),
        _quickChip(l.tomorrow, tomorrow),
        _quickChip(l.dayAfterTomorrow, dayAfter),
        _quickChip(l.nextWeek, nextWeek),
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
}
