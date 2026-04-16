import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/domain/providers/todos_provider.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';

class TodoCreatePage extends ConsumerStatefulWidget {
  const TodoCreatePage({super.key});

  @override
  ConsumerState<TodoCreatePage> createState() => _TodoCreatePageState();
}

class _TodoCreatePageState extends ConsumerState<TodoCreatePage> {
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dueDate;
  int _priority = 5;
  bool _saving = false;

  static const _priorities = [
    (label: 'None', value: 0),
    (label: 'Low', value: 9),
    (label: 'Medium', value: 5),
    (label: 'High', value: 1),
  ];

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_summaryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No calendar available')),
          );
        }
        return;
      }

      await ref.read(createTodoProvider).call(
            calendarId: calendars.first.id,
            uid: 'local-todo-${DateTime.now().millisecondsSinceEpoch}',
            summary: _summaryController.text.trim(),
            priority: _priority,
            status: 'NEEDS-ACTION',
            dueDate: _dueDate,
            description: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
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

  Future<void> _pickDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _dueDate = date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('New Todo'),
        actions: [
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
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Due date
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

          // Priority
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

          // Description
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}
