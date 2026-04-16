import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';

class EventCreatePage extends ConsumerStatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;

  const EventCreatePage({
    super.key,
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  ConsumerState<EventCreatePage> createState() => _EventCreatePageState();
}

class _EventCreatePageState extends ConsumerState<EventCreatePage> {
  late DateTime _start;
  late DateTime _end;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isAllDay = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
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
            const SnackBar(
                content: Text('No calendar available. Add one in Settings.')),
          );
        }
        return;
      }

      final createEvent = ref.read(createEventProvider);
      await createEvent(
        calendarId: calendars.first.id,
        uid: 'local-${DateTime.now().millisecondsSinceEpoch}',
        summary: _titleController.text.trim(),
        startDt: _start,
        endDt: _end,
        isAllDay: _isAllDay,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
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

  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    if (!_isAllDay) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end),
      );
      if (time == null || !mounted) return;

      final dt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
      setState(() {
        if (isStart) {
          _start = dt;
        } else {
          _end = dt;
        }
      });
    } else {
      setState(() {
        if (isStart) {
          _start = DateTime(date.year, date.month, date.day);
        } else {
          _end = DateTime(date.year, date.month, date.day);
        }
      });
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
        title: const Text('New Event'),
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
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _isAllDay,
            onChanged: (v) => setState(() => _isAllDay = v),
            title: const Text('All day'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: Text(_isAllDay ? 'Starts' : 'Starts at'),
            subtitle: Text(_formatDateTime(_start)),
            onTap: () => _pickDateTime(true),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.stop_outlined),
            title: Text(_isAllDay ? 'Ends' : 'Ends at'),
            subtitle: Text(_formatDateTime(_end)),
            onTap: () => _pickDateTime(false),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Location',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    if (_isAllDay) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
