import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:rrule_generator/src/rrule_generator_locale_register.dart';
import 'package:calendar_todo_app/core/utils/date_formatters.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';
import 'package:calendar_todo_app/domain/providers/ai_provider.dart';
import 'package:calendar_todo_app/domain/providers/reminders_provider.dart';
import 'package:calendar_todo_app/l10n/app_localizations.dart';

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
  bool _aiLoading = false;
  String? _rrule;

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
    final l = AppLocalizations.of(context)!;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.enterTitle)),
      );
      return;
    }

    if (!_isAllDay && _end.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.endBeforeStart)),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.noCalendar)),
          );
        }
        return;
      }

      final createEvent = ref.read(createEventProvider);
      final eventId = await createEvent(
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
        rrule: _rrule,
      );

      // Add default reminders
      if (!_isAllDay) {
        try {
          await ref.read(addDefaultEventRemindersProvider)(
            eventId: eventId,
            startDt: _start,
          );
        } catch (_) {}
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.error('$e'))),
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

  Future<void> _aiParse() async {
    final l = AppLocalizations.of(context)!;
    final text = _titleController.text.trim();
    if (text.isEmpty) return;

    final config = ref.read(aiConfigProvider).value;
    if (config == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.aiNotConfiguredHint)),
        );
      }
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final result = await parseNaturalLanguage(
        config: config,
        input: text,
        type: 'event',
      );
      if (mounted) {
        setState(() {
          if (result['summary'] != null) {
            _titleController.text = result['summary'] as String;
          }
          if (result['start'] != null) {
            _start = DateTime.parse(result['start'] as String);
          }
          if (result['end'] != null) {
            _end = DateTime.parse(result['end'] as String);
          }
          if (result['description'] != null) {
            _descriptionController.text = result['description'] as String;
          }
          if (result['location'] != null) {
            _locationController.text = result['location'] as String;
          }
          if (result['is_all_day'] == true) {
            _isAllDay = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.aiError('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => context.pop(),
        ),
        title: Text(l.newEvent),
        actions: [
          IconButton(
            onPressed: _aiLoading ? null : _aiParse,
            icon: _aiLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.sparkles),
            tooltip: 'AI parse',
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
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: l.title,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _isAllDay,
            onChanged: (v) => setState(() => _isAllDay = v),
            title: Text(l.allDay),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(CupertinoIcons.play),
            title: Text(l.startDate),
            subtitle: Text(_isAllDay
                ? DateFormatters.formatDate(_start)
                : DateFormatters.formatDateTime(_start)),
            onTap: () => _pickDateTime(true),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.stop),
            title: Text(l.endDate),
            subtitle: Text(_isAllDay
                ? DateFormatters.formatDate(_end)
                : DateFormatters.formatDateTime(_end)),
            onTap: () => _pickDateTime(false),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: l.description,
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: l.location,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(CupertinoIcons.location),
            ),
          ),
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

}

