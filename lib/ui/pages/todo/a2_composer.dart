import 'package:drift/drift.dart' show Value;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/utils/capture_parser.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// The A″ composer: one sheet that writes exactly what the user expressed.
///
/// `dueDate` is only written from the 截止 row, a [TaskAllocation] only from a
/// chosen slot, and opening the sheet for a browsed day pre-fills neither — the
/// primary button says what will happen before the user taps it.
Future<bool> showA2Composer(
  BuildContext context, {
  required DateTime contextDate,
  Todo? todo,
  DateTime? initialStart,
  DateTime? initialEnd,
  String? initialTitle,
  bool startAsEvent = false,
}) async {
  final composer = A2ComposerSheet(
    contextDate: contextDate,
    todo: todo,
    initialStart: initialStart,
    initialEnd: initialEnd,
    initialTitle: initialTitle,
    startAsEvent: startAsEvent,
  );
  // Desktop keeps its own overlay language: a centred dialog, not a phone
  // sheet stretched across the window. The composer chooses its chrome from
  // the same breakpoint, so the two calls cannot disagree.
  if (isWorkspaceLayout(context)) {
    final saved = await showDialog<bool>(
      context: context,
      barrierColor: const Color.fromRGBO(25, 25, 24, 0.26),
      builder: (_) => composer,
    );
    return saved ?? false;
  }
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color.fromRGBO(25, 25, 24, 0.26),
    builder: (_) => composer,
  );
  return saved ?? false;
}

/// Everything the quick sheet has already taken from the user travels with it
/// into the full form. The route is the only channel between the two, so it
/// carries all of it.
String composerCreateRoute({
  DateTime? due,
  DateTime? start,
  DateTime? end,
  String? summary,
}) {
  final text = summary?.trim() ?? '';
  final query = <String, String>{
    if (due != null) 'due': '${due.millisecondsSinceEpoch}',
    if (start != null) 'start': '${start.millisecondsSinceEpoch}',
    if (end != null) 'end': '${end.millisecondsSinceEpoch}',
    if (text.isNotEmpty) 'summary': text,
  };
  if (query.isEmpty) return '/todo/new';
  return '/todo/new?${Uri(queryParameters: query).query}';
}

typedef _ReminderSelection = ({Duration? offset});

class A2ComposerSheet extends ConsumerStatefulWidget {
  const A2ComposerSheet({
    super.key,
    required this.contextDate,
    this.todo,
    this.initialStart,
    this.initialEnd,
    this.initialTitle,
    this.startAsEvent = false,
  });

  final DateTime contextDate;
  final Todo? todo;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String? initialTitle;
  final bool startAsEvent;

  @override
  ConsumerState<A2ComposerSheet> createState() => _A2ComposerSheetState();
}

class _A2ComposerSheetState extends ConsumerState<A2ComposerSheet> {
  late final TextEditingController _title;
  DateTime? _due;
  DateTime? _start;
  DateTime? _end;
  int? _calendarId;
  int _priority = 5;
  Duration? _reminderOffset;
  bool _planOpen = false;
  bool _saving = false;
  bool _writeFailed = false;
  bool _titleValidationError = false;
  bool _event = false;
  bool _parsedHasSuggestion = false;
  bool _suggestionApplied = false;
  bool _suggestionRemoved = false;
  bool _discardOpen = false;
  bool _reminderTouched = false;
  String? _occurrenceId;
  Todo? _boundTodo;

  // The mode is the binding, not a separate flag: switching to "create" drops
  // the todo so nothing can be written against it by accident.
  bool get _scheduling => _boundTodo != null;

  bool get _dueChanged => _due != _boundTodo?.dueDate;

  static bool _isRecurring(Todo? todo) =>
      todo != null && todo.rrule != null && todo.rrule!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.initialTitle ?? widget.todo?.summary ?? '',
    );
    _boundTodo = widget.todo;
    _due = widget.todo?.dueDate;
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _priority = widget.todo?.priority ?? 5;
    _calendarId = widget.todo?.calendarId;
    _planOpen = false;
    _event = widget.startAsEvent && widget.todo == null;
    if (_event) _reminderOffset = const Duration(minutes: 15);
    final parsed = parseCapture(_title.text, DateTime.now());
    _parsedHasSuggestion = widget.todo == null && parsed.start != null;
    if (!_scheduling && parsed.start != null) {
      if (_start == null) {
        _start = parsed.start;
        _end = parsed.end;
      }
      _suggestionApplied = _start == parsed.start;
    }
  }

  CaptureDraft get _parsed => parseCapture(_title.text, DateTime.now());

  bool get _showSuggestionPanel =>
      !_scheduling &&
      !_event &&
      _parsedHasSuggestion &&
      (_suggestionRemoved || _suggestionApplied || _start == null);

  void _onTitleChanged(String value) {
    final parsed = parseCapture(value, DateTime.now());
    setState(() {
      if (_titleValidationError && value.trim().isNotEmpty) {
        _titleValidationError = false;
      }
      _parsedHasSuggestion = parsed.start != null;
      _suggestionRemoved = false;
      if (parsed.start != null && (_start == null || _suggestionApplied)) {
        _start = parsed.start;
        _end = parsed.end;
        _suggestionApplied = true;
      } else if (parsed.start == null && _suggestionApplied) {
        _start = null;
        _end = null;
        _suggestionApplied = false;
      }
    });
  }

  void _setEvent(bool event) {
    final parsed = _parsed;
    setState(() {
      _event = event;
      if (event && _start == null && parsed.start != null) {
        _start = parsed.start;
        _end = parsed.end;
        _suggestionApplied = true;
        _suggestionRemoved = false;
      }
      if (!event) _suggestionRemoved = false;
      if (event && !_reminderTouched && _reminderOffset == null) {
        _reminderOffset = const Duration(minutes: 15);
      }
    });
  }

  void _removeSuggestion() {
    setState(() {
      _suggestionRemoved = true;
      if (_suggestionApplied) {
        _start = null;
        _end = null;
        _suggestionApplied = false;
      }
    });
  }

  void _restoreSuggestion() {
    final parsed = _parsed;
    setState(() {
      _suggestionRemoved = false;
      if (parsed.start != null) {
        _start = parsed.start;
        _end = parsed.end;
        _suggestionApplied = true;
      }
    });
  }

  bool get _hasDraft {
    if (_scheduling) {
      return _start != widget.initialStart ||
          _end != widget.initialEnd ||
          _dueChanged ||
          _reminderOffset != null ||
          _priority != (widget.todo?.priority ?? 5);
    }
    return _title.text.trim().isNotEmpty ||
        _due != null ||
        _start != null ||
        _end != null ||
        (_reminderTouched && _reminderOffset != null) ||
        _priority != 5 ||
        _calendarId != null;
  }

  Future<void> _confirmDiscard() async {
    if (_discardOpen) return;
    _discardOpen = true;
    final l = AppLocalizations.of(context)!;
    final draftTitle = _scheduling
        ? (_boundTodo?.summary ?? '')
        : _title.text.trim();
    final discard = await confirmCaptureDiscard(
      context,
      title: l.captureDiscardTitle,
      body: _scheduling
          ? l.captureDiscardLineTitle
          : draftTitle.isEmpty
          ? l.captureDiscardLineTitle
          : '${l.captureDiscardSub(draftTitle)}\n${l.captureDiscardLineSub}',
      keepLabel: l.keepEditing,
      discardLabel: l.discard,
    );
    _discardOpen = false;
    if (discard && mounted) Navigator.of(context).pop();
  }

  void _setMode(bool scheduling) {
    if (scheduling == _scheduling) return;
    setState(() {
      _boundTodo = scheduling ? widget.todo : null;
      // A different series has a different set of occurrences.
      _occurrenceId = null;
    });
  }

  void _setSlot(DateTime? start, DateTime? end) {
    setState(() {
      _start = start;
      _end = end;
      _suggestionApplied = false;
      // The chosen occurrence belongs to the previous slot's day.
      _occurrenceId = null;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _md(DateTime d) => '${d.month}/${d.day}';

  String _mdhm(DateTime d) =>
      '${d.month}/${d.day} ${DateFormatters.formatTime(d)}';

  bool _hasClock(DateTime d) => d.hour != 0 || d.minute != 0;

  String _dueText(DateTime d) => _hasClock(d) ? _mdhm(d) : _md(d);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// A deadline on the slot's own day only needs its clock time: the date is
  /// already carried by the plan half of the label. A date-only deadline keeps
  /// its date, or "00:00" would read as a time the user never set.
  String _dueTextAgainst(DateTime due, DateTime? slotDay) =>
      _hasClock(due) && slotDay != null && _sameDay(due, slotDay)
      ? DateFormatters.formatTime(due)
      : _dueText(due);

  String _range(DateTime start, DateTime end, {bool includeDate = false}) {
    final startClock = DateFormatters.formatTime(start);
    final endClock = DateFormatters.formatTime(end);
    if (!includeDate) return '$startClock–$endClock';
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) return '${_md(start)} $startClock–$endClock';
    return '${_md(start)} $startClock–${_md(end)} $endClock';
  }

  Future<void> _pickDue() async {
    final l = AppLocalizations.of(context)!;
    final picked = await pickDeadline(
      context,
      initial: _due ?? widget.contextDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _due = picked);
    if (!mounted) return;
    final addTime = await showDsSheet<bool>(
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
    if (addTime != true || !mounted) return;
    final withTime = await pickDeadline(
      context,
      initial: DateTime(picked.year, picked.month, picked.day, 18),
      withTime: true,
    );
    if (withTime != null && mounted) setState(() => _due = withTime);
  }

  Future<void> _pickCustomSlot() async {
    final title = _title.text.trim().isNotEmpty
        ? _title.text.trim()
        : (_boundTodo?.summary ?? '');
    final defaultStart = _start ??
        DateTime(
          widget.contextDate.year,
          widget.contextDate.month,
          widget.contextDate.day,
          9,
        );
    final defaultEnd = _end ?? defaultStart.add(const Duration(hours: 1));
    if (!mounted) return;
    final picked = await SpecPlanPickerDialog.show(
      context,
      title: title,
      initialStart: defaultStart,
      initialEnd: defaultEnd,
      existingBlocks: _blocksForDay,
      isEditing: _scheduling && _start != null,
    );
    if (picked == null || !mounted) return;
    _setSlot(picked.$1, picked.$2);
    setState(() => _planOpen = true);
  }

  Future<List<SpecPlanBlock>> _blocksForDay(DateTime day) async {
    final db = ref.read(databaseProvider);
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final events = await db.eventsDao.getEventCandidates(start, end);
    final allocations = await fetchTaskAllocationsInDateRange(db, start, end);
    final blocks = calDayBlocks(
      day: start,
      events: [
        for (final event in events) CalendaEventAdapter.fromDrift(event),
      ],
      allocations: [
        for (final item in allocations)
          if (item.todo.id != _boundTodo?.id)
            TaskAllocationCalendarAdapter.fromItem(item),
      ],
    );
    return [
      for (final block in blocks)
        SpecPlanBlock(start: block.start, end: block.end, title: block.title),
    ];
  }

  Future<void> _pickReminder() async {
    final l = AppLocalizations.of(context)!;
    final options = <(Duration?, String)>[
      (null, l.remindNone),
      (Duration.zero, l.remindOnTime),
      (const Duration(minutes: 5), l.remindMinutesBefore(5)),
      (const Duration(minutes: 10), l.remindMinutesBefore(10)),
      (const Duration(minutes: 30), l.remindMinutesBefore(30)),
      (const Duration(hours: 1), l.remindHoursBefore(1)),
      (const Duration(days: 1), l.remindDaysBefore(1)),
    ];
    // `null` is the sheet being dismissed; choosing "No reminder" has to be a
    // value that survives the trip back, or the two are indistinguishable.
    final picked = await showDsSheet<_ReminderSelection>(
      context: context,
      title: l.reminder,
      body: Column(
        children: [
          for (final option in options)
            DsSettingRow(
              label: option.$2,
              selected: _reminderOffset == option.$1,
              trailing: _reminderOffset == option.$1
                  ? Icon(
                      CupertinoIcons.checkmark,
                      size: 17,
                      color: context.ds.primary,
                    )
                  : null,
              onTap: () => Navigator.of(
                context,
              ).pop<_ReminderSelection>((offset: option.$1)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _reminderTouched = true;
    if (picked.offset == null) {
      setState(() => _reminderOffset = null);
      return;
    }
    final anchor = _start ?? _due;
    if (anchor == null) {
      _toast(l.reminderNeedsAnchor);
      return;
    }
    setState(() => _reminderOffset = picked.offset);
  }

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

  Future<void> _openFullForm() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.maybeOf(context);
    final title = _title.text.trim();
    navigator.pop();
    if (router == null) return;
    // Everything the sheet has already taken from the user travels with it:
    // dropping the picked block here made the full form silently forget a
    // slot the user had expressed. Scheduling mode never reaches this: its "…"
    // is disabled because that form cannot carry the slot for an existing todo.
    router.push(
      composerCreateRoute(due: _due, start: _start, end: _end, summary: title),
    );
  }

  void _toast(String message) {
    showSpecToast(context, message);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim();
    final parsed = _parsed;
    final summary = parsed.start != null ? parsed.title : title;
    if (_saving) return;
    if (!_scheduling && title.isEmpty) {
      setState(() => _titleValidationError = true);
      return;
    }
    if (_event && (_start == null || _end == null)) return;
    if (_scheduling && (_start == null || _end == null)) return;
    setState(() {
      _saving = true;
      _writeFailed = false;
    });
    try {
      if (_scheduling) {
        final todo = _boundTodo!;
        final recurring = _isRecurring(todo);
        // A recurring series has no single occurrence to plan: the writer
        // refuses an allocation without one, so ask which instance this slot
        // belongs to (the picker opens on the planned day). Asking again after
        // a failed write would let a retry land on a different occurrence.
        if (recurring && _occurrenceId == null) {
          final picked = await TodoOccurrencePickerSheet.show(
            context,
            ref: ref,
            todo: todo,
            anchorDate: _start,
          );
          if (picked == null) {
            if (mounted) setState(() => _saving = false);
            return;
          }
          _occurrenceId = picked.occurrenceId;
        }
        if (!mounted) return;
        final start = _start!;
        final end = _end!;
        final due = _due;
        final writeDue = _dueChanged;
        await RecordScope.run(ref.read(databaseProvider), (tx) async {
          await ref.read(createTaskAllocationProvider)(
            todoId: todo.id,
            startAt: start,
            endAt: end,
            occurrenceId: recurring ? _occurrenceId : null,
          );
          // A recurring series carries its due date as part of the series
          // spec; writing the column alone is refused, so the row stays
          // read-only for those and only the block moves.
          if (writeDue && !recurring) {
            await ref.read(updateTodoProvider)(
              todo.id,
              TodosCompanion(dueDate: Value(due)),
            );
          }
        });
        if (!mounted) return;
        _landOn(start);
        Navigator.of(context).pop(true);
        _toast(l.planToDate(_md(start)));
        return;
      }
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        _toast(l.noCalendar);
        setState(() => _saving = false);
        return;
      }
      final calendarId =
          _calendarId ??
          resolveNewEntryCalendarId(
            calendars: calendars,
            preferredId: ref.read(defaultCalendarIdProvider),
          ) ??
          calendars.first.id;
      final start = _start;
      final end = _end;
      final reminderOffset = _reminderOffset;
      if (_event) {
        if (start == null || end == null) {
          setState(() => _saving = false);
          return;
        }
        await RecordScope.run(ref.read(databaseProvider), (tx) async {
          final eventId = await ref.read(createEventProvider)(
            calendarId: calendarId,
            summary: summary,
            startDt: start,
            endDt: end,
            isAllDay: false,
          );
          if (reminderOffset != null) {
            await ref.read(createReminderProvider)(
              parentType: 'event',
              parentId: eventId,
              triggerTime: start.subtract(reminderOffset),
            );
          }
        });
        if (!mounted) return;
        _landOn(start);
        Navigator.of(context).pop(true);
        _toast(l.eventCreated);
        return;
      }
      final due = _due;
      final priority = _priority;
      await RecordScope.run(ref.read(databaseProvider), (tx) async {
        final todoId = await ref.read(createTodoProvider)(
          calendarId: calendarId,
          summary: summary,
          priority: priority,
          status: 'NEEDS-ACTION',
          dueDate: due,
        );
        if (start != null && end != null) {
          await ref.read(createTaskAllocationProvider)(
            todoId: todoId,
            startAt: start,
            endAt: end,
          );
        }
        final anchor = start ?? due;
        if (reminderOffset != null && anchor != null) {
          await ref.read(createReminderProvider)(
            parentType: 'todo',
            parentId: todoId,
            triggerTime: anchor.subtract(reminderOffset),
          );
        }
      });
      if (!mounted) return;
      if (start != null) {
        _landOn(start);
        Navigator.of(context).pop(true);
        _toast(l.planToDate(_md(start)));
        return;
      }
      Navigator.of(context).pop(true);
      _toast(l.todoCreated);
    } catch (error) {
      debugPrint('composer: save failed: $error');
      if (!mounted) return;
      // The draft is the user's work: keep the sheet, every field and the
      // chosen occurrence, and mark the write as not done so a retry is
      // obviously a retry.
      setState(() {
        _saving = false;
        _writeFailed = true;
      });
    }
  }


  /// A write the user asked for happened on [day]; leaving the calendar on the
  /// day they were looking at made them hunt for the block they just made.
  void _landOn(DateTime day) {
    ref.read(viewedDateProvider.notifier).state = DateTime(
      day.year,
      day.month,
      day.day,
    );
  }

  List<(DateTime, DateTime)> _recommendedSlots() {
    final day = widget.contextDate;
    DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour);
    return [
      (at(9), at(10)),
      (at(12), at(13)),
      (at(14), at(15)),
      (at(16), at(17)),
      (at(19), at(20)),
    ];
  }

  /// The button is the promise: verb from the mode, then every field this
  /// save will actually write, values inline. Fields nobody touched are not
  /// named, and the order is fixed — plan before deadline.
  String _primaryLabel(AppLocalizations l) {
    final hasSlot = _start != null && _end != null;
    if (_event) {
      if (!hasSlot) return l.composerNoSlot;
      return '${l.newEvent} (${_range(_start!, _end!, includeDate: true)})';
    }
    final ready = _scheduling ? hasSlot : _title.text.trim().isNotEmpty;
    // A disabled button must not promise a result it cannot produce: it asks
    // for the missing input instead. Reuses the field's own prompt.
    if (!ready) return _scheduling ? l.composerNoSlot : l.composerPlaceholder;
    final due = _due;
    // An existing task's deadline is only part of the promise when it moved;
    // a series carries its deadline in the recurrence spec, so it stays put.
    final writesDue = _scheduling
        ? due != null && _dueChanged && !_isRecurring(_boundTodo)
        : due != null;
    final plan = hasSlot ? _range(_start!, _end!, includeDate: true) : null;
    if (plan != null && writesDue) {
      // When the deadline lands on the slot's own day, the plan half can drop
      // its date and the deadline keeps only its clock: one day, said once.
      // On different days both halves keep their date.
      final sameDay = _sameDay(due, _start!);
      final planText = sameDay
          ? l.plannedShortRangeLabel(_range(_start!, _end!))
          : l.plannedShortRangeLabel(plan);
      final dueText = _dueTextAgainst(due, sameDay ? _start : null);
      final fields = '$planText · ${l.dueValueLabel(dueText)}';
      return '${_scheduling ? l.schedule : l.save} ($fields)';
    }
    if (plan != null) {
      // Scheduling says where the existing task goes ("安排到 …"), creating
      // says what a new one becomes ("计划执行到 …"). Both are existing keys;
      // they differ only in the verb, which is the whole point.
      return _scheduling ? l.planToDate(plan) : l.savePlannedTo(plan);
    }
    if (writesDue) return l.saveWithDueDate(_dueText(due));
    return l.saveToUnplanned;
  }

  bool get _canSave =>
      !_saving &&
      (_scheduling || _event
          ? _start != null && _end != null
          : _title.text.trim().isNotEmpty) &&
      (_scheduling
          ? true
          : _event
          ? _title.text.trim().isNotEmpty
          : true);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final desktop = isWorkspaceLayout(context);
    final dateText = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).format(widget.contextDate);
    final weekday = DateFormat.E(
      Localizations.localeOf(context).toString(),
    ).format(widget.contextDate);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final defaultCalId = calendars.isEmpty
        ? null
        : resolveNewEntryCalendarId(
            calendars: calendars,
            preferredId: ref.watch(defaultCalendarIdProvider),
          );
    String? calendarName;
    for (final calendar in calendars) {
      if (calendar.id == (_calendarId ?? defaultCalId)) {
        calendarName = calendar.name;
      }
    }
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The mode only exists where both readings are possible: a sheet that
        // already carries a task can schedule it or branch into a new one.
        if (widget.todo != null) ...[
          _modeSwitcher(l),
          const SizedBox(height: 10),
        ],
        _titleField(ds, l),
        if (_scheduling) ...[const SizedBox(height: 6), _boundNote(ds, l)],
        if (_showSuggestionPanel) ...[
          const SizedBox(height: 8),
          _suggestionPanel(ds, l),
        ],
        const SizedBox(height: 10),
        if (_event) _eventWhenRow(ds, l) else _fieldPair(ds, l),
        if (_planOpen) ...[const SizedBox(height: 8), _slotChips(ds, l)],
        const SizedBox(height: 6),
        _hintLine(ds, l),
        const SizedBox(height: 8),
        if (!_scheduling) ...[
          _subRow(
            ds,
            l.reminder,
            _reminderOffset == null
                ? l.remindNone
                : _reminderOffset == Duration.zero
                ? l.remindOnTime
                : l.remindMinutesBefore(_reminderOffset!.inMinutes),
            key: const ValueKey('a2-composer-reminder'),
            onTap: _pickReminder,
          ),
          _subRow(
            ds,
            l.captureFieldCalendar,
            calendarName ?? (calendars.isEmpty ? '' : calendars.first.name),
            key: const ValueKey('a2-composer-calendar'),
            strong: calendarName != null,
            onTap: _pickCalendar,
          ),
          if (_event)
            _subRow(
              ds,
              l.recurrenceRule,
              l.repeatNever,
              key: const ValueKey('a2-composer-repeat'),
              last: true,
            )
          else ...[
            _subRow(
              ds,
              l.priority,
              switch (_priority) {
                1 => l.priorityHigh,
                5 => l.priorityMedium,
                9 => l.priorityLow,
                _ => l.priorityNone,
              },
              key: const ValueKey('a2-composer-priority'),
              last: true,
              onTap: _pickPriority,
            ),
          ],
        ],
        const SizedBox(height: 12),
      ],
    );
    final shortcuts = <ShortcutActivator, VoidCallback>{
      // Escape is the desktop way out of a sheet. The create field already
      // owns focus; scheduling mode has no field, so the wrapper takes it.
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    };

    if (desktop) {
      final isShifted = ref.watch(workspaceSelectionProvider) != null &&
          isMasterDetailLayout(context);
      final panelWidth = _writeFailed ? 520.0 : 620.0;
      return PopScope(
        canPop: !_hasDraft,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: CallbackShortcuts(
          bindings: shortcuts,
          child: Focus(
            autofocus: _scheduling,
            canRequestFocus: _scheduling,
            skipTraversal: !_scheduling,
            child: Dialog(
              backgroundColor: Colors.transparent,
              alignment: Alignment.bottomCenter,
              insetPadding: const EdgeInsets.only(bottom: 82),
              child: Transform.translate(
                offset: Offset(isShifted ? -190 : 0, 0),
                child: Container(
                width: panelWidth,
                constraints: const BoxConstraints(maxHeight: 620),
                decoration: BoxDecoration(
                  color: SpecTokens.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SpecTokens.hair2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x21191918),
                      blurRadius: 55,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(context, ds, l, dateText, weekday, desktop: true),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
                        child: fields,
                      ),
                    ),
                    _footer(ds, l, desktop: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      );
    }

    return PopScope(
      canPop: !_hasDraft,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: _scheduling,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.90,
            ),
            decoration: BoxDecoration(
              color: SpecTokens.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SpecTokens.hair2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2E191918),
                  blurRadius: 60,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, ds, l, dateText, weekday, desktop: false),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
                    child: fields,
                  ),
                ),
                _footer(ds, l, desktop: false),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    DsColors ds,
    AppLocalizations l,
    String dateText,
    String weekday, {
    required bool desktop,
  }) {
    final hasSlot = _start != null && _end != null;
    final title = _writeFailed
        ? l.widgetSaveFailed
        : _event
        ? l.newEvent
        : l.planToDate('$dateText · $weekday');
    final sub = _writeFailed
        ? l.captureSaveErrorServer
        : _event
        ? (hasSlot
              ? '${l.eventLabel} · ${_range(_start!, _end!, includeDate: true)}'
              : l.captureHintEvent)
        : _showSuggestionPanel && !_suggestionRemoved
        ? l.captureHintParsed
        : l.captureHintExpanded;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: SpecTokens.hair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: desktop ? 11.5 : 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: SpecTokens.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: SpecTokens.faint,
                    height: 1.3,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.xmark, size: 12),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            splashRadius: 14,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _footer(DsColors ds, AppLocalizations l, {required bool desktop}) {
    final hint = _writeFailed
        ? l.captureHintSaveError
        : _event
        ? l.captureHintEvent
        : _showSuggestionPanel && !_suggestionRemoved
        ? l.captureHintParsed
        : l.captureHintExpanded;

    if (desktop) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: SpecTokens.wash,
          border: Border(top: BorderSide(color: SpecTokens.hair)),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(10),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: SpecTokens.faint,
                    height: 1.35,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_event) ...[
                TextButton(
                  key: const ValueKey('a2-composer-change-to-todo'),
                  onPressed: () => _setEvent(false),
                  style: TextButton.styleFrom(
                    foregroundColor: SpecTokens.ink2,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 29),
                  ),
                  child: Text(l.captureActionChangeToTodo),
                ),
                const SizedBox(width: 6),
              ],
              _ellipsisButton(ds, l, desktop: true),
              const SizedBox(width: 8),
              if (_writeFailed) ...[
                Flexible(child: _writeFailureLabel(ds, l)),
                const SizedBox(width: 8),
                if (!_scheduling && !_event) ...[
                  TextButton(
                    onPressed: _saveToUnplanned,
                    style: TextButton.styleFrom(
                      foregroundColor: SpecTokens.ink2,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 29),
                    ),
                    child: Text(l.captureActionSaveLater),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
              Flexible(child: _primaryButton(ds, l, desktop: true)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: SpecTokens.wash,
        border: Border(top: BorderSide(color: SpecTokens.hair)),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(14),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _ellipsisButton(ds, l, desktop: false),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_event) ...[
                    Flexible(
                      child: TextButton(
                        key: const ValueKey('a2-composer-change-to-todo'),
                        onPressed: () => _setEvent(false),
                        style: TextButton.styleFrom(
                          foregroundColor: SpecTokens.ink2,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 44),
                        ),
                        child: Text(
                          l.captureActionChangeToTodo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_writeFailed) ...[
                    Flexible(child: _writeFailureLabel(ds, l)),
                    const SizedBox(width: 8),
                    if (!_scheduling && !_event) ...[
                      Flexible(
                        child: TextButton(
                          onPressed: _saveToUnplanned,
                          style: TextButton.styleFrom(
                            foregroundColor: SpecTokens.ink2,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 44),
                          ),
                          child: Text(
                            l.captureActionSaveLater,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                  Flexible(child: _primaryButton(ds, l, desktop: false)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToUnplanned() async {
    setState(() {
      _start = null;
      _end = null;
      _due = null;
      _writeFailed = false;
    });
    await _save();
  }

  Widget _ellipsisButton(
    DsColors ds,
    AppLocalizations l, {
    required bool desktop,
  }) {
    return Tooltip(
      message: _scheduling || _event ? l.scheduleTodoDesc : l.openFullForm,
      child: SizedBox(
        height: desktop ? 29 : 44,
        child: TextButton(
          onPressed: _scheduling || _event ? null : _openFullForm,
          style: TextButton.styleFrom(
            foregroundColor: SpecTokens.ink,
            disabledForegroundColor: SpecTokens.faint,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(desktop ? 5 : 6),
              side: BorderSide(color: SpecTokens.hair2),
            ),
          ),
          child: const Icon(CupertinoIcons.ellipsis, size: 16),
        ),
      ),
    );
  }

  Widget _writeFailureLabel(DsColors ds, AppLocalizations l) {
    return Container(
      key: const ValueKey('a2-composer-write-failed'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SpecTokens.redSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: SpecTokens.red.withValues(alpha: 0.3)),
      ),
      child: Text(
        l.widgetSaveFailed,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: SpecTokens.red,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
  }

  Widget _primaryButton(
    DsColors ds,
    AppLocalizations l, {
    required bool desktop,
  }) {
    return SizedBox(
      height: desktop ? 29 : 44,
      child: FilledButton(
        onPressed: _canSave ? _save : null,
        style: FilledButton.styleFrom(
          backgroundColor: SpecTokens.ink,
          disabledBackgroundColor: SpecTokens.hair2,
          disabledForegroundColor: SpecTokens.faint,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(desktop ? 5 : 8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text(
          _primaryLabel(l),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFeatures: AppTypography.tabular,
          ),
        ),
      ),
    );
  }

  Widget _modeSwitcher(AppLocalizations l) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DsSegmented<bool>(
        selected: _scheduling,
        onSelected: _setMode,
        options: [
          DsSegmentOption(false, l.create),
          DsSegmentOption(true, l.scheduleTodo),
        ],
      ),
    );
  }

  /// The read-only title says what; this line names the action and repeats the
  /// task, so "this is the existing task, nothing new is created" is said in
  /// words. There is no "will update «X»" key yet, so this is the closest
  /// existing-key composition.
  Widget _boundNote(DsColors ds, AppLocalizations l) {
    return Text(
      '${l.scheduleTodo} · ${_boundTodo!.summary}',
      key: const ValueKey('a2-composer-bound-note'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: ds.ink3,
        fontFamilyFallback: AppTypography.fallback,
      ),
    );
  }

  Widget _titleField(DsColors ds, AppLocalizations l) {
    final readOnly = _scheduling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: ds.surface,
            border: Border.all(
              color: _titleValidationError ? SpecTokens.red : ds.line,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: readOnly
              ? Text(
                  _boundTodo!.summary,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: ds.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                )
              : TextField(
                  key: const ValueKey('a2-composer-title'),
                  controller: _title,
                  autofocus: true,
                  maxLines: null,
                  cursorColor: ds.primary,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: ds.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                  onChanged: _onTitleChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: l.composerPlaceholder,
                    hintStyle: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: ds.ink3,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
        ),
        if (_titleValidationError) ...[
          const SizedBox(height: 4),
          Text(
            l.captureValidationEmptyTitle,
            style: const TextStyle(
              fontSize: 11,
              color: SpecTokens.red,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SpecTokens.redSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l.captureValidationAlert,
              style: const TextStyle(
                fontSize: 11,
                color: SpecTokens.red,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _suggestionPanel(DsColors ds, AppLocalizations l) {
    final parsed = _parsed;
    final removed = _suggestionRemoved;
    final range = parsed.start != null && parsed.end != null
        ? '${_md(parsed.start!)} ${_range(parsed.start!, parsed.end!)}'
        : '';
    return Column(
      key: const ValueKey('a2-composer-suggestion'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const ValueKey('a2-composer-parsed-type'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                CupertinoIcons.calendar,
                size: 13,
                color: SpecTokens.muted,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.captureParsedTypeTodoTitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ds.ink2,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.captureParsedTypeTodoSub,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.45,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: SpecTokens.workSoft,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFDFE3E5)),
          ),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.clock,
                size: 13,
                color: SpecTokens.work,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      removed
                          ? l.captureParsedSuggestRemoved
                          : range.isEmpty
                          ? l.captureParsedSuggestTitle
                          : '$range · ${l.captureParsedSuggestTitle}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: SpecTokens.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      removed
                          ? l.captureParsedSuggestSubRemoved
                          : l.captureParsedSuggestSub,
                      style: const TextStyle(
                        fontSize: 9.5,
                        height: 1.4,
                        color: SpecTokens.muted,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('a2-composer-suggestion-toggle'),
                onPressed: removed ? _restoreSuggestion : _removeSuggestion,
                style: TextButton.styleFrom(
                  foregroundColor: SpecTokens.work,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  removed ? l.captureActionRestore : l.captureActionRemove,
                  style: const TextStyle(
                    fontSize: 10,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('a2-composer-suggestion-type'),
                onPressed: () => _setEvent(true),
                style: TextButton.styleFrom(
                  foregroundColor: SpecTokens.work,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l.captureActionChangeToEvent,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _eventWhenRow(DsColors ds, AppLocalizations l) {
    final hasSlot = _start != null && _end != null;
    return _FieldRow(
      key: const ValueKey('a2-composer-event-time'),
      icon: CupertinoIcons.clock,
      label: l.executionWhen,
      value: hasSlot
          ? _range(_start!, _end!, includeDate: true)
          : l.composerNoSlot,
      tone: hasSlot ? ds.primary : null,
      filled: hasSlot,
      fillColor: ds.primarySoft,
      onTap: () => setState(() => _planOpen = !_planOpen),
    );
  }

  Widget _fieldPair(DsColors ds, AppLocalizations l) {
    final dueOn = _due != null;
    final allocOn = _start != null;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FieldRow(
          key: const ValueKey('a2-composer-due'),
          icon: CupertinoIcons.flag,
          label: l.deadline,
          value: dueOn
              ? (_due!.hour == 0 && _due!.minute == 0
                    ? _md(_due!)
                    : _mdhm(_due!))
              : l.composerUnset,
          tone: dueOn ? ds.warn : null,
          filled: dueOn,
          fillColor: ds.warnSoft,
          // A series keeps its deadline inside the recurrence spec, so the
          // row stays read-only there instead of promising a write it refuses.
          onTap: _scheduling && _isRecurring(_boundTodo) ? null : _pickDue,
        ),
        _FieldRow(
          key: const ValueKey('a2-composer-plan'),
          icon: CupertinoIcons.clock,
          label: l.executionSchedule,
          value: allocOn
              ? _range(_start!, _end!, includeDate: true)
              : l.composerNoSlot,
          tone: allocOn ? ds.primary : null,
          filled: allocOn,
          fillColor: ds.primarySoft,
          onTap: () => setState(() => _planOpen = !_planOpen),
        ),
      ],
    );
  }

  Widget _slotChips(DsColors ds, AppLocalizations l) {
    final slots = _recommendedSlots();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 2.4,
      children: [
        for (final slot in slots)
          _SlotChip(
            label: _range(slot.$1, slot.$2),
            selected: _start == slot.$1 && _end == slot.$2,
            onTap: () {
              final wasSelected = _start == slot.$1 && _end == slot.$2;
              _setSlot(
                wasSelected ? null : slot.$1,
                wasSelected ? null : slot.$2,
              );
            },
          ),
        _SlotChip(
          label: l.composerCustomSlot,
          selected:
              _start != null &&
              !slots.any((s) => s.$1 == _start && s.$2 == _end),
          muted: true,
          onTap: () {
            final customSelected =
                _start != null &&
                !slots.any((s) => s.$1 == _start && s.$2 == _end);
            if (customSelected) {
              _setSlot(null, null);
            } else {
              _pickCustomSlot();
            }
          },
        ),
      ],
    );
  }

  Widget _hintLine(DsColors ds, AppLocalizations l) {
    if (_event) {
      final (text, color) = _start != null
          ? (l.captureHintEvent, ds.primary)
          : (l.composerHintNoSlot, ds.ink3);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 12, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: color,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      );
    }
    final (text, color) = _start != null
        ? (l.composerHintAlloc, ds.primary)
        : _due != null
        ? (l.composerHintDue, ds.warn)
        : (l.composerHintNoSlot, ds.ink3);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.info_circle, size: 12, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: color,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ],
    );
  }

  Widget _subRow(
    DsColors ds,
    String label,
    String value, {
    Key? key,
    VoidCallback? onTap,
    bool strong = false,
    bool last = false,
  }) {
    final row = Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: ds.ink2,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: strong ? ds.ink : ds.ink3,
                fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 14, color: ds.ink3),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: ds.surface2,
        focusColor: ds.surface2,
        child: row,
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
    this.filled = false,
    this.fillColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? tone;
  final bool filled;
  final Color? fillColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final color = tone ?? ds.ink3;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: filled ? fillColor ?? ds.surface2 : ds.surface,
        borderRadius: BorderRadius.circular(6),
        border: filled ? null : Border.all(color: ds.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: filled ? color : ds.ink2,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      ),
    );
    final target = SizedBox(
      height: 48,
      child: Center(widthFactor: 1, child: row),
    );
    if (onTap == null) return target;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: ds.surface2,
        focusColor: ds.surface2,
        child: target,
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: ds.surface2,
        focusColor: ds.surface2,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ds.primarySoft : ds.surface,
            borderRadius: BorderRadius.circular(6),
            border: selected ? null : Border.all(color: ds.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? ds.primary
                  : muted
                  ? ds.ink3
                  : ds.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ),
    );
  }
}
