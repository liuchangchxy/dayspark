import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/domain/utils/capture_parser.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_drawer_overlay.dart';
import 'package:dayspark/ui/design/spec_pickers.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

import 'a2_composer.dart';
import 'capture_panel_submit.dart';
import 'month_year_picker.dart';

/// 待办: unplanned, every task, or one browsed day. The three modes share the
/// page header; only the list and the bottom entry change. The browse date is
/// the calendar's, so switching here never rewrites a deadline.
class A2TodoPage extends ConsumerStatefulWidget {
  const A2TodoPage({
    super.key,
    required this.now,
    required this.dayAgenda,
    this.onOpenTodo,
    this.onToggleTodo,
    this.onCapture,
    this.onCaptureDraft,
    this.onPlanDay,
    this.onScheduleTodo,
    this.onOpenEvent,
    this.onOpenUnplanned,
    this.dayAgendaLoading = false,
    this.dayAgendaFailed = false,
    this.onRetryDayAgenda,
    this.trailingActions = const <Widget>[],
    this.detail,
  });

  final DateTime now;
  final DayAgenda dayAgenda;
  final ValueChanged<Todo>? onOpenTodo;
  /// Returns whether the write actually happened; a dismissed occurrence
  /// picker must not read as a completion.
  final Future<bool> Function(Todo todo, String? occurrenceId, bool completed)?
  onToggleTodo;
  final Future<void> Function(String text)? onCapture;
  final Future<bool> Function(String text, A2CaptureDraft draft)?
  onCaptureDraft;
  final ValueChanged<DateTime>? onPlanDay;
  final ValueChanged<Todo>? onScheduleTodo;
  final ValueChanged<CalendaEventAdapter>? onOpenEvent;
  final VoidCallback? onOpenUnplanned;
  final bool dayAgendaLoading;
  final bool dayAgendaFailed;
  final VoidCallback? onRetryDayAgenda;
  final List<Widget> trailingActions;
  final Widget? detail;

  @override
  ConsumerState<A2TodoPage> createState() => _A2TodoPageState();
}

class _A2TodoPageState extends ConsumerState<A2TodoPage> {
  static const Duration _undoWindow = Duration(seconds: 4);

  bool _captureFocused = false;
  bool _completedOpen = false;
  A2CaptureState _desktopCaptureState = A2CaptureState.compact;
  A2CaptureState _captureChoiceReturnState = A2CaptureState.expanded;
  A2CaptureDraft _desktopCaptureDraft = const A2CaptureDraft();
  A2CaptureDraft? _captureChoiceBaseline;
  DateTime? _planDraftStart;
  DateTime? _planDraftEnd;
  DateTime? _suggestedPlanStart;
  DateTime? _suggestedPlanEnd;
  bool _suggestionRemoved = false;
  bool _capturing = false;
  bool _resetCaptureScheduled = false;
  final TextEditingController _desktopCaptureController = TextEditingController();
  Map<int, Calendar> _calendarMap = const {};
  Map<int, int> _currentMissedCounts = const {};

  final Map<String, _UndoEntry> _undoEntries = {};
  final Map<String, _UndoSlot> _lastSlots = {};
  final Map<String, Timer> _undoTimers = {};
  final Map<String, int> _undoGenerations = {};

  final LayerLink _filterToolLink = LayerLink();
  final FocusScopeNode _filterScopeNode =
      FocusScopeNode(debugLabel: 'todos-filter-popover');
  final FocusNode _filterToolFocusNode =
      FocusNode(debugLabel: 'todos-filter-tool');
  final FocusNode _filterInitialFocusNode =
      FocusNode(debugLabel: 'todos-filter-initial');
  OverlayEntry? _filterOverlay;

  @override
  void dispose() {
    _closeFilterOverlay(restoreFocus: false);
    _filterScopeNode.dispose();
    _filterToolFocusNode.dispose();
    _filterInitialFocusNode.dispose();
    for (final timer in _undoTimers.values) {
      timer.cancel();
    }
    _desktopCaptureController.dispose();
    super.dispose();
  }

  void _closeFilterOverlay({bool restoreFocus = true}) {
    final overlay = _filterOverlay;
    _filterOverlay = null;
    overlay?.remove();
    if (restoreFocus && mounted) {
      _filterToolFocusNode.requestFocus();
    }
  }

  String get _locale => Localizations.localeOf(context).toString();

  DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

  bool _isOverdue(DateTime due) {
    return isOverdueByDate(due, widget.now);
  }

  Future<void> _toggle(
    Todo todo,
    String? occurrenceId,
    bool completed, {
    _UndoSlot? slot,
  }) async {
    await _setCompleted(todo, occurrenceId, completed, slot: slot);
  }

  /// Undo goes back through the same callback, occurrence id included, so a
  /// recurring instance is reopened at the occurrence it was completed on.
  /// A completion keeps the row in place for the spec's four-second undo
  /// window; that window is the visible, unambiguous counterpart to the
  /// snackbar's undo.
  Future<void> _setCompleted(
    Todo todo,
    String? occurrenceId,
    bool completed, {
    _UndoSlot? slot,
  }) async {
    final callback = widget.onToggleTodo;
    if (callback == null) return;
    try {
      final changed = await callback(todo, occurrenceId, completed);
      if (!changed) return;
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
      return;
    }
    if (!mounted) return;
    _invalidateTodoLists();
    final key = _undoKey(todo.id, occurrenceId);
    if (completed) {
      _openUndoWindow(key, todo, occurrenceId, slot);
    } else {
      _closeUndoWindow(key);
    }
    final l = AppLocalizations.of(context);
    if (l == null) return;
    showUndoBar(
      context,
      message: completed ? l.completed : l.openTask,
      undoLabel: l.undo,
      onUndo: () => _setCompleted(todo, occurrenceId, !completed),
    );
  }

  // R5: completion is one event, so every list that counts or shows todos is
  // refreshed here instead of waiting for the user to switch tabs.
  void _invalidateTodoLists() {
    ref.invalidate(pendingTodosProvider);
    ref.invalidate(inboxTodosProvider);
    ref.invalidate(unplannedTodosProvider);
    ref.invalidate(allTodosProvider);
    ref.invalidate(completedTodosProvider);
    ref.invalidate(allActiveTaskAllocationsProvider);
    ref.invalidate(actionProjectionProvider);
    ref.invalidate(actionDueTodayTodosProvider);
    ref.invalidate(actionOverdueTodosProvider);
    ref.invalidate(actionCompletedTodayTodosProvider);
    ref.invalidate(actionActiveRecurringTodosProvider);
    ref.invalidate(actionAllNotDeletedTodosProvider);
    ref.invalidate(actionTaskInstanceStatesProvider);
  }

  String _undoKey(int todoId, String? occurrenceId) =>
      '$todoId|${occurrenceId ?? ''}';

  bool _inUndoWindow(int todoId, String? occurrenceId) =>
      _undoEntries.containsKey(_undoKey(todoId, occurrenceId));

  void _openUndoWindow(
    String key,
    Todo todo,
    String? occurrenceId,
    _UndoSlot? slot,
  ) {
    _undoTimers.remove(key)?.cancel();
    final generation = (_undoGenerations[key] ?? 0) + 1;
    _undoGenerations[key] = generation;
    if (slot != null) _lastSlots[key] = slot;
    final resolvedSlot = slot ?? _lastSlots[key];
    _undoTimers[key] = Timer(_undoWindow, () {
      if (!mounted || _undoGenerations[key] != generation) return;
      _undoTimers.remove(key);
      setState(() => _undoEntries.remove(key));
    });
    setState(() {
      _undoEntries[key] = _UndoEntry(
        todo: todo,
        occurrenceId: occurrenceId,
        slot: resolvedSlot,
      );
    });
  }

  void _closeUndoWindow(String key) {
    _undoTimers.remove(key)?.cancel();
    _undoGenerations[key] = (_undoGenerations[key] ?? 0) + 1;
    if (!_undoEntries.containsKey(key)) return;
    setState(() => _undoEntries.remove(key));
  }

  /// The occurrence's own label (the same string the occurrence picker shows),
  /// so a recurring row's undo names the instance it is about to reopen.
  String? _occurrenceLabel(String? occurrenceId) {
    if (occurrenceId == null) return null;
    try {
      final nominal = OccurrenceId.parse(occurrenceId).nominal;
      final canonical = nominal.canonical;
      return nominal.valueType == RecurrenceValueType.date
          ? canonical
          : canonical.replaceFirst('T', '  ');
    } on Object {
      return null;
    }
  }

  String _undoLabel(AppLocalizations l, String? occurrenceId) {
    final label = _occurrenceLabel(occurrenceId);
    return label == null ? l.undo : l.undoOccurrence(label);
  }

  DateTime _scheduleContextDate() {
    final view = ref.read(todosViewProvider);
    if (view is TodosDayView) return ref.read(viewedDateProvider);
    return _dayOf(widget.now);
  }

  void _schedule(Todo todo) {
    final onSchedule = widget.onScheduleTodo;
    if (onSchedule != null) {
      onSchedule(todo);
      return;
    }
    showA2Composer(
      context,
      contextDate: _scheduleContextDate(),
      todo: todo,
    );
  }

  Future<bool> _capture(
    String text, {
    A2CaptureDraft draft = const A2CaptureDraft(),
  }) async {
    if (_capturing) return false;
    _capturing = true;
    try {
      final draftCallback = widget.onCaptureDraft;
      if (draftCallback != null) {
        return await draftCallback(text, draft);
      }
      final callback = widget.onCapture;
      if (callback == null) return false;
      await callback(text);
      return true;
    } on Object catch (error) {
      debugPrint('todo: capture failed: $error');
      if (mounted) showCompletionError(context, error);
      return false;
    } finally {
      _capturing = false;
    }
  }

  void _openCaptureChoice(A2CaptureState state) {
    setState(() {
      _captureChoiceBaseline = _desktopCaptureDraft;
      _captureChoiceReturnState = _desktopCaptureState;
      _desktopCaptureState = state;
    });
  }

  void _applyCaptureChoice() {
    final returnState = _captureChoiceReturnState;
    setState(() {
      if (_desktopCaptureState == A2CaptureState.plan) {
        _desktopCaptureDraft = _desktopCaptureDraft.withPlan(
          _planDraftStart,
          _planDraftEnd,
        );
      }
      _captureChoiceBaseline = null;
      _planDraftStart = null;
      _planDraftEnd = null;
      _captureChoiceReturnState = A2CaptureState.expanded;
      _desktopCaptureState = returnState;
    });
  }

  void _cancelCaptureChoice() {
    final returnState = _captureChoiceReturnState;
    setState(() {
      final baseline = _captureChoiceBaseline;
      if (baseline != null) _desktopCaptureDraft = baseline;
      _captureChoiceBaseline = null;
      _planDraftStart = null;
      _planDraftEnd = null;
      _captureChoiceReturnState = A2CaptureState.expanded;
      _desktopCaptureState = returnState;
    });
  }

  void _chooseCaptureReminder(Duration? offset) {
    final l = AppLocalizations.of(context)!;
    if (offset != null &&
        _desktopCaptureDraft.dueDate == null &&
        _desktopCaptureDraft.planStart == null) {
      showSpecToast(context, l.reminderNeedsAnchor);
      return;
    }
    setState(() {
      _desktopCaptureDraft = _desktopCaptureDraft.withReminderOffset(offset);
    });
  }

  Future<void> _pickCaptureDueDate() async {
    final now = DateTime.now();
    final picked = await showSpecDatePicker(
      context,
      initialDate: _desktopCaptureDraft.dueDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _desktopCaptureDraft = _desktopCaptureDraft.withDueDate(
        DateTime(picked.year, picked.month, picked.day),
      );
      _desktopCaptureState = A2CaptureState.expanded;
    });
  }

  void _openPlanCapture() {
    final now = DateTime.now();
    setState(() {
      _captureChoiceBaseline = _desktopCaptureDraft;
      _captureChoiceReturnState = _desktopCaptureState;
      final start = _desktopCaptureDraft.planStart ??
          DateTime(now.year, now.month, now.day, 15, 15);
      _planDraftStart = start;
      _planDraftEnd = _desktopCaptureDraft.planEnd ??
          start.add(const Duration(minutes: 45));
      _desktopCaptureState = A2CaptureState.plan;
    });
  }

  Future<void> _pickCapturePlanDate() async {
    final start = _planDraftStart ?? DateTime.now();
    final end = _planDraftEnd;
    final picked = await showSpecDatePicker(
      context,
      initialDate: start,
      firstDate: DateTime(start.year - 5),
      lastDate: DateTime(start.year + 10),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _planDraftStart =
          DateTime(day.year, day.month, day.day, start.hour, start.minute);
      _planDraftEnd = end == null
          ? null
          : DateTime(day.year, day.month, day.day, end.hour, end.minute);
    });
  }

  Future<void> _pickCapturePlanStart() async {
    final current = _planDraftStart ?? DateTime.now();
    final picked = await showSpecTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    final start = DateTime(
      current.year,
      current.month,
      current.day,
      picked.hour,
      picked.minute,
    );
    final end = _planDraftEnd;
    setState(() {
      _planDraftStart = start;
      _planDraftEnd = end != null && end.isAfter(start)
          ? end
          : start.add(const Duration(minutes: 45));
    });
  }

  Future<void> _pickCapturePlanEnd() async {
    final start = _planDraftStart;
    if (start == null) return;
    final current =
        _planDraftEnd ?? start.add(const Duration(minutes: 45));
    final picked = await showSpecTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    final end = DateTime(
      start.year,
      start.month,
      start.day,
      picked.hour,
      picked.minute,
    );
    if (!end.isAfter(start)) return;
    setState(() {
      _planDraftEnd = end;
    });
  }

  String? _reminderLabel(AppLocalizations l, Duration? offset) {
    if (offset == null) return null;
    if (offset == const Duration(minutes: 5)) return l.captureReminder5mBefore;
    if (offset == const Duration(minutes: 15)) {
      return l.captureReminder15mBefore;
    }
    if (offset == const Duration(hours: 1)) return l.captureReminder1hBefore;
    if (offset == const Duration(days: 1)) return l.captureReminder1dBefore;
    return null;
  }

  Future<bool> _openCaptureComposer(String? draft) async {
    final text = draft?.trim() ?? '';
    final parsed = text.isEmpty
        ? emptyCaptureDraft
        : parseCapture(text, widget.now);
    return showA2Composer(
      context,
      contextDate: _scheduleContextDate(),
      initialTitle: text.isEmpty ? null : text,
      initialStart: parsed.start,
      initialEnd: parsed.end,
    );
  }

  void _enterParsedCapture(String text) {
    final parsed = parseCapture(text, widget.now);
    if (parsed.start == null) {
      setState(() => _desktopCaptureState = A2CaptureState.expanded);
      return;
    }
    setState(() {
      _suggestedPlanStart = parsed.start;
      _suggestedPlanEnd = parsed.end;
      _suggestionRemoved = false;
      _desktopCaptureDraft = _desktopCaptureDraft.withPlan(
        parsed.start,
        parsed.end,
      );
      _desktopCaptureState = A2CaptureState.parsed;
    });
  }

  void _toggleSuggestion() {
    setState(() {
      if (_suggestionRemoved) {
        _desktopCaptureDraft = _desktopCaptureDraft.withPlan(
          _suggestedPlanStart,
          _suggestedPlanEnd,
        );
        _suggestionRemoved = false;
      } else {
        _desktopCaptureDraft = _desktopCaptureDraft.withPlan(null, null);
        _suggestionRemoved = true;
      }
    });
  }

  /// While browsing a day the bar promises `计划到 <day>`, so a capture that
  /// has no plan of its own lands on that day instead of becoming unplanned.
  A2CaptureDraft _withBrowsedDay(
    A2CaptureDraft draft,
    TodosView view,
    DateTime viewed,
  ) {
    if (draft.planStart != null || view is! TodosDayView) return draft;
    final day = _dayOf(viewed);
    final start = DateTime(day.year, day.month, day.day, 15, 15);
    return draft.withPlan(
      start,
      start.add(const Duration(minutes: 45)),
    );
  }

  DateTime _defaultEventStart() {
    final view = ref.read(todosViewProvider);
    if (view is TodosDayView) {
      final day = _dayOf(ref.read(viewedDateProvider));
      return DateTime(day.year, day.month, day.day, 10);
    }
    return DateTime(
      widget.now.year,
      widget.now.month,
      widget.now.day,
      widget.now.hour + 1,
    );
  }

  void _enterEventCapture() {
    setState(() {
      final start = _desktopCaptureDraft.planStart ?? _defaultEventStart();
      final end = _desktopCaptureDraft.planEnd != null &&
              _desktopCaptureDraft.planEnd!.isAfter(start)
          ? _desktopCaptureDraft.planEnd!
          : start.add(const Duration(hours: 1));
      _desktopCaptureDraft = _desktopCaptureDraft.withPlan(start, end);
      _desktopCaptureState = A2CaptureState.event;
    });
  }

  void _backToTodoCapture() {
    setState(() {
      final text = _desktopCaptureController.text.trim();
      final parsed = text.isEmpty ? null : parseCapture(text, widget.now);
      _desktopCaptureState = parsed?.start != null
          ? A2CaptureState.parsed
          : A2CaptureState.expanded;
    });
  }

  void _cycleEventRepeat() {
    const repeats = <String?>[
      null,
      'FREQ=DAILY',
      'FREQ=WEEKLY',
      'FREQ=MONTHLY',
    ];
    final current = _desktopCaptureDraft.rrule;
    final index = repeats.indexOf(current);
    final next = repeats[(index < 0 ? 0 : index + 1) % repeats.length];
    setState(() {
      _desktopCaptureDraft = _desktopCaptureDraft.withRrule(next);
    });
  }

  String _eventRangeLabel(DateTime start, DateTime end) {
    String clock(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return '${start.month}/${start.day} ${clock(start)}–${clock(end)}';
  }

  String? _suggestionLabel() {
    final start = _desktopCaptureDraft.planStart;
    final end = _desktopCaptureDraft.planEnd;
    if (start == null || end == null) return null;
    return AppLocalizations.of(
      context,
    )!.captureSuggestionTitle(_eventRangeLabel(start, end));
  }

  Future<bool> _submitEventCapture(String text) async {
    final l = AppLocalizations.of(context)!;
    final start = _desktopCaptureDraft.planStart ?? _defaultEventStart();
    final rawEnd = _desktopCaptureDraft.planEnd;
    final end = rawEnd != null && rawEnd.isAfter(start)
        ? rawEnd
        : start.add(const Duration(hours: 1));
    final parsed = parseCapture(text, widget.now);
    final title = parsed.title.isEmpty ? text : parsed.title;
    final saved = await submitEventCapture(
      ref,
      context,
      title: title,
      start: start,
      end: end,
      calendarId: _desktopCaptureDraft.calendarId,
      rrule: _desktopCaptureDraft.rrule,
      reminderOffset: _desktopCaptureDraft.reminderOffset,
    );
    if (!mounted) return saved;
    if (saved) {
      showSpecToast(context, l.captureEventCreatedToast(_eventRangeLabel(start, end)));
    }
    return saved;
  }

  void _selectMode(TodosView view) {
    ref.read(todosInboxNoDateOnlyProvider.notifier).state = false;
    if (view is TodosInboxView && widget.onOpenUnplanned != null) {
      widget.onOpenUnplanned!();
      return;
    }
    ref.read(todosViewProvider.notifier).state = view;
  }

  void _openInboxNoDate() {
    ref.read(todosInboxNoDateOnlyProvider.notifier).state = true;
    ref.read(todosViewProvider.notifier).state = const TodosInboxView();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final view = ref.watch(todosViewProvider);
    final viewed = ref.watch(viewedDateProvider);
    final desktop = isWorkspaceLayout(context);
    if (!desktop &&
        (_desktopCaptureState != A2CaptureState.compact ||
            !_desktopCaptureDraft.isEmpty) &&
        !_resetCaptureScheduled) {
      _resetCaptureScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resetCaptureScheduled = false;
        if (!mounted || isWorkspaceLayout(context)) return;
        setState(() {
          _captureChoiceBaseline = null;
          _planDraftStart = null;
          _planDraftEnd = null;
          _desktopCaptureDraft = const A2CaptureDraft();
          _desktopCaptureState = A2CaptureState.compact;
        });
      });
    }
    final unplannedAsync = ref.watch(unplannedTodosProvider);
    final allAsync = ref.watch(allTodosProvider);
    final allocationsAsync = ref.watch(allActiveTaskAllocationsProvider);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    _calendarMap = {for (final c in calendars) c.id: c};
    final captureDefaultCalendar = calendars.isEmpty
        ? null
        : calendars.firstWhere(
            (calendar) => calendar.id == ref.watch(defaultCalendarIdProvider),
            orElse: () => calendars.first,
          );
    Calendar? captureCalendar;
    for (final calendar in calendars) {
      if (calendar.id == _desktopCaptureDraft.calendarId) {
        captureCalendar = calendar;
      }
    }
    captureCalendar ??= captureDefaultCalendar;
    final captureIsEvent = _desktopCaptureState == A2CaptureState.event;
    final captureStart = _desktopCaptureDraft.planStart;
    final captureEnd = _desktopCaptureDraft.planEnd;
    final captureCalendarName = captureCalendar?.name;
    final eventContextLabel = captureIsEvent && captureStart != null
        ? '${_eventRangeLabel(captureStart, captureEnd ?? captureStart.add(const Duration(hours: 1)))}'
              '${captureCalendarName == null ? '' : ' · $captureCalendarName'}'
        : null;
    final dateContextLabel = !captureIsEvent && view is TodosDayView
        ? '${l.capturePlanTo('${viewed.month}/${viewed.day}')}'
              '${captureCalendarName == null ? '' : ' · $captureCalendarName'}'
        : null;
    final captureContextLabel = eventContextLabel ?? dateContextLabel;
    var planDayBlocks = const <A2CaptureDayBlock>[];
    final planDayStart = _desktopCaptureState == A2CaptureState.plan
        ? _planDraftStart
        : null;
    if (planDayStart != null) {
      final dayStart = DateTime(
        planDayStart.year,
        planDayStart.month,
        planDayStart.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final rangeKey =
          '${dayStart.millisecondsSinceEpoch}-${dayEnd.millisecondsSinceEpoch}';
      final dayEvents =
          ref.watch(eventCandidatesInDateRangeProvider(rangeKey)).valueOrNull ??
          const [];
      final dayAllocations =
          ref
              .watch(taskAllocationsInDateRangeProvider(rangeKey))
              .valueOrNull ??
          const <TaskAllocationCalendarItem>[];
      planDayBlocks = <A2CaptureDayBlock>[
        for (final event in dayEvents)
          if (!event.isAllDay)
            A2CaptureDayBlock(
              start: event.startDt.toLocal(),
              end: event.endDt.toLocal(),
              title: event.summary,
            ),
        for (final item in dayAllocations)
          A2CaptureDayBlock(
            start: item.allocation.startAt.toLocal(),
            end: item.allocation.endAt.toLocal(),
            title: item.todo.summary,
          ),
      ]..sort((a, b) => a.start.compareTo(b.start));
    }
    final hideCompleted = ref.watch(hideCompletedProvider).valueOrNull ?? false;
    final tagMap =
        ref.watch(todoTagIdsMapProvider).valueOrNull ?? const <int, Set<int>>{};
    final projection = ref.watch(actionProjectionProvider).valueOrNull;
    final missedCounts = <int, int>{};
    if (projection != null) {
      for (final inst in projection.missedTaskInstances) {
        missedCounts[inst.todo.id] = (missedCounts[inst.todo.id] ?? 0) + 1;
      }
      for (final todo in projection.earlierMissedSeries) {
        missedCounts[todo.id] = (missedCounts[todo.id] ?? 0) + 1;
      }
    }
    _currentMissedCounts = missedCounts;

    final calendarFilter = ref.watch(todoCalendarFilterProvider);
    final tagFilter = ref.watch(todoTagFilterProvider);
    final priorityFilter = ref.watch(todoPriorityFilterProvider);
    final overdueFilter = ref.watch(todoOverdueFilterProvider);
    final filtered = _hasFilter;
    final noDateOnly =
        view is TodosInboxView && ref.watch(todosInboxNoDateOnlyProvider);

    // The filter sheet lives in this header, so every list behind it answers
    // to it: a control that changes nothing is worse than no control.
    bool visible(Todo todo) {
      if (hideCompleted && todo.status == 'COMPLETED') return false;
      if (overdueFilter) {
        final due = todo.dueDate?.toLocal();
        final isOverdue = due != null && isOverdueByDate(due, widget.now);
        final isMissed = (missedCounts[todo.id] ?? 0) > 0;
        if (!isOverdue && !isMissed) return false;
      }
      if (calendarFilter != null && todo.calendarId != calendarFilter) {
        return false;
      }
      if (priorityFilter != null && todo.priority != priorityFilter) {
        return false;
      }
      if (tagFilter.isNotEmpty) {
        final ids = tagMap[todo.id];
        if (ids == null || !tagFilter.any(ids.contains)) return false;
      }
      return true;
    }

    final names = <int, String>{
      for (final calendar in calendars) calendar.id: calendar.name,
    };
    final unplanned = <Todo>[
      for (final todo in unplannedAsync.valueOrNull ?? const <Todo>[])
        if (visible(todo)) todo,
    ];
    final allRows = <Todo>[
      for (final todo in allAsync.valueOrNull ?? const <Todo>[])
        if (todo.status != 'CANCELLED' && visible(todo)) todo,
    ];
    final inboxRows = <Todo>[
      for (final todo in unplanned)
        if (!noDateOnly || todo.dueDate == null) todo,
    ];
    final allocations =
        allocationsAsync.valueOrNull ?? const <TaskAllocationCalendarItem>[];
    final selection = ref.watch(workspaceSelectionProvider);

    final head = _head(l, view, inboxRows, allRows, desktop, noDateOnly);
    // By date needs one entry that reaches any month in two taps. The desktop
    // bar outside this page prints a date but cannot open a picker, so the
    // strip is the only honest entry on both platforms.
    final strip = view is TodosDayView
        ? _dateStrip(l, viewed, desktop: desktop)
        : null;
    final footer = _footer(
      l,
      view,
      viewed,
      contextLabel: captureContextLabel,
      isEvent: captureIsEvent,
    );

    final Widget body;
    if (view is TodosInboxView && unplannedAsync.hasError) {
      body = _loadError(l, () {
        ref.invalidate(pendingTodosProvider);
        ref.invalidate(allActiveTaskAllocationsProvider);
      });
    } else if (view is TodosAllView &&
        (allAsync.hasError || allocationsAsync.hasError)) {
      body = _loadError(l, () {
        ref.invalidate(allTodosProvider);
        ref.invalidate(allActiveTaskAllocationsProvider);
      });
    } else if (view is TodosInboxView) {
      body = _inboxBody(
        l,
        inboxRows,
        names,
        selection,
        desktop,
        unplannedAsync.isLoading && !unplannedAsync.hasValue,
        filtered,
        noDateOnly,
      );
    } else if (view is TodosAllView) {
      body = _allBody(
        l,
        allRows,
        allocations,
        names,
        selection,
        desktop,
        allAsync.isLoading && !allAsync.hasValue,
        filtered,
      );
    } else {
      final noDateTodos = <Todo>[
        for (final todo in unplanned)
          if (todo.dueDate == null) todo,
      ];
      final dayFailed = widget.dayAgendaFailed || unplannedAsync.hasError;
      body = dayFailed
          ? _loadError(l, () {
              widget.onRetryDayAgenda?.call();
              ref.invalidate(unplannedTodosProvider);
              ref.invalidate(allTodosProvider);
              ref.invalidate(allActiveTaskAllocationsProvider);
            })
          : _dayBody(
              l,
              names,
              selection,
              desktop,
              visible,
              noDateTodos,
              filtered,
              widget.dayAgendaLoading ||
                  (unplannedAsync.isLoading && !unplannedAsync.hasValue),
            );
    }

    if (desktop) {
      final detail = widget.detail;
      final showDrawer = canShowDesktopDrawer(context) && detail != null;
      return Material(
        color: SpecTokens.paper,
        child: Stack(
          children: [
            Positioned.fill(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        head,
                        if (strip != null) strip,
                        Expanded(child: body),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18,
                    child: footer,
                  ),
                  if (_desktopCaptureState != A2CaptureState.compact)
                    Positioned(
                      bottom: 78,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: A2CapturePanel(
                            state: _desktopCaptureState,
                            titleController: _desktopCaptureController,
                            onStateChanged: (s) => setState(() => _desktopCaptureState = s),
                            onCancel: () => setState(() {
                              _captureChoiceBaseline = null;
                              _planDraftStart = null;
                              _planDraftEnd = null;
                              _desktopCaptureDraft = const A2CaptureDraft();
                              _desktopCaptureState = A2CaptureState.compact;
                            }),
                            onDiscard: () {
                              _desktopCaptureController.clear();
                              setState(() {
                                _captureChoiceBaseline = null;
                                _planDraftStart = null;
                                _planDraftEnd = null;
                                _desktopCaptureDraft = const A2CaptureDraft();
                                _desktopCaptureState = A2CaptureState.compact;
                              });
                            },
                            dueDate: _desktopCaptureDraft.dueDate,
                            planStart:
                                _desktopCaptureState == A2CaptureState.plan
                                ? _planDraftStart
                                : _desktopCaptureDraft.planStart,
                            planEnd:
                                _desktopCaptureState == A2CaptureState.plan
                                ? _planDraftEnd
                                : _desktopCaptureDraft.planEnd,
                            calendarName: captureCalendar?.name,
                            calendarColor: captureCalendar == null
                                ? null
                                : ColorUtils.parseHex(captureCalendar.color),
                            reminderLabel:
                                _desktopCaptureDraft.dueDate == null &&
                                    _desktopCaptureDraft.planStart == null
                                ? null
                                : _reminderLabel(
                                    l,
                                    _desktopCaptureDraft.reminderOffset,
                                  ),
                            isEvent: captureIsEvent,
                            suggestionRemoved: _suggestionRemoved,
                            suggestionLabel: _suggestionLabel(),
                            onToggleSuggestion: _toggleSuggestion,
                            planDayBlocks: planDayBlocks,
                            calendarChoices: [
                              for (final calendar in calendars)
                                A2CaptureCalendarChoice(
                                  id: calendar.id,
                                  name: calendar.name,
                                  color: ColorUtils.parseHex(calendar.color),
                                ),
                            ],
                            selectedCalendarId:
                                _desktopCaptureDraft.calendarId ??
                                captureDefaultCalendar?.id,
                            selectedReminderOffset:
                                _desktopCaptureDraft.reminderOffset,
                            onChooseDueDate: (date) => setState(() {
                              if (date != null) {
                                _desktopCaptureDraft =
                                    _desktopCaptureDraft.withDueDate(date);
                              }
                            }),
                            onChooseCalendar: (id) => setState(() {
                              if (id != null) {
                                _desktopCaptureDraft =
                                    _desktopCaptureDraft.withCalendarId(id);
                              }
                            }),
                            onChooseReminder: _chooseCaptureReminder,
                            onPickDate: () =>
                                _openCaptureChoice(A2CaptureState.date),
                            onPickCustomDate: _pickCaptureDueDate,
                            onPickPlan: _openPlanCapture,
                            onPickPlanDate: _pickCapturePlanDate,
                            onPickPlanStart: _pickCapturePlanStart,
                            onPickPlanEnd: _pickCapturePlanEnd,
                            onPickCalendar: () =>
                                _openCaptureChoice(A2CaptureState.calendar),
                            onPickReminder: () =>
                                _openCaptureChoice(A2CaptureState.reminder),
                            onApplyChoice: _applyCaptureChoice,
                            onCancelChoice: _cancelCaptureChoice,
                            onSwitchToEvent: _enterEventCapture,
                            onSwitchToTodo: _backToTodoCapture,
                            onCycleEventRepeat: _cycleEventRepeat,
                            eventRepeat: _desktopCaptureDraft.rrule,
                            onSubmit: () async {
                              final text = _desktopCaptureController.text.trim();
                              if (text.isEmpty) {
                                setState(() => _desktopCaptureState = A2CaptureState.validation);
                                return;
                              }
                              try {
                                final bool saved;
                                if (_desktopCaptureState == A2CaptureState.event) {
                                  saved = await _submitEventCapture(text);
                                } else {
                                  final parsed =
                                      _desktopCaptureState == A2CaptureState.parsed;
                                  final base = parsed
                                      ? (_suggestionRemoved
                                            ? _desktopCaptureDraft.withPlan(
                                                null,
                                                null,
                                              )
                                            : _desktopCaptureDraft)
                                      : _desktopCaptureDraft;
                                  final draft = parsed && _suggestionRemoved
                                      ? base
                                      : _withBrowsedDay(base, view, viewed);
                                  saved = await _capture(
                                    parsed
                                        ? parseCapture(text, widget.now).title
                                        : text,
                                    draft: draft,
                                  );
                                }
                                if (saved) {
                                  _desktopCaptureController.clear();
                                  setState(() {
                                    _captureChoiceBaseline = null;
                                    _planDraftStart = null;
                                    _planDraftEnd = null;
                                    _suggestedPlanStart = null;
                                    _suggestedPlanEnd = null;
                                    _suggestionRemoved = false;
                                    _desktopCaptureDraft =
                                        const A2CaptureDraft();
                                    _desktopCaptureState =
                                        A2CaptureState.compact;
                                  });
                                } else {
                                  setState(() => _desktopCaptureState = A2CaptureState.saveError);
                                }
                              } catch (_) {
                                setState(() => _desktopCaptureState = A2CaptureState.saveError);
                              }
                            },
                            onSubmitLater: () async {
                              final text = _desktopCaptureController.text.trim();
                              if (text.isEmpty) {
                                setState(() => _desktopCaptureState = A2CaptureState.validation);
                                return;
                              }
                              try {
                                final saved = await _capture(text);
                                if (saved) {
                                  _desktopCaptureController.clear();
                                  setState(() {
                                    _desktopCaptureDraft =
                                        const A2CaptureDraft();
                                    _desktopCaptureState =
                                        A2CaptureState.compact;
                                  });
                                } else {
                                  setState(() => _desktopCaptureState = A2CaptureState.saveError);
                                }
                              } catch (_) {
                                setState(() => _desktopCaptureState = A2CaptureState.saveError);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showDrawer)
              SpecDrawerOverlay(
                child: detail,
              ),
          ],
        ),
      );
    }

    return Material(
      color: ds.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _mobileTopBar(context, l, view),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _modeSwitch(l, view),
            ),
          ),
          if (strip != null) strip,
          Expanded(child: body),
          footer,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ header

  Widget _mobileTopBar(
    BuildContext context,
    AppLocalizations l,
    TodosView view,
  ) {
    final String title;
    if (view is TodosInboxView) {
      title = l.inbox;
    } else if (view is TodosAllView) {
      title = l.allTasks;
    } else {
      final viewed = ref.watch(viewedDateProvider);
      final day = _dayOf(viewed);
      final dateText = DateFormat.MMMd(_locale).format(day);
      final weekText = DateFormat.E(_locale).format(day);
      title = '$dateText \u00b7 $weekText';
    }

    return Container(
      key: const ValueKey('m-top'),
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontVariations: [FontVariation('wght', 650)],
                letterSpacing: 0.15,
                color: SpecTokens.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mIcon(
                key: const ValueKey('todos-search-tool'),
                icon: CupertinoIcons.search,
                tooltip: l.search,
                onTap: () {
                  try {
                    context.push('/search');
                  } catch (_) {}
                },
              ),
              const SizedBox(width: 5),
              _mIcon(
                key: const ValueKey('todos-filter-tool'),
                icon: CupertinoIcons.slider_horizontal_3,
                size: 14,
                tooltip: l.filter,
                onTap: () => _showFilterSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mIcon({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 15,
  }) {
    return Tooltip(
      message: tooltip,
      child: FocusableTap(
        key: key,
        onTap: onTap,
        semanticsLabel: tooltip,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: SpecTokens.muted,
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasFilter =>
      ref.watch(todoCalendarFilterProvider) != null ||
      ref.watch(todoTagFilterProvider).isNotEmpty ||
      ref.watch(todoPriorityFilterProvider) != null ||
      ref.watch(todoOverdueFilterProvider);

  Widget _head(
    AppLocalizations l,
    TodosView view,
    List<Todo> unplanned,
    List<Todo> allRows,
    bool desktop,
    bool noDateOnly,
  ) {
    final ds = context.ds;
    final withDue = unplanned.where((todo) => todo.dueDate != null).length;
    final active = allRows.where((todo) => todo.status != 'COMPLETED').length;
    final completed = allRows.where((todo) => todo.status == 'COMPLETED').length;
    final viewed = ref.watch(viewedDateProvider);
    final day = _dayOf(viewed);
    final today = _dayOf(widget.now);
    final delta = _daysBetween(day, today);

    final title = l.todos;
    final String subtitle;
    if (view is TodosInboxView) {
      subtitle = noDateOnly
          ? l.todoInboxNoDateContext(unplanned.length)
          : l.todoUnplannedContext(unplanned.length, withDue);
    } else if (view is TodosAllView) {
      subtitle = l.todoAllActiveSummary(active, completed);
    } else {
      final dateText = DateFormat.MMMd(_locale).format(day);
      final weekText = DateFormat.E(_locale).format(day);
      final relative = delta == 0
          ? ''
          : (delta > 0 ? l.inDaysCount(delta) : l.daysAgo(-delta));
      subtitle = relative.isEmpty
          ? '$dateText · $weekText'
          : '$dateText · $weekText · $relative';
    }

    final hasFilter = _hasFilter;

    return Container(
      padding: EdgeInsets.fromLTRB(
        desktop ? 28 : 16,
        desktop ? 20 : 14,
        desktop ? 28 : 16,
        13,
      ),
      decoration: BoxDecoration(
        color: desktop ? ds.surface : ds.bg,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.01 * 26,
                        height: 1.22,
                        color: ds.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ds.ink3,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _filterTool(l, hasFilter),
              ...widget.trailingActions,
            ],
          ),
          const SizedBox(height: 10),
          _modeSwitch(l, view),
        ],
      ),
    );
  }

  Widget _filterTool(AppLocalizations l, bool active) {
    return CompositedTransformTarget(
      link: _filterToolLink,
      child: Tooltip(
        message: l.filter,
        child: FocusableTap(
          key: const ValueKey('todos-filter-tool'),
          focusNode: _filterToolFocusNode,
          onTap: () => _showFilterSheet(context),
          semanticsLabel: l.filter,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                key: const ValueKey('todos-filter-tool-visual'),
                height: 29,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: active ? SpecTokens.wash : Colors.white,
                  border: Border.all(
                    color: active ? SpecTokens.ink2 : SpecTokens.hair2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.slider_horizontal_3,
                      size: 12,
                      color: SpecTokens.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      l.filter,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? SpecTokens.ink : SpecTokens.ink2,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFilterSheet(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final calendars =
        ref.read(calendarsProvider).valueOrNull ?? const <Calendar>[];
    final tags = ref.read(tagsProvider).valueOrNull ?? const <Tag>[];
    final allTodos = ref.read(allTodosProvider).valueOrNull ?? const <Todo>[];
    final tagMap =
        ref.read(todoTagIdsMapProvider).valueOrNull ?? const <int, Set<int>>{};

    var draftCalendar = ref.read(todoCalendarFilterProvider);
    var draftTags = ref.read(todoTagFilterProvider);
    var draftPriority = ref.read(todoPriorityFilterProvider);
    var draftOverdue = ref.read(todoOverdueFilterProvider);

    void applyDraft() {
      ref.read(todoCalendarFilterProvider.notifier).state = draftCalendar;
      ref.read(todoTagFilterProvider.notifier).state = draftTags;
      ref.read(todoPriorityFilterProvider.notifier).state = draftPriority;
      ref.read(todoOverdueFilterProvider.notifier).state = draftOverdue;
    }

    void clearDraft() {
      draftCalendar = null;
      draftTags = const <int>{};
      draftPriority = null;
      draftOverdue = false;
    }

    int computeMatchCount(int? cal, Set<int> tgs, int? prio, bool overdue) {
      return allTodos.where((t) {
        if (overdue) {
          final due = t.dueDate?.toLocal();
          final isOverdue = due != null && isOverdueByDate(due, widget.now);
          final isMissed = (_currentMissedCounts[t.id] ?? 0) > 0;
          if (!isOverdue && !isMissed) return false;
        }
        if (cal != null && t.calendarId != cal) return false;
        if (prio != null && t.priority != prio) return false;
        if (tgs.isNotEmpty) {
          final ids = tagMap[t.id];
          if (ids == null || !tgs.any(ids.contains)) return false;
        }
        return true;
      }).length;
    }

    if (isWorkspaceLayout(context)) {
      _closeFilterOverlay(restoreFocus: false);
      final entry = OverlayEntry(
        builder: (overlayContext) {
          return StatefulBuilder(
            builder: (ctx, setPopState) {
              final matched = computeMatchCount(draftCalendar, draftTags, draftPriority, draftOverdue);
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _closeFilterOverlay(),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CompositedTransformFollower(
                      link: _filterToolLink,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.bottomRight,
                      followerAnchor: Alignment.topRight,
                      offset: const Offset(0, 6),
                      child: FocusScope(
                        node: _filterScopeNode,
                        autofocus: true,
                        child: Focus(
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.escape) {
                              _closeFilterOverlay();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: SizedBox(
                            width: 260,
                            child: Material(
                      color: Colors.white,
                      elevation: 16,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                        side: const BorderSide(color: SpecTokens.hair2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l.filter,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: SpecTokens.ink,
                                    fontFamilyFallback: AppTypography.fallback,
                                  ),
                                ),
                                FocusableTap(
                                  focusNode: _filterInitialFocusNode,
                                  onTap: () => _closeFilterOverlay(),
                                  semanticsLabel: l.close,
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Icon(CupertinoIcons.xmark, size: 12, color: SpecTokens.muted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              l.filterMatchedCount(matched),
                              style: const TextStyle(
                                fontSize: 9,
                                color: SpecTokens.faint,
                                fontFamilyFallback: AppTypography.fallback,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Divider(height: 1, color: SpecTokens.hair),
                            const SizedBox(height: 8),
                            Text(
                              l.calendar,
                              style: const TextStyle(
                                fontSize: 9,
                                letterSpacing: 0.9,
                                fontWeight: FontWeight.w600,
                                color: SpecTokens.faint,
                                fontFamilyFallback: AppTypography.fallback,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final c in calendars)
                                  FocusableTap(
                                    onTap: () => setPopState(() {
                                      draftCalendar = draftCalendar == c.id ? null : c.id;
                                    }),
                                    semanticsLabel: c.name,
                                    selected: draftCalendar == c.id,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: draftCalendar == c.id ? SpecTokens.ink : Colors.white,
                                          border: Border.all(color: draftCalendar == c.id ? SpecTokens.ink : SpecTokens.hair2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: ColorUtils.parseHex(c.color),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              c.name,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: draftCalendar == c.id ? Colors.white : SpecTokens.ink2,
                                                fontFamilyFallback: AppTypography.fallback,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Divider(height: 1, color: SpecTokens.hair),
                              const SizedBox(height: 8),
                              Text(
                                l.tags,
                                style: const TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 0.9,
                                  fontWeight: FontWeight.w600,
                                  color: SpecTokens.faint,
                                  fontFamilyFallback: AppTypography.fallback,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final t in tags)
                                    FocusableTap(
                                      onTap: () => setPopState(() {
                                        final next = {...draftTags};
                                        if (!next.remove(t.id)) next.add(t.id);
                                        draftTags = next;
                                      }),
                                      semanticsLabel: t.name,
                                      selected: draftTags.contains(t.id),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: draftTags.contains(t.id) ? SpecTokens.ink : Colors.white,
                                          border: Border.all(color: draftTags.contains(t.id) ? SpecTokens.ink : SpecTokens.hair2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          t.name,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: draftTags.contains(t.id) ? Colors.white : SpecTokens.ink2,
                                            fontFamilyFallback: AppTypography.fallback,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: SpecTokens.hair),
                            const SizedBox(height: 8),
                            Text(
                              l.priority,
                              style: const TextStyle(
                                fontSize: 9,
                                letterSpacing: 0.9,
                                fontWeight: FontWeight.w600,
                                color: SpecTokens.faint,
                                fontFamilyFallback: AppTypography.fallback,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final p in [
                                  (null, l.priorityNone),
                                  (1, l.priorityHigh),
                                  (5, l.priorityMedium),
                                  (9, l.priorityLow),
                                ])
                                  FocusableTap(
                                    onTap: () => setPopState(() => draftPriority = p.$1),
                                    semanticsLabel: p.$2,
                                    selected: draftPriority == p.$1,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: draftPriority == p.$1 ? SpecTokens.ink : Colors.white,
                                        border: Border.all(color: draftPriority == p.$1 ? SpecTokens.ink : SpecTokens.hair2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        p.$2,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: draftPriority == p.$1 ? Colors.white : SpecTokens.ink2,
                                          fontFamilyFallback: AppTypography.fallback,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: SpecTokens.hair),
                            const SizedBox(height: 8),
                            FocusableTap(
                              onTap: () => setPopState(() => draftOverdue = !draftOverdue),
                              semanticsLabel: l.filterOverdueOnly,
                              borderRadius: BorderRadius.circular(4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: draftOverdue ? SpecTokens.ink : Colors.white,
                                      border: Border.all(color: draftOverdue ? SpecTokens.ink : const Color(0xFFCFCFC7)),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: draftOverdue
                                        ? const Center(child: Icon(CupertinoIcons.check_mark, size: 8, color: Colors.white))
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    l.filterOverdueOnly,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: SpecTokens.ink2,
                                      fontFamilyFallback: AppTypography.fallback,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: SpecTokens.hair),
                            const SizedBox(height: 8),
                            Consumer(
                              builder: (ctx, r, _) {
                                final hideCompleted =
                                    r.watch(hideCompletedProvider).valueOrNull ?? false;
                                return Row(
                                  children: [
                                    Text(
                                      l.hideCompleted,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: SpecTokens.ink2,
                                        fontFamilyFallback: AppTypography.fallback,
                                      ),
                                    ),
                                    const Spacer(),
                                    Switch(
                                      value: hideCompleted,
                                      onChanged: (value) =>
                                          r.read(setHideCompletedProvider)(value),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    clearDraft();
                                    applyDraft();
                                    _closeFilterOverlay();
                                  },
                                  child: Text(
                                    l.filterReset,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: SpecTokens.ink2,
                                      fontFamilyFallback: AppTypography.fallback,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    applyDraft();
                                    _closeFilterOverlay();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: SpecTokens.ink,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  ),
                                  child: Text(
                                    l.filterApply,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontFamilyFallback: AppTypography.fallback,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  _filterOverlay = entry;
  Overlay.of(context).insert(entry);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _filterOverlay == entry) {
      _filterInitialFocusNode.requestFocus();
    }
  });
  return Future<void>.value();
}

    return showDsSheet<void>(
      context: context,
      title: l.filter,
      actions: [
        Expanded(
          child: DsButton(
            label: l.filterReset,
            tone: DsButtonTone.secondary,
            expand: true,
            onPressed: () {
              clearDraft();
              applyDraft();
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DsButton(
            label: l.filterApply,
            expand: true,
            onPressed: () {
              applyDraft();
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
        ),
      ],
      body: Consumer(
        builder: (ctx, r, _) {
          final hideCompleted =
              r.watch(hideCompletedProvider).valueOrNull ?? false;
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final matched = computeMatchCount(draftCalendar, draftTags, draftPriority, draftOverdue);
              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.filterMatchedCount(matched),
                      style: const TextStyle(
                        fontSize: 9,
                        color: SpecTokens.faint,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DsGroupLabel(l.calendar),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final calendar in calendars)
                          DsChip(
                            label: calendar.name,
                            selected: draftCalendar == calendar.id,
                            leading: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: ColorUtils.parseHex(calendar.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            onTap: () => setSheetState(() {
                              draftCalendar = draftCalendar == calendar.id
                                  ? null
                                  : calendar.id;
                            }),
                          ),
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DsGroupLabel(l.tags),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in tags)
                            DsChip(
                              label: tag.name,
                              selected: draftTags.contains(tag.id),
                              leading: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: ColorUtils.parseHex(tag.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              onTap: () => setSheetState(() {
                                final next = {...draftTags};
                                if (!next.remove(tag.id)) next.add(tag.id);
                                draftTags = next;
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    DsGroupLabel(l.priority),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DsChip(
                          label: l.priorityNone,
                          selected: draftPriority == null,
                          onTap: () =>
                              setSheetState(() => draftPriority = null),
                        ),
                        for (final entry in [
                          (1, l.priorityHigh),
                          (5, l.priorityMedium),
                          (9, l.priorityLow),
                        ])
                          DsChip(
                            label: entry.$2,
                            selected: draftPriority == entry.$1,
                            onTap: () => setSheetState(() {
                              draftPriority = draftPriority == entry.$1
                                  ? null
                                  : entry.$1;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FocusableTap(
                      onTap: () => setSheetState(() => draftOverdue = !draftOverdue),
                      semanticsLabel: l.filterOverdueOnly,
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: draftOverdue ? SpecTokens.ink : Colors.white,
                              border: Border.all(color: draftOverdue ? SpecTokens.ink : const Color(0xFFCFCFC7)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: draftOverdue
                                ? const Center(child: Icon(CupertinoIcons.check_mark, size: 9, color: Colors.white))
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.filterOverdueOnly,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SpecTokens.ink,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: SpecTokens.hair, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.hideCompleted,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: SpecTokens.ink,
                                    fontFamilyFallback: AppTypography.fallback,
                                  ),
                                ),
                                Text(
                                  l.hideCompletedDesc,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: SpecTokens.faint,
                                    fontFamilyFallback: AppTypography.fallback,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: hideCompleted,
                            onChanged: (value) =>
                                r.read(setHideCompletedProvider)(value),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _modeSwitch(AppLocalizations l, TodosView view) {
    final isInbox = view is TodosInboxView;
    final isAll = view is TodosAllView;
    final isDate = view is TodosDayView;

    Widget visual(String label, bool active, Key key) => ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48),
      child: Center(child: _modeButtonVisual(label, active, key: key)),
    );

    return SizedBox(
      key: const ValueKey('todos-mode-switch'),
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Container(
                key: const ValueKey('todos-mode-switch-visual'),
                height: 33,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: SpecTokens.wash,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    visual(
                      l.inbox,
                      isInbox,
                      const ValueKey('todo-mode-visual-inbox'),
                    ),
                    const SizedBox(width: 2),
                    visual(
                      l.allLabel,
                      isAll,
                      const ValueKey('todo-mode-visual-all'),
                    ),
                    const SizedBox(width: 2),
                    visual(
                      l.byDateTitle,
                      isDate,
                      const ValueKey('todo-mode-visual-date'),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeButton(
                  key: const ValueKey('todo-mode-inbox'),
                  label: l.inbox,
                  active: isInbox,
                  onTap: () => _selectMode(const TodosInboxView()),
                ),
                const SizedBox(width: 2),
                _modeButton(
                  key: const ValueKey('todo-mode-all'),
                  label: l.allLabel,
                  active: isAll,
                  onTap: () => _selectMode(const TodosAllView()),
                ),
                const SizedBox(width: 2),
                _modeButton(
                  key: const ValueKey('todo-mode-date'),
                  label: l.byDateTitle,
                  active: isDate,
                  onTap: () => _selectMode(const TodosDayView()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButtonVisual(String label, bool active, {Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 140),
      height: 27,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: Color(0x0F191918),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? SpecTokens.ink : SpecTokens.muted,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
  }

  Widget _modeButton({
    required Key key,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return FocusableTap(
      key: key,
      onTap: onTap,
      semanticsLabel: label,
      selected: active,
      borderRadius: BorderRadius.circular(5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Center(
          child: ExcludeSemantics(
            child: Opacity(
              opacity: 0,
              child: _modeButtonVisual(label, active),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- date strip

  Widget _dateStrip(
    AppLocalizations l,
    DateTime viewed, {
    bool desktop = false,
  }) {
    final ds = context.ds;
    final day = _dayOf(viewed);
    final today = _dayOf(widget.now);
    final isToday = _sameDay(day, today);
    final monthText = DateFormat.yMMMM(_locale).format(day);
    final days = [-3, -2, -1, 0, 1, 2, 3]
        .map((offset) => day.add(Duration(days: offset)))
        .toList();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 28 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: desktop ? ds.surface : ds.bg,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          FocusableTap(
            key: const ValueKey('todos-date-strip'),
            onTap: () => showMonthYearPicker(context, initial: day),
            semanticsLabel: monthText,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Container(
                  key: const ValueKey('todos-date-strip-visual'),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: SpecTokens.hair2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        monthText,
                        style: TextStyle(
                          fontSize: desktop ? 10.5 : 10.0,
                          color: SpecTokens.ink2,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        CupertinoIcons.chevron_down,
                        size: 10,
                        color: SpecTokens.faint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('todos-date-strip-scroll'),
              scrollDirection: Axis.horizontal,
              child: _dateStripDays(
                days: days,
                day: day,
                today: today,
                desktop: desktop,
              ),
            ),
          ),
          if (!isToday) ...[
            const SizedBox(width: 6),
            _dateStripTodayButton(l, today),
          ],
        ],
      ),
    );
  }

  Widget _dateStripDays({
    required List<DateTime> days,
    required DateTime day,
    required DateTime today,
    required bool desktop,
  }) {
    final width = desktop ? 44.0 : 34.0;
    final height = desktop ? 48.0 : 44.0;
    const gap = 4.0;
    const hitSize = 48.0;
    final step = width + gap;
    final totalWidth = days.length * width + (days.length - 1) * gap;

    void selectAt(double x) {
      final index = ((x - width / 2) / step).round().clamp(
        0,
        days.length - 1,
      );
      ref.read(viewedDateProvider.notifier).state = days[index];
    }

    return SizedBox(
      key: const ValueKey('todos-date-strip-days'),
      width: totalWidth,
      height: hitSize,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapUp: (details) => selectAt(details.localPosition.dx),
          child: Stack(
            children: [
              for (var i = 0; i < days.length; i++)
                Positioned(
                  left: i * step,
                  top: (hitSize - height) / 2,
                  width: width,
                  height: height,
                  child: ExcludeSemantics(
                    child: _dateStripDayVisual(
                      key: ValueKey(
                        'todos-date-strip-day-visual-${_dateKey(days[i])}',
                      ),
                      d: days[i],
                      selected: _sameDay(days[i], day),
                      isToday: _sameDay(days[i], today),
                    ),
                  ),
                ),
              for (var i = 0; i < days.length; i++)
                Positioned(
                  left: (i * step - (hitSize - width) / 2).clamp(
                    0.0,
                    totalWidth - hitSize,
                  ),
                  top: 0,
                  width: hitSize,
                  height: hitSize,
                  child: FocusableTap(
                    key: ValueKey(
                      'todos-date-strip-day-${_dateKey(days[i])}',
                    ),
                    onTap: () =>
                        ref.read(viewedDateProvider.notifier).state = days[i],
                    semanticsLabel:
                        '${DateFormat.E(_locale).format(days[i])} '
                        '${days[i].day}',
                    selected: _sameDay(days[i], day),
                    borderRadius: BorderRadius.circular(7),
                    pointerEnabled: false,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateStripDayVisual({
    required Key key,
    required DateTime d,
    required bool selected,
    required bool isToday,
  }) {
    final weekdayRaw = DateFormat.E(_locale).format(d);
    final weekdayStr =
        weekdayRaw.length > 1 && !weekdayRaw.startsWith(RegExp(r'[A-Za-z]'))
            ? weekdayRaw.substring(weekdayRaw.length - 1)
            : weekdayRaw;
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: selected ? SpecTokens.ink : Colors.transparent,
        border: Border.all(
          color: selected ? SpecTokens.ink : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekdayStr,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.02 * 9,
              color: selected ? Colors.white : SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '${d.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: AppTypography.tabular,
              color: selected
                  ? Colors.white
                  : (isToday ? SpecTokens.red : SpecTokens.muted),
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Widget _dateStripTodayButton(AppLocalizations l, DateTime today) {
    return Tooltip(
      message: l.goToToday,
      child: FocusableTap(
        key: const ValueKey('todos-date-strip-today'),
        onTap: () => ref.read(viewedDateProvider.notifier).state = today,
        semanticsLabel: l.goToToday,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              key: const ValueKey('todos-date-strip-today-visual'),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: SpecTokens.hair2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l.today,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ footer

  Widget _footer(
    AppLocalizations l,
    TodosView view,
    DateTime viewed, {
    String? contextLabel,
    bool isEvent = false,
  }) {
    // The spec floats one 560x54 capture pill over the page, bottom 18.
    final desktop = isWorkspaceLayout(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: A2CaptureBar(
            controller: _desktopCaptureController,
            placeholder: l.capturePlaceholder,
            contextLabel: contextLabel,
            isEvent: isEvent,
            hint: _captureFocused
                ? l.captureHintSubmit
                : (desktop ? l.captureHintEnter : ''),
            onSubmit: (text) async {
              if (text.trim().isEmpty) {
                if (desktop) {
                  setState(() => _desktopCaptureState = A2CaptureState.validation);
                }
                return;
              }
              if (!desktop) {
                await _capture(text, draft: const A2CaptureDraft());
                return;
              }
              if (_desktopCaptureState == A2CaptureState.event) {
                final saved = await _submitEventCapture(text);
                if (saved) {
                  _desktopCaptureController.clear();
                  setState(() {
                    _desktopCaptureDraft = const A2CaptureDraft();
                    _desktopCaptureState = A2CaptureState.compact;
                  });
                }
                return;
              }
              final draft = _withBrowsedDay(
                _desktopCaptureDraft,
                view,
                viewed,
              );
              final saved = await _capture(text, draft: draft);
              if (saved) {
                _desktopCaptureController.clear();
                setState(() {
                  _captureChoiceBaseline = null;
                  _planDraftStart = null;
                  _planDraftEnd = null;
                  _suggestedPlanStart = null;
                  _suggestedPlanEnd = null;
                  _suggestionRemoved = false;
                  _desktopCaptureDraft = const A2CaptureDraft();
                  _desktopCaptureState = A2CaptureState.compact;
                });
              } else {
                setState(() => _desktopCaptureState = A2CaptureState.saveError);
              }
            },
            onExpand: () {
              if (desktop) {
                if (_desktopCaptureState == A2CaptureState.compact) {
                  final text = _desktopCaptureController.text.trim();
                  if (text.isEmpty) {
                    setState(
                      () => _desktopCaptureState = A2CaptureState.expanded,
                    );
                  } else {
                    _enterParsedCapture(text);
                  }
                } else {
                  setState(() {
                    _captureChoiceBaseline = null;
                    _planDraftStart = null;
                    _planDraftEnd = null;
                    _suggestedPlanStart = null;
                    _suggestedPlanEnd = null;
                    _suggestionRemoved = false;
                    _desktopCaptureDraft = const A2CaptureDraft();
                    _desktopCaptureState = A2CaptureState.compact;
                  });
                }
              } else {
                _openCaptureComposer(_desktopCaptureController.text);
              }
            },
            onParsedSubmit: (draft) async {
              if (!desktop) {
                return _openCaptureComposer(draft);
              }
              if (_desktopCaptureState == A2CaptureState.event) {
                return _submitEventCapture(draft);
              }
              _enterParsedCapture(draft);
              return false;
            },
            onFocusChange: (focused) {
              if (_captureFocused == focused) return;
              setState(() => _captureFocused = focused);
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- lists

  Widget _loading() =>
      Center(child: CupertinoActivityIndicator(color: context.ds.ink3));

  Widget _loadError(AppLocalizations l, VoidCallback retry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.error),
        TextButton(onPressed: retry, child: Text(l.retry)),
      ],
    ),
  );

  Widget _groupHead({
    required String label,
    int? count,
    String? countLabel,
    bool danger = false,
    Color? tone,
    Widget? trailing,
    VoidCallback? onTap,
    bool topBorder = true,
  }) {
    final desktop = isWorkspaceLayout(context);
    return A2GroupHead(
      label: label,
      count: count,
      countLabel: countLabel,
      danger: danger,
      tone: tone,
      trailing: trailing,
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 4 : 20),
      topBorder: topBorder,
    );
  }

  void _clearFilters() {
    ref.read(todoCalendarFilterProvider.notifier).state = null;
    ref.read(todoTagFilterProvider.notifier).state = const <int>{};
    ref.read(todoPriorityFilterProvider.notifier).state = null;
    ref.read(todoOverdueFilterProvider.notifier).state = false;
  }

  Widget _bannerShell({
    required Key key,
    required Key actionKey,
    required String label,
    required String action,
    required VoidCallback onAction,
    required bool desktop,
  }) {
    return Container(
      key: key,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 28 : 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          FocusableTap(
            key: actionKey,
            onTap: onAction,
            semanticsLabel: action,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(
                child: Text(
                  action,
                  style: const TextStyle(
                    fontSize: 10,
                    color: SpecTokens.ink2,
                    decoration: TextDecoration.underline,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withBanners({
    required List<Widget> banners,
    required Widget child,
  }) {
    if (banners.isEmpty) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...banners, Expanded(child: child)],
    );
  }

  String _filterCriteria(AppLocalizations l) {
    final parts = <String>[];
    final calendarId = ref.watch(todoCalendarFilterProvider);
    if (calendarId != null) {
      final calendar = _calendarMap[calendarId];
      if (calendar != null) parts.add(calendar.name);
    }
    final tagIds = ref.watch(todoTagFilterProvider);
    if (tagIds.isNotEmpty) {
      final tags = ref.watch(tagsProvider).valueOrNull ?? const <Tag>[];
      for (final tag in tags) {
        if (tagIds.contains(tag.id)) parts.add(tag.name);
      }
    }
    final priority = ref.watch(todoPriorityFilterProvider);
    if (priority != null) {
      parts.add(switch (priority) {
        1 => l.priorityHigh,
        5 => l.priorityMedium,
        9 => l.priorityLow,
        _ => l.priorityNone,
      });
    }
    if (ref.watch(todoOverdueFilterProvider)) {
      parts.add(l.filterOverdueOnly);
    }
    return parts.join(l.listSeparator);
  }

  Widget _filterBanner(AppLocalizations l, int count, bool desktop) =>
      _bannerShell(
        key: const ValueKey('todos-filter-banner'),
        actionKey: const ValueKey('todos-filter-clear'),
        label: l.filterAppliedSummary(_filterCriteria(l), count),
        action: l.clearFilters,
        onAction: _clearFilters,
        desktop: desktop,
      );

  Widget _inboxNoDateBanner(AppLocalizations l, bool desktop) => _bannerShell(
    key: const ValueKey('todos-inbox-nodate-banner'),
    actionKey: const ValueKey('todos-inbox-view-all'),
    label: l.todoInboxNoDateBanner,
    action: l.todoInboxViewAll,
    onAction: () =>
        ref.read(todosInboxNoDateOnlyProvider.notifier).state = false,
    desktop: desktop,
  );

  Widget _inboxBody(
    AppLocalizations l,
    List<Todo> todos,
    Map<int, String> names,
    WorkspaceSelection? selection,
    bool desktop,
    bool loading,
    bool filtered,
    bool noDateOnly,
  ) {
    if (loading) return _loading();
    final open = widget.onOpenTodo;

    if (filtered) {
      final activeTodos = todos.where((t) => t.status != 'COMPLETED').toList();
      final banners = <Widget>[
        if (noDateOnly) _inboxNoDateBanner(l, desktop),
        _filterBanner(l, activeTodos.length, desktop),
      ];
      if (activeTodos.isEmpty) {
        final empty = A2Empty(title: l.filterEmptyTitle, hint: l.filterEmptyHint);
        return _withBanners(banners: banners, child: empty);
      }
      final list = ListView.builder(
        padding: EdgeInsets.fromLTRB(desktop ? 28 : 0, desktop ? 8 : 14, desktop ? 28 : 0, 118),
        itemCount: activeTodos.length,
        itemBuilder: (context, index) {
          final todo = activeTodos[index];
          return _todoRow(
            todo,
            meta: _inboxMeta(l, todo, names),
            desktop: desktop,
            selected: _isTodoSelected(selection, todo.id),
            checked: false,
            onTap: open == null ? null : () => open(todo),
            slot: _UndoSlot(_UndoGroup.inboxNoDue, index),
          );
        },
      );
      return _withBanners(banners: banners, child: list);
    }

    final withDue = <Todo>[
      for (final todo in todos)
        if (todo.dueDate != null) todo,
    ];
    final noDue = <Todo>[
      for (final todo in todos)
        if (todo.dueDate == null) todo,
    ];
    _pinInboxWindows(withDue, noDue);
    final banners = <Widget>[
      if (noDateOnly) _inboxNoDateBanner(l, desktop),
    ];
    if (withDue.isEmpty && noDue.isEmpty) {
      final empty = noDateOnly
          ? A2Empty(
              title: l.emptyInboxNoDateTitle,
              hint: l.emptyInboxNoDateHint,
            )
          : A2Empty(title: l.emptyUnplannedTitle, hint: l.emptyUnplannedHint);
      return _withBanners(banners: banners, child: empty);
    }

    final list = ListView(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 0, desktop ? 8 : 14, desktop ? 28 : 0, 118),
      children: [
        if (withDue.isNotEmpty) ...[
          _groupHead(label: l.withDueUnplannedSection, count: withDue.length),
          for (var index = 0; index < withDue.length; index++)
            _todoRow(
              withDue[index],
              meta: _inboxMeta(l, withDue[index], names),
              desktop: desktop,
              selected: _isTodoSelected(selection, withDue[index].id),
              checked: withDue[index].status == 'COMPLETED',
              onTap: open == null ? null : () => open(withDue[index]),
              slot: _UndoSlot(_UndoGroup.inboxWithDue, index),
            ),
        ],
        if (noDue.isNotEmpty) ...[
          _groupHead(label: noDateOnly ? l.noDateGroupSection : l.noDueSection, count: noDue.length),
          for (var index = 0; index < noDue.length; index++)
            _todoRow(
              noDue[index],
              meta: _inboxMeta(l, noDue[index], names),
              desktop: desktop,
              selected: _isTodoSelected(selection, noDue[index].id),
              checked: noDue[index].status == 'COMPLETED',
              onTap: open == null ? null : () => open(noDue[index]),
              slot: _UndoSlot(_UndoGroup.inboxNoDue, index),
            ),
        ],
      ],
    );
    return _withBanners(banners: banners, child: list);
  }

  /// A completed row stays where it was for the undo window, even though the
  /// pending list has already dropped it.
  void _pinInboxWindows(List<Todo> withDue, List<Todo> noDue) {
    for (final entry in _undoEntries.values.toList()) {
      final slot = entry.slot;
      if (slot == null) continue;
      final isWithDue = slot.group == _UndoGroup.inboxWithDue;
      if (!isWithDue && slot.group != _UndoGroup.inboxNoDue) continue;
      withDue.removeWhere((todo) => todo.id == entry.todo.id);
      noDue.removeWhere((todo) => todo.id == entry.todo.id);
      final target = isWithDue ? withDue : noDue;
      target.insert(
        slot.index.clamp(0, target.length).toInt(),
        entry.todo,
      );
    }
  }

  Widget _allBody(
    AppLocalizations l,
    List<Todo> todos,
    List<TaskAllocationCalendarItem> allocations,
    Map<int, String> names,
    WorkspaceSelection? selection,
    bool desktop,
    bool loading,
    bool filtered,
  ) {
    if (loading) return _loading();

    if (filtered) {
      final activeTodos = todos.where((t) => t.status != 'COMPLETED').toList();
      final banners = <Widget>[
        _filterBanner(l, activeTodos.length, desktop),
      ];
      if (activeTodos.isEmpty) {
        final empty = A2Empty(title: l.filterEmptyTitle, hint: l.filterEmptyHint);
        return _withBanners(banners: banners, child: empty);
      }
      final allocationByTodo = _earliestAllocations(allocations);
      final open = widget.onOpenTodo;
      final list = ListView.builder(
        padding: EdgeInsets.fromLTRB(desktop ? 28 : 0, desktop ? 8 : 14, desktop ? 28 : 0, 118),
        itemCount: activeTodos.length,
        itemBuilder: (context, index) {
          final todo = activeTodos[index];
          return _todoRow(
            todo,
            meta: _allMeta(l, todo, allocationByTodo[todo.id], names),
            desktop: desktop,
            selected: _isTodoSelected(selection, todo.id),
            checked: false,
            onTap: open == null ? null : () => open(todo),
            slot: _UndoSlot(_UndoGroup.allLater, index),
          );
        },
      );
      return _withBanners(banners: banners, child: list);
    }
    final today = _dayOf(widget.now);
    final dueToday = <Todo>[];
    final pastDue = <Todo>[];
    final later = <Todo>[];
    final noDue = <Todo>[];
    final done = <Todo>[];
    for (final todo in todos) {
      if (todo.status == 'COMPLETED') {
        done.add(todo);
        continue;
      }
      final due = todo.dueDate?.toLocal();
      if (due == null) {
        if ((_currentMissedCounts[todo.id] ?? 0) > 0) {
          pastDue.add(todo);
        } else {
          noDue.add(todo);
        }
        continue;
      }
      final day = _dayOf(due);
      if (_sameDay(day, today)) {
        dueToday.add(todo);
      } else if (day.isBefore(today)) {
        pastDue.add(todo);
      } else {
        later.add(todo);
      }
    }

    int byDueDate(Todo a, Todo b) =>
        (a.dueDate ?? DateTime(0)).compareTo(b.dueDate ?? DateTime(0));
    dueToday.sort(byDueDate);
    pastDue.sort(byDueDate);
    later.sort(byDueDate);

    _pinAllWindows(dueToday, pastDue, later, noDue);
    final pinnedIds = {
      for (final e in _undoEntries.values)
        if (e.slot?.group.isAllList ?? false) e.todo.id,
    };
    done.removeWhere((todo) => pinnedIds.contains(todo.id));

    final banners = <Widget>[
      if (filtered) _filterBanner(l, todos.length, desktop),
    ];
    if (dueToday.isEmpty &&
        pastDue.isEmpty &&
        later.isEmpty &&
        noDue.isEmpty &&
        done.isEmpty) {
      final empty = filtered
          ? A2Empty(title: l.filterEmptyTitle, hint: l.filterEmptyHint)
          : A2Empty(title: l.todosEmptyTitle, hint: l.todosEmptyHint);
      return _withBanners(banners: banners, child: empty);
    }

    final allocationByTodo = _earliestAllocations(allocations);
    final open = widget.onOpenTodo;
    Widget row(Todo todo, _UndoSlot slot) => _todoRow(
      todo,
      meta: _allMeta(l, todo, allocationByTodo[todo.id], names),
      desktop: desktop,
      selected: _isTodoSelected(selection, todo.id),
      checked: todo.status == 'COMPLETED',
      onTap: open == null ? null : () => open(todo),
      slot: slot,
    );

    final list = ListView(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 0, desktop ? 8 : 14, desktop ? 28 : 0, 118),
      children: [
        if (dueToday.isNotEmpty) ...[
          _groupHead(
            label: l.allDueTodaySection,
            count: dueToday.length,
            tone: context.ds.warn,
          ),
          for (var index = 0; index < dueToday.length; index++)
            row(dueToday[index], _UndoSlot(_UndoGroup.allDueToday, index)),
        ],
        if (pastDue.isNotEmpty) ...[
          _groupHead(
            label: l.pastDueOrMissedSection,
            count: pastDue.length,
            danger: true,
          ),
          for (var index = 0; index < pastDue.length; index++)
            row(pastDue[index], _UndoSlot(_UndoGroup.allPastDue, index)),
        ],
        if (later.isNotEmpty) ...[
          _groupHead(label: l.allLaterSection, count: later.length),
          for (var index = 0; index < later.length; index++)
            row(later[index], _UndoSlot(_UndoGroup.allLater, index)),
        ],
        if (noDue.isNotEmpty) ...[
          _groupHead(label: l.allUnplannedNoDueSection, count: noDue.length),
          for (var index = 0; index < noDue.length; index++)
            row(noDue[index], _UndoSlot(_UndoGroup.allNoDue, index)),
        ],
        _groupHead(
          label: l.completed,
          count: done.length,
          countLabel: l.groupCountItems(done.length),
          trailing: Icon(
            _completedOpen
                ? CupertinoIcons.chevron_down
                : CupertinoIcons.chevron_right,
            size: 11,
            color: context.ds.faint,
          ),
          onTap: () => setState(() => _completedOpen = !_completedOpen),
        ),
        if (_completedOpen)
          for (var index = 0; index < done.length; index++)
            row(done[index], _UndoSlot(_UndoGroup.allCompleted, index)),
      ],
    );
    return _withBanners(banners: banners, child: list);
  }

  /// All's natural sort sinks finished work. During the undo window the row
  /// must not move, so it is removed from wherever it landed and put back at
  /// the slot it occupied when it was ticked.
  void _pinAllWindows(
    List<Todo> dueToday,
    List<Todo> pastDue,
    List<Todo> later,
    List<Todo> noDue,
  ) {
    for (final entry in _undoEntries.values.toList()) {
      final slot = entry.slot;
      if (slot == null || !slot.group.isAllList) continue;
      for (final list in <List<Todo>>[dueToday, pastDue, later, noDue]) {
        list.removeWhere((todo) => todo.id == entry.todo.id);
      }
      final target = switch (slot.group) {
        _UndoGroup.allDueToday => dueToday,
        _UndoGroup.allPastDue => pastDue,
        _UndoGroup.allLater => later,
        _ => noDue,
      };
      target.insert(
        slot.index.clamp(0, target.length).toInt(),
        entry.todo,
      );
    }
  }

  Widget _dayBody(
    AppLocalizations l,
    Map<int, String> names,
    WorkspaceSelection? selection,
    bool desktop,
    bool Function(Todo) visible,
    List<Todo> noDateTodos,
    bool filtered,
    bool isLoading,
  ) {
    if (isLoading) return _loading();
    final agenda = widget.dayAgenda;
    final allocations = <DayItem>[
      for (final item in agenda.allocations)
        if (item.todo == null || visible(item.todo!)) item,
    ]..sort((a, b) => a.start!.compareTo(b.start!));
    final events = <DayItem>[
      for (final item in agenda.events)
        if (!item.allDay &&
            item.start != null &&
            item.end != null &&
            item.start!.day == item.end!.day)
          item,
    ]..sort((a, b) => a.start!.compareTo(b.start!));
    final dueAll = <DayItem>[
      for (final item in agenda.dueTodos)
        if (item.todo == null || visible(item.todo!)) item,
    ];
    // Finished work sinks inside the group, exactly as in All; two passes keep
    // the projection's own order inside each half (List.sort is not stable).
    final due = <DayItem>[
      for (final item in dueAll)
        if (!item.completed) item,
      for (final item in dueAll)
        if (item.completed) item,
    ];
    final openTodo = widget.onOpenTodo;
    final hasNoContent =
        allocations.isEmpty && due.isEmpty && noDateTodos.isEmpty;
    final matchCount =
        allocations.length + due.length + noDateTodos.length;
    final banners = <Widget>[
      if (filtered) _filterBanner(l, matchCount, desktop),
    ];

    final list = ListView(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 0, desktop ? 8 : 14, desktop ? 28 : 0, 118),
      children: [
        _bgBand(l, events, desktop),
        if (hasNoContent)
          filtered
              ? A2Empty(title: l.filterEmptyTitle, hint: l.filterEmptyHint)
              : A2Empty(title: l.emptyDateTitle, hint: l.emptyDateHint),
        if (allocations.isNotEmpty) ...[
          _groupHead(label: l.datePlannedSection, count: allocations.length),
          for (var index = 0; index < allocations.length; index++)
            _todoRow(
              allocations[index].todo!,
              meta: _dayAllocationMeta(l, allocations[index]),
              desktop: desktop,
              selected: _isTodoSelected(
                selection,
                allocations[index].todoId,
              ),
              checked: allocations[index].completed,
              occurrenceId:
                  allocations[index].allocation?.allocation.occurrenceId,
              onTap: openTodo == null
                  ? null
                  : () => openTodo(allocations[index].todo!),
              slot: _UndoSlot(_UndoGroup.dayPlanned, index),
            ),
        ],
        if (due.isNotEmpty) ...[
          _groupHead(label: l.dateDueSection, count: due.length),
          for (var index = 0; index < due.length; index++)
            _todoRow(
              due[index].todo!,
              meta: _deadlineMeta(l, due[index]),
              desktop: desktop,
              selected: _isTodoSelected(selection, due[index].todoId),
              checked: due[index].completed,
              onTap: openTodo == null
                  ? null
                  : () => openTodo(due[index].todo!),
              slot: _UndoSlot(_UndoGroup.dayDue, index),
            ),
        ],
        if (noDateTodos.isNotEmpty) ...[
          _groupHead(
            label: l.noDateGroupSection,
            count: noDateTodos.length,
          ),
          for (var index = 0;
              index < (noDateTodos.length > 5 ? 5 : noDateTodos.length);
              index++)
            _todoRow(
              noDateTodos[index],
              meta: _inboxMeta(l, noDateTodos[index], names),
              desktop: desktop,
              selected: _isTodoSelected(selection, noDateTodos[index].id),
              checked: noDateTodos[index].status == 'COMPLETED',
              onTap: openTodo == null
                  ? null
                  : () => openTodo(noDateTodos[index]),
              slot: _UndoSlot(_UndoGroup.inboxNoDue, index),
            ),
          if (noDateTodos.length > 5)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openInboxNoDate,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(33, 8, 16, 8),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.arrow_right,
                        size: 10,
                        color: SpecTokens.muted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        l.viewNoDateCount(noDateTodos.length),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: SpecTokens.muted,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
    return _withBanners(banners: banners, child: list);
  }

  Widget _bgBand(
    AppLocalizations l,
    List<DayItem> events,
    bool desktop,
  ) {
    final ds = context.ds;
    return Container(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 16, 10, desktop ? 28 : 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                l.events,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: SpecTokens.muted,
                  letterSpacing: 0.04 * 10,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  l.dayEventsBgSub(events.length),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: SpecTokens.faint,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ],
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 7),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in events) ...[
                    _bgChip(item),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bgChip(DayItem item) {
    final start = item.start;
    final timeStr = start == null ? '' : DateFormatters.formatTime(start);
    final color = item.calendarColor ?? SpecTokens.work;
    return FocusableTap(
      onTap: () {
        if (widget.onOpenEvent != null && item.event != null) {
          widget.onOpenEvent!(item.event!);
        }
      },
      semanticsLabel: timeStr.isEmpty ? item.title : '$timeStr ${item.title}',
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFBF8),
          border: Border.all(color: SpecTokens.hair),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            if (timeStr.isNotEmpty) ...[
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 10,
                  color: SpecTokens.ink2,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 10,
                color: SpecTokens.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- rows

  Widget _todoRow(
    Todo todo, {
    required List<Widget> meta,
    required bool desktop,
    required bool selected,
    required bool checked,
    String? occurrenceId,
    VoidCallback? onTap,
    _UndoSlot? slot,
  }) {
    final l = AppLocalizations.of(context)!;
    final inWindow = _inUndoWindow(todo.id, occurrenceId);
    final onSchedule = widget.onScheduleTodo ?? _schedule;
    final due = todo.dueDate?.toLocal();
    final hasDue = due != null;
    final dueLabel = hasDue
        ? _dueValue(l, due, includeToday: true)
        : null;
    final overdue = hasDue ? _isOverdue(due) : false;

    return SpecTaskRow(
      key: ValueKey('todo-row-${todo.id}-${occurrenceId ?? 'series'}'),
      title: todo.summary,
      checked: checked || inWindow,
      selected: selected,
      meta: meta,
      dueLabel: dueLabel,
      isOverdue: overdue,
      mobileFidelity: !desktop,
      trailing: inWindow
          ? _A2RowAction(
              actionKey: ValueKey(
                'todo-undo-${todo.id}-${occurrenceId ?? 'series'}',
              ),
              label: _undoLabel(l, occurrenceId),
              tooltip: _undoLabel(l, occurrenceId),
              highlight: true,
              onPressed: () => _setCompleted(todo, occurrenceId, false),
            )
          : null,
      onSchedule: inWindow ? null : () => onSchedule(todo),
      scheduleTooltip: l.scheduleAction,
      scheduleKey: ValueKey(
        'todo-schedule-${todo.id}-${occurrenceId ?? 'series'}',
      ),
      onToggle: widget.onToggleTodo == null
          ? null
          : (value) =>
                _toggle(todo, occurrenceId, value, slot: slot),
      onTap: onTap,
    );
  }

  bool _isTodoSelected(WorkspaceSelection? selection, int id) =>
      selection is TodoSelection && selection.todo.id == id;

  // -------------------------------------------------------------------- meta

  List<Widget> _inboxMeta(
    AppLocalizations l,
    Todo todo,
    Map<int, String> names,
  ) {
    final cal = _calendarMap[todo.calendarId];
    return buildSharedRowMeta(
      context,
      calendarName: cal?.name ?? names[todo.calendarId],
      calendarColor: cal != null ? ColorUtils.parseHex(cal.color) : null,
      rrule: todo.rrule,
      missedCount: _currentMissedCounts[todo.id],
    );
  }

  List<Widget> _allMeta(
    AppLocalizations l,
    Todo todo,
    TaskAllocationCalendarItem? allocation,
    Map<int, String> names,
  ) {
    final cal = _calendarMap[todo.calendarId];
    String? planLabel;
    if (allocation != null) {
      final start = allocation.allocation.startAt.toLocal();
      final end = allocation.allocation.endAt.toLocal();
      final sameDay = _sameDay(_dayOf(start), _dayOf(widget.now));
      planLabel = l.plannedShortRangeLabel(
        _rangeLabel(start, end, includeDate: !sameDay),
      );
    }
    return buildSharedRowMeta(
      context,
      calendarName: cal?.name ?? names[todo.calendarId],
      calendarColor: cal != null ? ColorUtils.parseHex(cal.color) : null,
      rrule: todo.rrule,
      missedCount: _currentMissedCounts[todo.id],
      planLabel: planLabel,
    );
  }

  List<Widget> _dayAllocationMeta(AppLocalizations l, DayItem item) {
    String? planLabel;
    final start = item.start;
    final end = item.end;
    if (start != null && end != null) {
      planLabel = l.plannedShortRangeLabel(_rangeLabel(start, end, includeDate: false));
    }
    final cal = item.todo != null ? _calendarMap[item.todo!.calendarId] : null;
    return buildSharedRowMeta(
      context,
      calendarName: item.calendarName ?? cal?.name,
      calendarColor: item.calendarColor ?? (cal != null ? ColorUtils.parseHex(cal.color) : null),
      rrule: item.todo?.rrule,
      missedCount: item.todo != null ? _currentMissedCounts[item.todo!.id] : null,
      planLabel: planLabel,
    );
  }

  List<Widget> _deadlineMeta(AppLocalizations l, DayItem item) {
    final cal = item.todo != null ? _calendarMap[item.todo!.calendarId] : null;
    return buildSharedRowMeta(
      context,
      calendarName: item.calendarName ?? cal?.name,
      calendarColor: item.calendarColor ?? (cal != null ? ColorUtils.parseHex(cal.color) : null),
      rrule: item.todo?.rrule,
      missedCount: item.todo != null ? _currentMissedCounts[item.todo!.id] : null,
    );
  }


  String _dueValue(
    AppLocalizations l,
    DateTime due, {
    bool includeToday = false,
  }) {
    final hasTime = due.hour != 0 || due.minute != 0;
    final time = hasTime ? DateFormatters.formatTime(due) : null;
    if (_sameDay(_dayOf(due), _dayOf(widget.now))) {
      if (!hasTime) return l.today;
      return includeToday ? '${l.today} $time' : time!;
    }
    final date = due.year == widget.now.year
        ? '${due.month}/${due.day}'
        : '${due.year}/${due.month}/${due.day}';
    return hasTime ? '$date $time' : date;
  }

  String _rangeLabel(
    DateTime start,
    DateTime end, {
    required bool includeDate,
  }) {
    final times =
        '${DateFormatters.formatTime(start)}–'
        '${DateFormatters.formatTime(end)}';
    if (!includeDate) return times;
    return '${start.month}/${start.day} $times';
  }

  Map<int, TaskAllocationCalendarItem> _earliestAllocations(
    List<TaskAllocationCalendarItem> items,
  ) {
    final byTodo = <int, TaskAllocationCalendarItem>{};
    for (final item in items) {
      final id = item.todo.id;
      final existing = byTodo[id];
      if (existing == null ||
          item.allocation.startAt.isBefore(existing.allocation.startAt)) {
        byTodo[id] = item;
      }
    }
    return byTodo;
  }
}

enum _UndoGroup {
  inboxWithDue,
  inboxNoDue,
  allDueToday,
  allPastDue,
  allLater,
  allNoDue,
  allCompleted,
  dayPlanned,
  dayDue;

  bool get isAllList =>
      this == allDueToday ||
      this == allPastDue ||
      this == allLater ||
      this == allNoDue ||
      this == allCompleted;
}

class _UndoSlot {
  const _UndoSlot(this.group, this.index);

  final _UndoGroup group;
  final int index;
}

class _UndoEntry {
  const _UndoEntry({
    required this.todo,
    required this.occurrenceId,
    required this.slot,
  });

  final Todo todo;
  final String? occurrenceId;
  final _UndoSlot? slot;
}

/// A 44-high text action on the row's right edge. Ghost by default (schedule);
/// the undo variant borrows the primary-soft pill the snackbar's undo uses.
class _A2RowAction extends StatelessWidget {
  const _A2RowAction({
    required this.actionKey,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.highlight = false,
  });

  final Key actionKey;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FocusableTap(
        key: actionKey,
        onTap: onPressed,
        semanticsLabel: tooltip,
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
            maxHeight: 44,
            maxWidth: 160,
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: highlight
                  ? BoxDecoration(
                      color: SpecTokens.wash,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

