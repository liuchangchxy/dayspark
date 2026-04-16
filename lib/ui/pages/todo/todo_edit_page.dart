import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:calendar_todo_app/core/theme/app_colors.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/domain/providers/todos_provider.dart';
import 'package:calendar_todo_app/domain/providers/database_provider.dart';

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
  bool _saving = false;

  static const _priorities = [
    (label: 'None', value: 0),
    (label: 'Low', value: 9),
    (label: 'Medium', value: 5),
    (label: 'High', value: 1),
  ];

  @override
  void initState() {
    super.initState();
    _todo = widget.todo;
    _summaryController.text = _todo.summary;
    _descriptionController.text = _todo.description ?? '';
    _priority = _todo.priority;
    _dueDate = _todo.dueDate;
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_summaryController.text.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await (db.update(db.todos)..where((t) => t.id.equals(_todo.id))).write(
        TodosCompanion(
          summary: Value(_summaryController.text.trim()),
          description: Value(_descriptionController.text.trim().isNotEmpty
              ? _descriptionController.text.trim()
              : null),
          priority: Value(_priority),
          dueDate: Value(_dueDate),
          isDirty: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Todo'),
        content: Text('Delete "${_todo.summary}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.lightError),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(deleteTodoProvider)(_todo.id);
    if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Edit Todo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
            tooltip: 'Delete',
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _summaryController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Due date'),
            subtitle: _dueDate != null
                ? Text(
                    '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}')
                : const Text('Not set'),
            onTap: _pickDueDate,
            trailing: _dueDate != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _dueDate = null),
                  )
                : null,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          const Text('Priority',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: _priorities
                .map((p) => ButtonSegment(value: p.value, label: Text(p.label)))
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
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
