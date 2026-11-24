import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart' show FocusableTap;
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_picker.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

class CalendarSlotSheet extends ConsumerStatefulWidget {
  final DateTimeRange range;
  final VoidCallback onCreateEvent;
  final Future<void> Function(Todo todo, String? occurrenceId) onScheduleTodo;
  final Future<List<Todo>> Function() loadSchedulableTodos;

  /// Starts a todo form that will create the todo and its scheduled block in
  /// one save. Null when the caller cannot offer it.
  final VoidCallback? onCreateTodoHere;

  /// True when the tapped range already carries an event. The head then states
  /// the span as a fact instead of labelling it an editable default.
  final bool isExistingBlock;

  /// The spec slot surface: a prefilled create-event panel. The three-action
  /// launcher is kept for direct construction and older hosts; every product
  /// entry (`.show`) opens the capture panel.
  final bool capture;

  const CalendarSlotSheet({
    super.key,
    required this.range,
    required this.onCreateEvent,
    required this.onScheduleTodo,
    required this.loadSchedulableTodos,
    this.onCreateTodoHere,
    this.isExistingBlock = false,
    this.capture = false,
  });

  static Future<void> show({
    required BuildContext context,
    required DateTimeRange range,
    required VoidCallback onCreateEvent,
    required Future<void> Function(Todo todo, String? occurrenceId)
    onScheduleTodo,
    required Future<List<Todo>> Function() loadSchedulableTodos,
    VoidCallback? onCreateTodoHere,
    bool isExistingBlock = false,
    bool capture = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.ds.scrim,
      elevation: 0,
      builder: (ctx) => CalendarSlotSheet(
        range: range,
        onCreateEvent: onCreateEvent,
        onScheduleTodo: onScheduleTodo,
        loadSchedulableTodos: loadSchedulableTodos,
        onCreateTodoHere: onCreateTodoHere,
        isExistingBlock: isExistingBlock,
        capture: capture,
      ),
    );
  }

  @override
  ConsumerState<CalendarSlotSheet> createState() => _CalendarSlotSheetState();
}

TextStyle _slotText(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
  bool tabular = false,
}) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    fontFeatures: tabular ? AppTypography.tabular : null,
  );
  if (AppTypography.fallback.isEmpty) return style;
  return style.copyWith(fontFamilyFallback: AppTypography.fallback);
}

enum _CandidatesState { loading, ready, failed }

class _CalendarSlotSheetState extends ConsumerState<CalendarSlotSheet> {
  bool _showingTodoPicker = false;
  _CandidatesState _candidatesState = _CandidatesState.loading;
  List<Todo> _candidates = const [];

  late final TextEditingController _title;
  late DateTimeRange _range;
  int? _calendarId;
  String? _location;
  Duration? _reminder;
  bool _saving = false;
  bool _writeFailed = false;
  bool _titleError = false;

  @override
  void initState() {
    super.initState();
    _range = widget.range;
    _title = TextEditingController();
    _title.addListener(() {
      if (_titleError && _title.text.trim().isNotEmpty && mounted) {
        setState(() => _titleError = false);
      }
    });
    // The spec panel prefills the event reminder at 15 minutes; a todo has no
    // reminder by default, so the split stays honest.
    _reminder = const Duration(minutes: 15);
    // The count badge on "Schedule Task" is part of the sheet itself, so the
    // candidate list is read once on open rather than only when that row is
    // tapped. A failure stays on that row; the other two actions never wait.
    _loadCandidates();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    try {
      final list = await widget.loadSchedulableTodos();
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _candidatesState = _CandidatesState.ready;
      });
    } catch (error) {
      debugPrint(
        'calendar slot sheet: loading schedulable todos failed: $error',
      );
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _candidatesState = _CandidatesState.failed;
      });
    }
  }

  void _retryCandidates() {
    setState(() => _candidatesState = _CandidatesState.loading);
    _loadCandidates();
  }

  void _openTodoPicker() {
    if (_candidatesState == _CandidatesState.failed) return;
    if (_candidatesState == _CandidatesState.ready && _candidates.isEmpty) {
      return;
    }
    setState(() => _showingTodoPicker = true);
  }

  String _dateLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final start = widget.range.start;
    final date = DateFormat.MMMMd(locale).format(start);
    final weekday = DateFormat.E(locale).format(start);
    return '$date · $weekday';
  }

  String _spanLabel() {
    final start = widget.range.start;
    final end = widget.range.end;
    return '${DateFormatters.formatTime(start)}–'
        '${DateFormatters.formatTime(end)}';
  }

  /// The head's second line: a resolved span plus what kind of span it is.
  /// An empty slot carries a chosen length the user can still change, so the
  /// line marks it as editable; an existing block states the span as a fact.
  /// Every action below writes the same `range`, so nothing can drift from it.
  String _rangeDetail(AppLocalizations l) {
    final span = _spanLabel();
    if (widget.isExistingBlock) return '$span · ${l.slotRangeExistingEvent}';
    final minutes = widget.range.end.difference(widget.range.start).inMinutes;
    final length = minutes % 60 == 0
        ? l.durationHours(minutes ~/ 60)
        : l.durationMinutes(minutes);
    return '$span · $length · ${l.slotRangeDefaultEditable}';
  }

  String _spanOf(DateTimeRange range) =>
      '${DateFormatters.formatTime(range.start)}–'
      '${DateFormatters.formatTime(range.end)}';

  String _captureTimeLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.MMMd(locale).format(_range.start)} '
        '${_spanOf(_range)}';
  }

  String _reminderLabelText(AppLocalizations l) {
    final offset = _reminder;
    if (offset == null) return l.remindNone;
    if (offset == Duration.zero) return l.remindOnTime;
    if (offset.inDays >= 1) return l.remindDaysBefore(offset.inDays);
    if (offset.inHours >= 1) return l.remindHoursBefore(offset.inHours);
    return l.remindMinutesBefore(offset.inMinutes);
  }

  Future<void> _pickCaptureTime() async {
    final picked = await SpecPlanPickerDialog.show(
      context,
      title: _title.text.trim(),
      initialStart: _range.start,
      initialEnd: _range.end,
      isEditing: true,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = DateTimeRange(start: picked.$1, end: picked.$2));
  }

  Future<void> _pickCaptureCalendar() async {
    final picked = await pickCalendar(context, ref, selectedId: _calendarId);
    if (picked != null && mounted) setState(() => _calendarId = picked);
  }

  Future<void> _pickCaptureLocation() async {
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

  Future<void> _pickCaptureReminder() async {
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
    final picked = await showDsSheet<_SlotReminderChoice>(
      context: context,
      title: l.reminder,
      body: Column(
        children: [
          for (final option in options)
            DsSettingRow(
              label: option.$2,
              selected: _reminder == option.$1,
              onTap: () => Navigator.of(context).pop(
                _SlotReminderChoice(option.$1),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _reminder = picked.offset);
  }

  Future<void> _saveCapture() async {
    if (_saving) return;
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    setState(() {
      _saving = true;
      _writeFailed = false;
    });
    final calendars = await ref.read(calendarsProvider.future);
    if (!mounted) return;
    if (calendars.isEmpty) {
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
    try {
      final eventId = await ref.read(createEventProvider)(
        calendarId: calendarId,
        summary: title,
        startDt: _range.start,
        endDt: _range.end,
        isAllDay: false,
        location: _location,
      );
      final offset = _reminder;
      if (offset != null) {
        await ref.read(createReminderProvider)(
          parentType: 'event',
          parentId: eventId,
          triggerTime: _range.start.subtract(offset),
        );
      }
      if (!mounted) return;
      showSpecToast(context, l.eventCreated);
      await Navigator.of(context).maybePop();
    } catch (error) {
      debugPrint('calendar slot capture: create event failed: $error');
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
    final ds = context.ds;
    if (widget.capture) return _captureSheet(context, l, ds);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(top: BorderSide(color: ds.line)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6B141410),
            offset: Offset(0, -10),
            blurRadius: 32,
            spreadRadius: -20,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSheetChrome(
              title: _showingTodoPicker
                  ? l.selectTodoToSchedule
                  : _dateLabel(context),
              headerAction: _showingTodoPicker
                  ? DsIconButton(
                      icon: CupertinoIcons.back,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () =>
                          setState(() => _showingTodoPicker = false),
                    )
                  : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _rangeDetail(l),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _slotText(
                          12,
                          FontWeight.w500,
                          ds.ink3,
                          height: 1.35,
                          tabular: true,
                        ),
                      ),
                    ),
                    if (!_showingTodoPicker) ..._actions(context, l),
                    if (_showingTodoPicker) ..._todoPicker(context, l),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureSheet(
    BuildContext context,
    AppLocalizations l,
    DsColors ds,
  ) {
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final defaultId = resolveNewEntryCalendarId(
      calendars: calendars,
      preferredId: ref.read(defaultCalendarIdProvider),
    );
    final activeId = _calendarId ?? defaultId;
    Calendar? calendar;
    for (final item in calendars) {
      if (item.id == activeId) calendar = item;
    }
    final calendarName = calendar?.name ?? l.calendarField;
    final locale = Localizations.localeOf(context).toString();
    final sub =
        '${l.slotCaptureFrom} · '
        '${DateFormat.MMMd(locale).format(_range.start)} '
        '${_spanOf(_range)} · $calendarName';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(top: BorderSide(color: ds.line)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6B141410),
            offset: Offset(0, -10),
            blurRadius: 32,
            spreadRadius: -20,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSheetChrome(
              title: _showingTodoPicker ? l.selectTodoToSchedule : l.newEvent,
              headerAction: _showingTodoPicker
                  ? DsIconButton(
                      icon: CupertinoIcons.back,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () =>
                          setState(() => _showingTodoPicker = false),
                    )
                  : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: _showingTodoPicker
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _todoPicker(context, l),
                      )
                    : _captureForm(context, l, ds, sub, calendarName),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureForm(
    BuildContext context,
    AppLocalizations l,
    DsColors ds,
    String sub,
    String calendarName,
  ) {
    return Column(
      key: const ValueKey('slot-capture-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _slotText(9.5, FontWeight.w400, ds.faint, height: 1.4),
            ),
          ),
        if (_writeFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.actionFailedRetry,
              key: const ValueKey('slot-capture-error'),
              style: _slotText(11, FontWeight.w400, ds.danger),
            ),
          ),
        TextField(
          key: const ValueKey('slot-capture-title'),
          controller: _title,
          autofocus: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: l.captureFieldEventTitle,
            errorText: _titleError ? l.titleRequired : null,
            isDense: true,
          ),
          style: _slotText(17, FontWeight.w600, ds.ink, height: 1.3),
        ),
        const SizedBox(height: 6),
        _CaptureField(
          key: const ValueKey('slot-capture-time'),
          label: l.captureFieldEventTime,
          value: _captureTimeLabel(context),
          onTap: _pickCaptureTime,
        ),
        _CaptureField(
          key: const ValueKey('slot-capture-calendar'),
          label: l.captureFieldCalendar,
          value: calendarName,
          onTap: _pickCaptureCalendar,
        ),
        _CaptureField(
          key: const ValueKey('slot-capture-location'),
          label: l.location,
          value: _location?.isNotEmpty == true ? _location! : l.locationHint,
          onTap: _pickCaptureLocation,
        ),
        _CaptureField(
          key: const ValueKey('slot-capture-reminder'),
          label: l.captureFieldReminder,
          value: _reminderLabelText(l),
          onTap: _pickCaptureReminder,
        ),
        const SizedBox(height: 8),
        // Spec cp-foot: the hint explains the common surface; the actions are
        // Cancel and the one filled button, Create event.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                l.slotCaptureHint,
                style: _slotText(9.5, FontWeight.w400, ds.faint, height: 1.45),
              ),
            ),
            const SizedBox(width: 10),
            _CaptureButton(
              key: const ValueKey('slot-capture-cancel'),
              label: l.cancel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            _CaptureButton(
              key: const ValueKey('slot-capture-create'),
              label: _writeFailed
                  ? l.retrySave
                  : (_saving ? l.savingLabel : l.createEventAction),
              primary: true,
              onTap: _saving ? null : _saveCapture,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: ds.lineSoft),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
          child: Text(
            l.slotOtherWays,
            style: _slotText(9, FontWeight.w600, ds.faint, height: 1.3),
          ),
        ),
        if (widget.onCreateTodoHere != null)
          _CaptureLinkRow(
            key: const ValueKey('slot-capture-create-schedule'),
            label: l.createTodoAndSchedule,
            subtitle: l.createTodoAndScheduleDesc,
            onTap: () {
              Navigator.of(context).maybePop();
              widget.onCreateTodoHere!();
            },
          ),
        _CaptureLinkRow(
          key: const ValueKey('slot-action-schedule-todo'),
          label: l.scheduleTodo,
          subtitle: switch (_candidatesState) {
            _CandidatesState.loading => '·',
            _CandidatesState.failed => l.actionFailedRetry,
            _CandidatesState.ready =>
              _candidates.isEmpty ? l.noSchedulableTodos : l.scheduleTodoDesc,
          },
          count: _candidatesState == _CandidatesState.ready
              ? _candidates.length
              : null,
          onTap: _candidatesState == _CandidatesState.failed
              ? _retryCandidates
              : _openTodoPicker,
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return [
      _SolidActionRow(
        key: const ValueKey('slot-action-event'),
        icon: CupertinoIcons.calendar_badge_plus,
        title: l.createEventOption,
        subtitle: l.createEventDesc,
        onTap: () {
          Navigator.of(context).pop();
          widget.onCreateEvent();
        },
      ),
      if (widget.onCreateTodoHere != null) ...[
        const SizedBox(height: 8),
        _OutlinedActionRow(
          key: const ValueKey('slot-action-create-schedule'),
          icon: CupertinoIcons.add,
          title: l.createTodoAndSchedule,
          subtitle: l.createTodoAndScheduleDesc,
          onTap: () {
            Navigator.of(context).pop();
            widget.onCreateTodoHere!();
          },
        ),
      ],
      const SizedBox(height: 4),
      _ScheduleTodoRow(
        key: const ValueKey('slot-action-schedule-todo'),
        state: _candidatesState,
        count: _candidates.length,
        onTap: _openTodoPicker,
        onRetry: _retryCandidates,
      ),
      if (_candidatesState == _CandidatesState.ready &&
          _candidates.isEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(38, 0, 4, 0),
          child: Text(
            l.slotEmptyCreateHint,
            key: const ValueKey('slot-schedule-empty-hint'),
            maxLines: 2,
            style: _slotText(12, FontWeight.w400, ds.ink3, height: 1.4),
          ),
        ),
        if (widget.onCreateTodoHere != null)
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DsButton(
                key: const ValueKey('slot-empty-create-schedule'),
                label: l.createTodoAndSchedule,
                tone: DsButtonTone.ghost,
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onCreateTodoHere!();
                },
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _todoPicker(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return [
      Container(height: 1, color: ds.lineSoft),
      if (_candidatesState == _CandidatesState.loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_candidatesState == _CandidatesState.failed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.actionFailedRetry,
                textAlign: TextAlign.center,
                style: _slotText(15, FontWeight.w400, ds.ink2, height: 1.4),
              ),
              const SizedBox(height: 6),
              DsButton(
                label: l.retry,
                tone: DsButtonTone.ghost,
                onPressed: _retryCandidates,
              ),
            ],
          ),
        )
      else if (_candidates.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.noSchedulableTodos,
                textAlign: TextAlign.center,
                style: _slotText(15, FontWeight.w400, ds.ink2, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                l.slotEmptyCreateHint,
                textAlign: TextAlign.center,
                style: _slotText(12, FontWeight.w400, ds.ink3, height: 1.4),
              ),
              if (widget.onCreateTodoHere != null) ...[
                const SizedBox(height: 8),
                DsButton(
                  key: const ValueKey('slot-empty-create-schedule'),
                  label: l.createTodoAndSchedule,
                  tone: DsButtonTone.ghost,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onCreateTodoHere!();
                  },
                ),
              ],
            ],
          ),
        )
      else
        Column(
          children: [
            for (final todo in _candidates)
              _SlotRow(
                icon: todo.rrule != null && todo.rrule!.isNotEmpty
                    ? CupertinoIcons.repeat
                    : CupertinoIcons.circle,
                title: todo.summary,
                subtitle: todo.rrule != null && todo.rrule!.isNotEmpty
                    ? l.recurringTask
                    : (todo.dueDate != null
                          ? '${l.dueDate}: ${DateFormatters.formatShortDate(todo.dueDate!)}'
                          : l.noDueDate),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  if (todo.rrule != null && todo.rrule!.isNotEmpty) {
                    final selected = await TodoOccurrencePickerSheet.show(
                      context,
                      ref: ref,
                      todo: todo,
                      anchorDate: widget.range.start,
                    );
                    if (selected == null || !mounted) return;
                    navigator.pop();
                    await _invokeScheduleTodo(todo, selected.occurrenceId);
                  } else {
                    navigator.pop();
                    await _invokeScheduleTodo(todo);
                  }
                },
              ),
          ],
        ),
    ];
  }

  Future<void> _invokeScheduleTodo(Todo todo, [String? occurrenceId]) =>
      widget.onScheduleTodo(todo, occurrenceId);
}

/// The sheet's only filled action. Frequency, not importance, sets the order:
/// creating an event is the everyday path, so it reads as the primary button.
class _SolidActionRow extends StatelessWidget {
  const _SolidActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SpecTokens.ink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(child: Icon(icon, size: 18, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, Colors.white),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(
                        12,
                        FontWeight.w400,
                        Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shortcut, not the main path: outlined on surface-2 so it reads as one
/// step quieter than the filled row above it.
class _OutlinedActionRow extends StatelessWidget {
  const _OutlinedActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ds.surface2,
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(child: Icon(icon, size: 18, color: ds.ink2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, ds.ink),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(12, FontWeight.w400, ds.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_right, size: 14, color: ds.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The heaviest action sits last and reads as plain text: it opens a second
/// sheet and writes an allocation, so it must never compete with the primary
/// row. The count badge says how much work it leads to; at zero the row is
/// disabled and says why instead of opening an empty picker.
class _ScheduleTodoRow extends StatelessWidget {
  const _ScheduleTodoRow({
    super.key,
    required this.state,
    required this.count,
    required this.onTap,
    required this.onRetry,
  });

  final _CandidatesState state;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final failed = state == _CandidatesState.failed;
    final empty = state == _CandidatesState.ready && count == 0;
    final enabled = !failed && !empty;
    final titleColor = enabled ? ds.ink : ds.ink3;
    final subtitleColor = enabled ? ds.ink2 : ds.ink3;
    final subtitle = failed
        ? l.actionFailedRetry
        : empty
        ? l.noSchedulableTodos
        : l.scheduleTodoDesc;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              Container(
                key: const ValueKey('slot-schedule-count'),
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ds.surface3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state == _CandidatesState.loading ? '·' : '$count',
                  style: _slotText(
                    11,
                    FontWeight.w600,
                    enabled ? ds.ink2 : ds.ink3,
                    height: 1,
                    tabular: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.scheduleTodo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, titleColor),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(12, FontWeight.w400, subtitleColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (failed)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const ValueKey('slot-schedule-retry'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        l.retry,
                        style: _slotText(13, FontWeight.w600, ds.primary),
                      ),
                    ),
                  ),
                )
              else if (enabled)
                Icon(CupertinoIcons.chevron_right, size: 14, color: ds.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {  const _SlotRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(child: Icon(icon, size: 20, color: ds.ink2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, ds.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w400, ds.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_right, size: 14, color: ds.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spec .cp-field: label on the left in muted, value on the right in ink-2,
/// 37px minimum height, hairline above. Every row is a button because every
/// field can be changed before the event is created.
class _CaptureField extends StatelessWidget {
  const _CaptureField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 37),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              Text(label, style: _slotText(11, FontWeight.w400, ds.ink3)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _slotText(11, FontWeight.w400, ds.ink2),
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_right, size: 11, color: ds.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spec .cp-actions .btn: 29px, 1px hairline border, 5px radius. The primary
/// one is ink-filled; the cancel one is paper.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return FocusableTap(
      onTap: onTap,
      semanticsLabel: label,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? ds.ink : ds.surface,
          border: Border.all(color: primary ? ds.ink : ds.lineSoft),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: _slotText(
            10.5,
            primary ? FontWeight.w600 : FontWeight.w400,
            primary ? Colors.white : ds.ink,
          ),
        ),
      ),
    );
  }
}

/// The honest home for the two non-event actions the spec panel has no slot
/// for: "New & schedule" and "Schedule Task" sit under an "Other scheduling
/// options" divider instead of being deleted or silently losing reach.
class _CaptureLinkRow extends StatelessWidget {
  const _CaptureLinkRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.count,
  });

  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(CupertinoIcons.calendar, size: 15, color: ds.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: _slotText(13, FontWeight.w500, ds.ink)),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(10.5, FontWeight.w400, ds.faint),
                    ),
                  ],
                ),
              ),
              if (count != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: ds.surface2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$count',
                    style: _slotText(
                      10,
                      FontWeight.w600,
                      ds.ink3,
                      height: 1.2,
                      tabular: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(CupertinoIcons.chevron_right, size: 12, color: ds.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotReminderChoice {
  const _SlotReminderChoice(this.offset);

  final Duration? offset;
}
