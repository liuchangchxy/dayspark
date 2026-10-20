import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/ui/widgets/time_picker/wheel_time_picker.dart';
import 'package:dayspark/core/l10n/locale_aware_rrule_delegate.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_selector.dart';
import 'package:dayspark/ui/widgets/tag_chips.dart';
import 'package:dayspark/ui/widgets/attachment_list.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_section.dart';
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
  late final bool _openedAsAllDay;
  String? _rrule;
  int? _selectedCalendarId;

  /// The times this page edits: the row's own DTSTART/DTEND, not the position
  /// of the occurrence that was tapped. For a plain event the two are the same
  /// value, so this is one code path for both.
  late DateTime _start;
  late DateTime _end;

  /// True for a series row or any of its occurrences — both write to the same
  /// row, so both have to say so.
  bool get _isRecurring => widget.event.rrule != null;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _start = _event.seriesStart;
    _end = _event.seriesEnd;
    _titleController.text = _event.title;
    _descriptionController.text = _event.description ?? '';
    _locationController.text = _event.location ?? '';
    _isAllDay = _event.isAllDay;
    _openedAsAllDay = _event.isAllDay;
    _rrule = _event.rrule;
    _selectedCalendarId = _event.calendarId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// All-day events are stored at midnight. Existing all-day rows keep
  /// whatever they already carry — normalising on every save would move a
  /// series' DTSTART that the user never touched.
  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool get _normaliseAllDay => _isAllDay && !_openedAsAllDay;

  DateTime get _startDt => _normaliseAllDay ? _dateOnly(_start) : _start;

  DateTime get _endDt => _normaliseAllDay ? _dateOnly(_end) : _end;

  String? get _descriptionText {
    final text = _descriptionController.text.trim();
    return text.isEmpty ? null : text;
  }

  String? get _locationText {
    final text = _locationController.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }

    final start = _startDt;
    final end = _endDt;
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.endBeforeStart)));
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = _event.copyWithData(
        calendarId: _selectedCalendarId,
        // Only the row's own times are written. The tapped occurrence's
        // position never reaches the companion, so a title-only edit cannot
        // move DTSTART even by accident.
        seriesStart: start,
        seriesEnd: end,
        title: _titleController.text.trim(),
        description: _descriptionText,
        location: _locationText,
        rrule: _rrule,
        isAllDay: _isAllDay,
      );
      await ref.read(updateEventProvider)(
        _event.drifId,
        updated.toUpdateCompanion(),
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

  Future<void> _delete() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        // A recurring row is one series, not one occurrence: say so, or the
        // user reads "delete this" as "delete the one I tapped".
        content: Text(
          _isRecurring
              ? l.deleteRecurringEventConfirm(_event.title)
              : l.deleteEventConfirm(_event.title),
        ),
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
    final current = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    if (_isAllDay) {
      setState(() {
        final picked = DateTime(date.year, date.month, date.day);
        if (isStart) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
      return;
    }

    final time = await showWheelTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _start = dt;
      } else {
        _end = dt;
      }
    });
  }

  Widget _buildSeriesNotice(AppLocalizations l) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.repeat,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l.recurringSeriesNotice,
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
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
          if (_isRecurring) _buildSeriesNotice(l),
          CalendarSelector(
            selectedId: _selectedCalendarId,
            onChanged: (id) => setState(() => _selectedCalendarId = id),
          ),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(labelText: l.title),
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
            subtitle: Text(
              _isAllDay
                  ? DateFormatters.formatDate(_start)
                  : DateFormatters.formatDateTime(_start),
            ),
            onTap: () => _pickDateTime(true),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.stop),
            title: Text(l.endDate),
            subtitle: Text(
              _isAllDay
                  ? DateFormatters.formatDate(_end)
                  : DateFormatters.formatDateTime(_end),
            ),
            onTap: () => _pickDateTime(false),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(labelText: l.description),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: l.location,
              prefixIcon: const Icon(CupertinoIcons.location),
            ),
          ),
          const SizedBox(height: 16),
          // Tags
          ref
              .watch(eventTagsProvider(_event.drifId))
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
          RemindersSection(
            parentType: 'event',
            parentId: _event.drifId,
            defaultTriggerTime: _start.subtract(const Duration(minutes: 15)),
          ),
          const SizedBox(height: 16),
          // Recurrence rule
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
        ],
      ),
    );
  }
}
