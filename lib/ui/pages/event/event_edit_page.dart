import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:rrule_generator/src/rrule_generator_locale_register.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class EventEditPage extends ConsumerStatefulWidget {
  final CalendaEventAdapter event;

  const EventEditPage({super.key, required this.event});

  @override
  ConsumerState<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends ConsumerState<EventEditPage> {
  late CalendaEventAdapter _event;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  bool _saving = false;
  bool _isAllDay = false;
  String? _rrule;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _titleController.text = _event.title;
    _descriptionController.text = _event.description ?? '';
    _locationController.text = _event.location ?? '';
    _isAllDay = _event.isAllDay;
    _rrule = _event.rrule;
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

    if (!_isAllDay && _event.dateTimeRange.end.isBefore(_event.dateTimeRange.start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.endBeforeStart)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final updated = _event.copyWithData(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        rrule: _rrule,
        isAllDay: _isAllDay,
      );
      await (db.update(db.events)..where((t) => t.id.equals(_event.drifId)))
          .write(updated.toUpdateCompanion());

      // Reschedule reminders if start time changed
      final oldStart = widget.event.dateTimeRange.start;
      final newStart = updated.dateTimeRange.start;
      if (oldStart != newStart && !_isAllDay) {
        try {
          await ref.read(rescheduleRemindersProvider)(
            parentType: 'event',
            parentId: _event.drifId,
            oldReferenceTime: oldStart,
            newReferenceTime: newStart,
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

  Future<void> _delete() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.deleteEventConfirm(_event.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.lightError),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(deleteEventProvider)(_event.drifId);
    if (mounted) context.pop();
  }

  Future<void> _pickDateTime(bool isStart) async {
    final current =
        isStart ? _event.dateTimeRange.start : _event.dateTimeRange.end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    if (_isAllDay) {
      setState(() {
        if (isStart) {
          _event = _event.copyWithData(
            dateTimeRange: DateTimeRange(
                start: DateTime(date.year, date.month, date.day),
                end: _event.dateTimeRange.end),
          );
        } else {
          _event = _event.copyWithData(
            dateTimeRange: DateTimeRange(
                start: _event.dateTimeRange.start,
                end: DateTime(date.year, date.month, date.day)),
          );
        }
      });
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _event = _event.copyWithData(
          dateTimeRange: DateTimeRange(
              start: dt, end: _event.dateTimeRange.end),
        );
      } else {
        _event = _event.copyWithData(
          dateTimeRange: DateTimeRange(
              start: _event.dateTimeRange.start, end: dt),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.editEvent),
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
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: l.title,
              border: const OutlineInputBorder(),
            ),
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
                ? DateFormatters.formatDate(_event.dateTimeRange.start)
                : DateFormatters.formatDateTime(_event.dateTimeRange.start)),
            onTap: () => _pickDateTime(true),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.stop),
            title: Text(l.endDate),
            subtitle: Text(_isAllDay
                ? DateFormatters.formatDate(_event.dateTimeRange.end)
                : DateFormatters.formatDateTime(_event.dateTimeRange.end)),
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
          // Tags
          ref.watch(eventTagsProvider(_event.drifId)).when(
                data: (tags) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.tags, style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TagChips(
                      parentType: 'event',
                      parentId: _event.drifId,
                      assignedTags: tags,
                    ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          const SizedBox(height: 16),
          AttachmentList(parentType: 'event', parentId: _event.drifId),
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

