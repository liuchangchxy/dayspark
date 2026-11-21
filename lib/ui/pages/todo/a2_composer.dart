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
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// The A″ composer: one sheet that writes exactly what the user expressed.
///
/// `dueDate` is only written from the 截止 row, a [TaskAllocation] only from a
/// chosen slot, and opening the sheet for a browsed day pre-fills neither — the
/// primary button says what will happen before the user taps it.
Future<void> showA2Composer(
  BuildContext context, {
  required DateTime contextDate,
  Todo? todo,
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  final composer = A2ComposerSheet(
    contextDate: contextDate,
    todo: todo,
    initialStart: initialStart,
    initialEnd: initialEnd,
  );
  // Desktop keeps its own overlay language: a centred dialog, not a phone
  // sheet stretched across the window. The composer chooses its chrome from
  // the same breakpoint, so the two calls cannot disagree.
  if (isWorkspaceLayout(context)) {
    return showDialog<void>(
      context: context,
      barrierColor: Theme.of(context).extension<DsColors>()?.scrim,
      builder: (_) => composer,
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Theme.of(context).extension<DsColors>()?.scrim,
    builder: (_) => composer,
  );
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
  });

  final DateTime contextDate;
  final Todo? todo;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  ConsumerState<A2ComposerSheet> createState() => _A2ComposerSheetState();
}

class _A2ComposerSheetState extends ConsumerState<A2ComposerSheet> {
  late final TextEditingController _title;
  DateTime? _due;
  DateTime? _start;
  DateTime? _end;
  int? _calendarId;
  int _priority = 0;
  Duration? _reminderOffset;
  bool _planOpen = false;
  bool _saving = false;
  bool _writeFailed = false;
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
    _title = TextEditingController(text: widget.todo?.summary ?? '');
    _boundTodo = widget.todo;
    _due = widget.todo?.dueDate;
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _priority = widget.todo?.priority ?? 0;
    _calendarId = widget.todo?.calendarId;
    _planOpen = false;
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
    final l = AppLocalizations.of(context)!;
    final start = await pickDateTime(
      context,
      initial:
          _start ??
          DateTime(
            widget.contextDate.year,
            widget.contextDate.month,
            widget.contextDate.day,
            9,
          ),
    );
    if (start == null || !mounted) return;
    final length = await showDsSheet<Duration>(
      context: context,
      title: l.executionBlock,
      body: Column(
        children: [
          for (final option in kExecutionLengths)
            DsSettingRow(
              label: _durationLabel(option),
              onTap: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    );
    if (length == null || !mounted) return;
    _setSlot(start, start.add(length));
    setState(() => _planOpen = true);
  }

  String _durationLabel(Duration d) {
    final l = AppLocalizations.of(context)!;
    if (d.inMinutes == 0) return l.durationMinutes(0);
    if (d.inMinutes % 60 == 0) return l.durationHours(d.inHours);
    return l.durationHoursMinutes(d.inHours, d.inMinutes % 60);
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim();
    if (_saving) return;
    if (!_scheduling && title.isEmpty) return;
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
        Navigator.of(context).pop();
        _toast(l.planToDate(_md(start)));
        return;
      }
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        _toast(l.noCalendar);
        setState(() => _saving = false);
        return;
      }
      final calendarId = _calendarId ?? calendars.first.id;
      final due = _due;
      final start = _start;
      final end = _end;
      final reminderOffset = _reminderOffset;
      final priority = _priority;
      await RecordScope.run(ref.read(databaseProvider), (tx) async {
        final todoId = await ref.read(createTodoProvider)(
          calendarId: calendarId,
          summary: title,
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
        Navigator.of(context).pop();
        _toast(l.planToDate(_md(start)));
        return;
      }
      Navigator.of(context).pop();
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
      (_scheduling
          ? _start != null && _end != null
          : _title.text.trim().isNotEmpty);

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
    String? calendarName;
    for (final calendar in calendars) {
      if (calendar.id == (_calendarId ?? calendars.first.id)) {
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
        const SizedBox(height: 10),
        _fieldPair(ds, l),
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
            l.calendarField,
            calendarName ?? (calendars.isEmpty ? '' : calendars.first.name),
            key: const ValueKey('a2-composer-calendar'),
            strong: calendarName != null,
            onTap: _pickCalendar,
          ),
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
            onTap: _pickPriority,
          ),
          // Notes live in the full form only; this row is the way there, and
          // it carries the title so the trip does not lose what was typed.
          _subRow(
            ds,
            l.notes,
            l.composerOptional,
            key: const ValueKey('a2-composer-notes'),
            last: true,
            onTap: _openFullForm,
          ),
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
      // DsDialog owns the 560px width, the content-height cap and the modal
      // route's focus scope (Tab cannot reach the page behind it). Keeping the
      // fields in one Column also fixes the Tab order: title, deadline, plan,
      // secondary rows, then the actions.
      return CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: _scheduling,
          canRequestFocus: _scheduling,
          skipTraversal: !_scheduling,
          child: DsDialog(
            title: l.planToDate('$dateText · $weekday'),
            actions: [
              _ellipsisButton(ds, l),
              const Spacer(),
              if (_writeFailed) ...[
                Flexible(child: _writeFailureLabel(ds, l)),
                const SizedBox(width: 8),
              ],
              _primaryButton(ds, l),
            ],
            child: fields,
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: _scheduling,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.92,
            ),
            decoration: BoxDecoration(
              color: ds.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              border: Border(top: BorderSide(color: ds.line)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ds.surface3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.planToDate('$dateText · $weekday'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: ds.ink,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
                      ),
                      _SheetIcon(
                        icon: CupertinoIcons.xmark,
                        tooltip: l.cancel,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: fields,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: ds.lineSoft)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        _ellipsisButton(ds, l),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_writeFailed) ...[
                                Flexible(child: _writeFailureLabel(ds, l)),
                                const SizedBox(width: 8),
                              ],
                              // The label names every value it will write, so
                              // it can outgrow a phone's action row; shrink and
                              // ellipsize instead of overflowing.
                              Flexible(child: _primaryButton(ds, l)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ellipsisButton(DsColors ds, AppLocalizations l) {
    return Tooltip(
      message: _scheduling ? l.scheduleTodoDesc : l.openFullForm,
      child: SizedBox(
        height: 44,
        child: TextButton(
          onPressed: _scheduling ? null : _openFullForm,
          style: TextButton.styleFrom(
            foregroundColor: ds.primary,
            disabledForegroundColor: ds.faint,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Icon(CupertinoIcons.ellipsis, size: 17),
        ),
      ),
    );
  }

  /// A failed write leaves the draft intact, so the button has to say that the
  /// next tap is a retry of something that did not land. Kept outside the
  /// button so neither chrome has to give the button unbounded width.
  Widget _writeFailureLabel(DsColors ds, AppLocalizations l) {
    return Text(
      l.widgetSaveFailed,
      key: const ValueKey('a2-composer-write-failed'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: ds.danger,
        fontFamilyFallback: AppTypography.fallback,
      ),
    );
  }

  Widget _primaryButton(DsColors ds, AppLocalizations l) {
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: _canSave ? _save : null,
        style: FilledButton.styleFrom(
          backgroundColor: ds.primary,
          disabledBackgroundColor: ds.surface3,
          disabledForegroundColor: ds.faint,
          foregroundColor: ds.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text(
          _primaryLabel(l),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Values are inline in the label, so they line up like the field
          // rows above them rather than jittering with proportional digits.
          style: const TextStyle(fontFeatures: AppTypography.tabular),
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
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: ds.surface,
        border: Border.all(color: ds.line),
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
              onChanged: (_) => setState(() {}),
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

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: ds.ink3),
        ),
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
