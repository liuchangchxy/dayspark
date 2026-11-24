import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// The full-page host of Capture.
///
/// Same fields, same defaults, same writers as the floating capture panel; the
/// only difference is that a deep link (widget, command palette, search) lands
/// on a page instead of floating over another surface. It deliberately carries
/// no tags, subtasks or attachments — those belong to the detail editor and can
/// be added after the item exists.
class NewItemPage extends ConsumerStatefulWidget {
  const NewItemPage({
    super.key,
    this.isEvent = false,
    this.initialSummary,
    this.initialDue,
    this.initialStart,
    this.initialEnd,
    this.initialAllDay = false,
  });

  final bool isEvent;
  final String? initialSummary;
  final DateTime? initialDue;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final bool initialAllDay;

  @override
  ConsumerState<NewItemPage> createState() => _NewItemPageState();
}

class _NewItemPageState extends ConsumerState<NewItemPage> {
  late final TextEditingController _title;
  late bool _event;
  late DateTime? _due;
  late DateTime? _start;
  late DateTime? _end;
  late bool _allDay;
  Duration? _reminder;
  int? _calendarId;
  int _priority = 5;
  String? _location;
  String? _rrule;
  bool _saving = false;
  bool _writeFailed = false;
  bool _titleError = false;
  bool _discardOpen = false;
  bool _reminderTouched = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialSummary ?? '');
    _event = widget.isEvent;
    _due = widget.initialDue;
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _allDay = widget.initialAllDay;
    // The design gives an event a 15-minute reminder by default and a todo
    // none; the split is a default, not a rule, so picking one wins.
    _reminder = _event ? const Duration(minutes: 15) : null;
    _title.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    if (_titleError && _title.text.trim().isNotEmpty && mounted) {
      setState(() => _titleError = false);
    }
  }

  bool get _hasDraft =>
      _title.text.trim().isNotEmpty ||
      _due != null ||
      _start != null ||
      _calendarId != null ||
      (_reminderTouched && _reminder != null) ||
      _priority != 5 ||
      (_location?.trim().isNotEmpty ?? false) ||
      _rrule != null;

  String _md(DateTime d) =>
      DateFormat.MMMd(Localizations.localeOf(context).toString()).format(d);

  String _hm(DateTime d) => DateFormat.Hm().format(d);

  String _range(DateTime start, DateTime end) =>
      '${_md(start)} ${_hm(start)}–${_hm(end)}';

  String _reminderLabel(AppLocalizations l) {
    final offset = _reminder;
    if (offset == null) return l.remindNone;
    if (offset == Duration.zero) return l.remindOnTime;
    if (offset.inDays >= 1) return l.remindDaysBefore(offset.inDays);
    if (offset.inHours >= 1) return l.remindHoursBefore(offset.inHours);
    return l.remindMinutesBefore(offset.inMinutes);
  }

  Future<void> _confirmDiscard() async {
    if (_discardOpen) return;
    final l = AppLocalizations.of(context)!;
    final draftTitle = _title.text.trim();
    setState(() => _discardOpen = true);
    final leave = await confirmCaptureDiscard(
      context,
      title: l.captureDiscardTitle,
      body: draftTitle.isEmpty
          ? l.captureDiscardLineTitle
          : '${l.captureDiscardSub(draftTitle)}\n${l.captureDiscardLineSub}',
      keepLabel: l.keepEditing,
      discardLabel: l.captureActionDiscard,
    );
    if (!mounted) return;
    setState(() => _discardOpen = false);
    if (leave) {
      _title.clear();
      if (mounted) context.pop();
    }
  }

  Future<void> _pickDue() async {
    final l = AppLocalizations.of(context)!;
    final picked = await pickDeadline(
      context,
      initial: _due ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _due = picked);
    if (!mounted) return;
    final withTime = await showDsSheet<bool>(
      context: context,
      title: l.deadline,
      body: Column(
        children: [
          DsSettingRow(
            label: l.dateOnly,
            onTap: () => Navigator.of(context).pop(false),
          ),
          DsSettingRow(
            label: l.addTime,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (withTime != true || !mounted) return;
    final timed = await pickDeadline(
      context,
      initial: DateTime(picked.year, picked.month, picked.day, 18),
      withTime: true,
    );
    if (timed != null && mounted) setState(() => _due = timed);
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final defaultStart = _start ?? DateTime(now.year, now.month, now.day, 9);
    final defaultEnd = _end ?? defaultStart.add(const Duration(hours: 1));
    if (!mounted) return;
    final picked = await SpecPlanPickerDialog.show(
      context,
      title: _title.text.trim(),
      initialStart: defaultStart,
      initialEnd: defaultEnd,
      isEditing: _start != null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked.$1;
      _end = picked.$2;
      _allDay = false;
    });
  }

  Future<void> _pickReminder() async {
    final l = AppLocalizations.of(context)!;
    final options = <(Duration?, String)>[
      (null, l.remindNone),
      (Duration.zero, l.remindOnTime),
      (const Duration(minutes: 5), l.remindMinutesBefore(5)),
      (const Duration(minutes: 15), l.remindMinutesBefore(15)),
      (const Duration(minutes: 30), l.remindMinutesBefore(30)),
      (const Duration(hours: 1), l.remindHoursBefore(1)),
      (const Duration(days: 1), l.remindDaysBefore(1)),
    ];
    final picked = await showDsSheet<_ReminderChoice>(
      context: context,
      title: l.reminder,
      body: Column(
        children: [
          for (final option in options)
            DsSettingRow(
              label: option.$2,
              selected: _reminder == option.$1,
              trailing: _reminder == option.$1
                  ? Icon(
                      CupertinoIcons.checkmark,
                      size: 17,
                      color: context.ds.primary,
                    )
                  : null,
              onTap: () => Navigator.of(
                context,
              ).pop<_ReminderChoice>(_ReminderChoice(option.$1)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _reminderTouched = true;
    if (picked.offset == null) {
      setState(() => _reminder = null);
      return;
    }
    if (_anchor == null) {
      showSpecToast(context, l.reminderNeedsAnchor);
      return;
    }
    setState(() => _reminder = picked.offset);
  }

  DateTime? get _anchor => _event ? _start : (_start ?? _due);

  Future<void> _pickCalendar() async {
    final picked = await pickCalendar(context, ref, selectedId: _calendarId);
    if (picked != null && mounted) setState(() => _calendarId = picked);
  }

  Future<void> _pickPriority() async {
    final l = AppLocalizations.of(context)!;
    final picked = await showDsSheet<int>(
      context: context,
      title: l.priority,
      body: Column(
        children: [
          for (final entry in [
            (0, l.priorityNone),
            (9, l.priorityLow),
            (5, l.priorityMedium),
            (1, l.priorityHigh),
          ])
            DsSettingRow(
              label: entry.$2,
              selected: _priority == entry.$1,
              onTap: () => Navigator.of(context).pop(entry.$1),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _priority = picked);
  }

  Future<void> _pickLocation() async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _location ?? '');
    final value = await showDsSheet<String>(
      context: context,
      title: l.location,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: l.locationHint),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text(l.save),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      setState(() => _location = value.trim().isEmpty ? null : value.trim());
    }
  }

  Future<void> _pickRepeat() async {
    final l = AppLocalizations.of(context)!;
    final options = <(String?, String)>[
      (null, l.repeatNever),
      ('FREQ=DAILY', l.repeatDaily),
      ('FREQ=WEEKLY', l.repeatWeekly),
      ('FREQ=MONTHLY', l.repeatMonthly),
      ('FREQ=YEARLY', l.repeatYearly),
    ];
    final picked = await showDsSheet<_RepeatChoice>(
      context: context,
      title: l.recurrenceRule,
      body: Column(
        children: [
          for (final option in options)
            DsSettingRow(
              label: option.$2,
              selected: _rrule == option.$1,
              onTap: () => Navigator.of(
                context,
              ).pop<_RepeatChoice>(_RepeatChoice(option.$1)),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _rrule = picked.rule);
  }

  String _repeatLabel(AppLocalizations l) => switch (_rrule) {
    'FREQ=DAILY' => l.repeatDaily,
    'FREQ=WEEKLY' => l.repeatWeekly,
    'FREQ=MONTHLY' => l.repeatMonthly,
    'FREQ=YEARLY' => l.repeatYearly,
    _ => l.repeatNever,
  };

  Future<void> _save() async {
    if (_saving) return;
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    if (_event && (_start == null || _end == null)) {
      showSpecToast(context, l.plannedExecution);
      return;
    }
    setState(() {
      _saving = true;
      _writeFailed = false;
    });
    final calendars = await ref.read(calendarsProvider.future);
    if (calendars.isEmpty) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSpecToast(context, l.noCalendar);
      return;
    }
    final calendarId =
        _calendarId ??
        resolveNewEntryCalendarId(
          calendars: calendars,
          preferredId: ref.read(defaultCalendarIdProvider),
        ) ??
        calendars.first.id;
    final offset = _reminder;
    try {
      await RecordScope.run(ref.read(databaseProvider), (tx) async {
        if (_event) {
          final start = _allDay
              ? DateTime(_start!.year, _start!.month, _start!.day)
              : _start!;
          final end = _allDay
              ? DateTime(_start!.year, _start!.month, _start!.day)
                    .add(const Duration(days: 1))
              : _end!;
          final eventId = await ref.read(createEventProvider)(
            calendarId: calendarId,
            summary: title,
            startDt: start,
            endDt: end,
            isAllDay: _allDay,
            location: _location,
            rrule: _rrule,
          );
          if (offset != null) {
            await ref.read(createReminderProvider)(
              parentType: 'event',
              parentId: eventId,
              triggerTime: start.subtract(offset),
            );
          }
          return;
        }
        final todoId = await ref.read(createTodoProvider)(
          calendarId: calendarId,
          summary: title,
          priority: _priority,
          status: 'NEEDS-ACTION',
          dueDate: _due,
        );
        if (_start != null && _end != null) {
          await ref.read(createTaskAllocationProvider)(
            todoId: todoId,
            startAt: _start!,
            endAt: _end!,
          );
        }
        if (offset != null) {
          final anchor = _start ?? _due;
          if (anchor != null) {
            await ref.read(createReminderProvider)(
              parentType: 'todo',
              parentId: todoId,
              triggerTime: anchor.subtract(offset),
            );
          }
        }
      });
      if (!mounted) return;
      showSpecToast(context, _event ? l.eventCreated : l.todoCreated);
      // A deep link can land here with nothing underneath; going home beats
      // trapping the user on the page that just saved.
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/');
      }
    } catch (error) {
      debugPrint('new item: save failed: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _writeFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final defaultCalId = calendars.isEmpty
        ? null
        : resolveNewEntryCalendarId(
            calendars: calendars,
            preferredId: ref.watch(defaultCalendarIdProvider),
          );
    Calendar? calendar;
    for (final item in calendars) {
      if (item.id == (_calendarId ?? defaultCalId)) calendar = item;
    }
    final calendarName = calendar?.name ?? '';

    final primary = _PrimaryToolButton(
      key: const ValueKey('new-item-primary'),
      label: _writeFailed
          ? l.retrySave
          : (_event ? l.createEventAction : l.createTodoAction),
      busy: _saving,
      onPressed: _save,
    );

    return PopScope(
      canPop: !_hasDraft,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: WorkspacePage(
        title: _event ? l.newEvent : l.newTodoPageTitle,
        subtitle: l.newItemPageSub,
        actions: [
          if (desktop)
            _ToolButton(
              label: l.cancel,
              onPressed: () => _hasDraft ? _confirmDiscard() : context.pop(),
            ),
          primary,
        ],
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            desktop ? 28 : 16,
            16,
            desktop ? 28 : 16,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_writeFailed) ...[
                    _Alert(
                      text: '${l.saveFailedNotWritten} '
                          '${l.newItemSaveFailedNote}',
                      danger: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _TypeRow(
                    event: _event,
                    note: _event ? l.typeNoteEvent : l.typeNoteTodo,
                    onSelect: (value) => setState(() {
                      _event = value;
                      if (!value) _rrule = null;
                      if (!_reminderTouched) {
                        _reminder = value
                            ? const Duration(minutes: 15)
                            : null;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.07,
                      fontWeight: FontWeight.w600,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _TitleField(
                    key: const ValueKey('new-item-title'),
                    controller: _title,
                    autofocus: true,
                    invalid: _titleError,
                    hint: _event ? l.newEventPlaceholder : l.newTodoPlaceholder,
                  ),
                  if (_titleError) ...[
                    const SizedBox(height: 4),
                    Text(
                      l.titleRequired,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: SpecTokens.red,
                        height: 1.45,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  _Facts(
                    items: _event
                        ? [
                            _Fact(
                              color: _parseColor(calendar?.color),
                              text: calendarName,
                            ),
                            _Fact(
                              text: _allDay
                                  ? '${l.allDay} · ${_md(_start ?? DateTime.now())}'
                                  : _start != null && _end != null
                                  ? _range(_start!, _end!)
                                  : l.notScheduled,
                              icon: CupertinoIcons.clock,
                            ),
                            _Fact(text: _reminderLabel(l), icon: CupertinoIcons.bell),
                          ]
                        : [
                            _Fact(
                              text: _start != null
                                  ? _md(_start!)
                                  : l.noDate,
                              icon: CupertinoIcons.clock,
                              muted: _start == null,
                            ),
                            _Fact(
                              color: _parseColor(calendar?.color),
                              text: calendarName,
                            ),
                            _Fact(
                              text: _due == null
                                  ? l.noDeadline
                                  : '${_md(_due!)}${_due!.hour == 0 && _due!.minute == 0 ? '' : ' ${_hm(_due!)}'}',
                              icon: CupertinoIcons.flag,
                              muted: _due == null,
                            ),
                          ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: SpecTokens.hair)),
                    ),
                    child: Column(
                      children: _event
                          ? [
                              _FieldRow(
                                label: l.captureFieldEventTime,
                                value: _start != null && _end != null
                                    ? _range(_start!, _end!)
                                    : l.notScheduled,
                                onTap: _pickSlot,
                              ),
                              _FieldRow(
                                label: l.allDay,
                                value: _allDay ? l.captureFieldYes : l.captureFieldNo,
                                onTap: () => setState(() => _allDay = !_allDay),
                              ),
                              _FieldRow(
                                label: l.captureFieldCalendar,
                                value: calendarName,
                                onTap: _pickCalendar,
                              ),
                              _FieldRow(
                                label: l.location,
                                value: _location ?? l.notFilled,
                                onTap: _pickLocation,
                              ),
                              _FieldRow(
                                label: l.newItemRepeatLabel,
                                value: _repeatLabel(l),
                                onTap: _pickRepeat,
                              ),
                              _FieldRow(
                                label: l.reminder,
                                value: _reminderLabel(l),
                                onTap: _pickReminder,
                              ),
                            ]
                          : [
                              _FieldRow(
                                label: l.deadline,
                                value: _due == null
                                    ? l.noDeadline
                                    : '${_md(_due!)} ${_hm(_due!)}',
                                onTap: _pickDue,
                              ),
                              _FieldRow(
                                label: l.plannedExecution,
                                value: _start != null && _end != null
                                    ? _range(_start!, _end!)
                                    : l.notScheduled,
                                onTap: _pickSlot,
                              ),
                              _FieldRow(
                                label: l.reminder,
                                value: _reminderLabel(l),
                                onTap: _pickReminder,
                              ),
                              _FieldRow(
                                label: l.captureFieldCalendar,
                                value: calendarName,
                                onTap: _pickCalendar,
                              ),
                              _FieldRow(
                                label: l.priority,
                                value: switch (_priority) {
                                  1 => l.priorityHigh,
                                  5 => l.priorityMedium,
                                  9 => l.priorityLow,
                                  _ => l.priorityNone,
                                },
                                onTap: _pickPriority,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _event ? l.newEventFootnote : l.newTodoFootnote,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: SpecTokens.faint,
                      height: 1.6,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(cleaned.length <= 6 ? 0xFF000000 | value : value);
}

class _ReminderChoice {
  const _ReminderChoice(this.offset);
  final Duration? offset;
}

class _RepeatChoice {
  const _RepeatChoice(this.rule);
  final String? rule;
}

class _TitleField extends StatelessWidget {
  const _TitleField({
    super.key,
    required this.controller,
    required this.hint,
    required this.invalid,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool invalid;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: SpecTokens.ink,
        fontFamilyFallback: AppTypography.fallback,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E84),
          fontFamilyFallback: AppTypography.fallback,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        constraints: const BoxConstraints(minHeight: 34),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: invalid ? SpecTokens.red : SpecTokens.hair2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: invalid ? SpecTokens.red : const Color(0xFFA9A9A0),
          ),
        ),
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.event,
    required this.note,
    required this.onSelect,
  });

  final bool event;
  final String note;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Row(
      children: [
        _TypeButton(
          label: l.itemTypeTodo,
          icon: CupertinoIcons.checkmark_alt,
          on: !event,
          onTap: () => onSelect(false),
        ),
        const SizedBox(width: 6),
        _TypeButton(
          key: const ValueKey('new-item-type-event'),
          label: l.itemTypeEvent,
          icon: CupertinoIcons.calendar,
          on: event,
          onTap: () => onSelect(true),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: on ? SpecTokens.ink : SpecTokens.paper,
            border: Border.all(
              color: on ? SpecTokens.ink : SpecTokens.hair2,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 10,
                color: on ? Colors.white : SpecTokens.ink2,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? Colors.white : SpecTokens.ink2,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact {
  const _Fact({
    required this.text,
    this.icon,
    this.color,
    this.muted = false,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final bool muted;
}

class _Facts extends StatelessWidget {
  const _Facts({required this.items});

  final List<_Fact> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final item in items)
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFBFBF8),
              border: Border.all(color: SpecTokens.hair),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.color != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ] else if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 10,
                    color: item.muted ? SpecTokens.faint : SpecTokens.muted,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  item.text,
                  style: TextStyle(
                    fontSize: 10,
                    color: item.muted ? SpecTokens.faint : SpecTokens.ink2,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 37),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F3EE))),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: SpecTokens.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFDF0ED) : SpecTokens.amberSoft,
        border: Border(
          left: BorderSide(
            color: danger ? SpecTokens.red : SpecTokens.amber,
            width: danger ? 3 : 2,
          ),
        ),
        borderRadius: danger ? BorderRadius.circular(4) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: danger ? const Color(0xFF7C231B) : const Color(0xFF6B4B12),
          height: 1.55,
          fontWeight: danger ? FontWeight.w500 : FontWeight.w400,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 29),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          foregroundColor: SpecTokens.ink2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: SpecTokens.hair2),
          ),
          backgroundColor: SpecTokens.paper,
          textStyle: const TextStyle(
            fontSize: 11,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _PrimaryToolButton extends StatelessWidget {
  const _PrimaryToolButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 29),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        foregroundColor: Colors.white,
        backgroundColor: SpecTokens.ink,
        disabledBackgroundColor: SpecTokens.ink.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
