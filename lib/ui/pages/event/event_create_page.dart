import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/ui/widgets/time_picker/wheel_time_picker.dart';
import 'package:dayspark/core/l10n/locale_aware_rrule_delegate.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_selector.dart';
import 'package:dayspark/ui/widgets/centered_content.dart';
import 'package:dayspark/ui/widgets/reminder/reminders_draft_section.dart';
import 'package:dayspark/core/theme/app_spacing.dart';

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
  int? _selectedCalendarId;
  List<DateTime> _draftReminders = [];

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  /// All-day events are stored at midnight; the time-of-day a slot prefill
  /// carried is meaningless once the event covers whole days.
  DateTime get _startDt => _isAllDay ? _dateOnly(_start) : _start;
  DateTime get _endDt => _isAllDay ? _dateOnly(_end) : _end;

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }

    // All-day ranges are validated too: DTEND is exclusive, so an end date
    // before the start date is as illegal there as it is for a timed event.
    if (_endDt.isBefore(_startDt)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.endBeforeStart)));
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

      final createEvent = ref.read(createEventProvider);
      final eventId = await createEvent(
        calendarId: _selectedCalendarId ?? calendars.first.id,
        summary: _titleController.text.trim(),
        startDt: _startDt,
        endDt: _endDt,
        isAllDay: _isAllDay,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        rrule: _rrule,
      );

      for (final trigger in _draftReminders) {
        try {
          await ref.read(createReminderProvider)(
            parentType: 'event',
            parentId: eventId,
            triggerTime: trigger,
          );
        } catch (e) {
          debugPrint('event_create: reminder error: $e');
        }
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

  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    if (!_isAllDay) {
      final time = await showWheelTimePicker(
        context,
        initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.aiNotConfiguredHint)));
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
                    width: AppSpacing.lg,
                    height: AppSpacing.lg,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.sparkles),
            tooltip: AppLocalizations.of(context)!.aiParse,
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
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Carries its own bottom gap, so it can sit here unconditionally
            // without leaving a hole when it renders nothing.
            CalendarSelector(
              selectedId: _selectedCalendarId,
              onChanged: (id) => setState(() => _selectedCalendarId = id),
            ),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: l.title),
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
              textCapitalization: TextCapitalization.sentences,
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
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            RemindersDraftSection(
              draftReminders: _draftReminders,
              defaultTriggerTime: _startDt,
              onChanged: (reminders) => setState(() => _draftReminders = reminders),
            ),
          ],
        ),
      ),
    );
  }
}
