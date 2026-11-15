import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

import 'a2_composer.dart';
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
    this.onPlanDay,
    this.onScheduleTodo,
    this.onOpenEvent,
    this.onOpenUnplanned,
    this.trailingActions = const <Widget>[],
    this.detail,
  });

  final DateTime now;
  final DayAgenda dayAgenda;
  final ValueChanged<Todo>? onOpenTodo;
  final Future<void> Function(Todo todo, String? occurrenceId, bool completed)?
  onToggleTodo;
  final Future<void> Function(String text)? onCapture;
  final ValueChanged<DateTime>? onPlanDay;
  final ValueChanged<Todo>? onScheduleTodo;
  final ValueChanged<CalendaEventAdapter>? onOpenEvent;
  final VoidCallback? onOpenUnplanned;
  final List<Widget> trailingActions;
  final Widget? detail;

  @override
  ConsumerState<A2TodoPage> createState() => _A2TodoPageState();
}

class _A2TodoPageState extends ConsumerState<A2TodoPage> {
  static const Duration _undoWindow = Duration(seconds: 5);

  bool _captureFocused = false;

  final Map<String, _UndoEntry> _undoEntries = {};
  final Map<String, _UndoSlot> _lastSlots = {};
  final Map<String, Timer> _undoTimers = {};
  final Map<String, int> _undoGenerations = {};

  @override
  void dispose() {
    for (final timer in _undoTimers.values) {
      timer.cancel();
    }
    super.dispose();
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

  TextStyle _type(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFamilyFallback: AppTypography.fallback,
    );
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
  /// A completion keeps the row in place for five seconds; that window is the
  /// visible, unambiguous counterpart to the snackbar's undo.
  Future<void> _setCompleted(
    Todo todo,
    String? occurrenceId,
    bool completed, {
    _UndoSlot? slot,
  }) async {
    final callback = widget.onToggleTodo;
    if (callback == null) return;
    try {
      await callback(todo, occurrenceId, completed);
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(completed ? l.completed : l.openTask),
          action: SnackBarAction(
            label: l.undo,
            onPressed: () => _setCompleted(todo, occurrenceId, !completed),
          ),
        ),
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

  void _schedule(Todo todo) {
    final onSchedule = widget.onScheduleTodo;
    if (onSchedule != null) {
      onSchedule(todo);
      return;
    }
    showA2Composer(
      context,
      contextDate: ref.read(viewedDateProvider),
      todo: todo,
    );
  }

  Future<void> _capture(String text) async {
    final callback = widget.onCapture;
    if (callback == null) return;
    try {
      await callback(text);
    } on Object catch (error) {
      debugPrint('todo: capture failed: $error');
      if (mounted) showCompletionError(context, error);
    }
  }

  void _selectMode(TodosView view) {
    if (view is TodosInboxView && widget.onOpenUnplanned != null) {
      widget.onOpenUnplanned!();
      return;
    }
    ref.read(todosViewProvider.notifier).state = view;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final view = ref.watch(todosViewProvider);
    final viewed = ref.watch(viewedDateProvider);
    final desktop = isWorkspaceLayout(context);
    final unplannedAsync = ref.watch(unplannedTodosProvider);
    final allAsync = ref.watch(allTodosProvider);
    final allocationsAsync = ref.watch(allActiveTaskAllocationsProvider);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final hideCompleted = ref.watch(hideCompletedProvider).valueOrNull ?? false;
    final tagMap =
        ref.watch(todoTagIdsMapProvider).valueOrNull ?? const <int, Set<int>>{};
    final calendarFilter = ref.watch(todoCalendarFilterProvider);
    final tagFilter = ref.watch(todoTagFilterProvider);
    final priorityFilter = ref.watch(todoPriorityFilterProvider);

    // The filter sheet lives in this header, so every list behind it answers
    // to it: a control that changes nothing is worse than no control.
    bool visible(Todo todo) {
      if (hideCompleted && todo.status == 'COMPLETED') return false;
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
    final allocations =
        allocationsAsync.valueOrNull ?? const <TaskAllocationCalendarItem>[];
    final selection = ref.watch(workspaceSelectionProvider);

    final head = _head(l, view, unplanned, allRows, desktop);
    // By date needs one entry that reaches any month in two taps. The desktop
    // bar outside this page prints a date but cannot open a picker, so the
    // strip is the only honest entry on both platforms.
    final strip = view is TodosDayView
        ? _dateStrip(l, viewed, desktop: desktop)
        : null;
    final footer = _footer(l, view, viewed);

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
        unplanned,
        names,
        selection,
        desktop,
        unplannedAsync.isLoading && !unplannedAsync.hasValue,
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
      );
    } else {
      body = _dayBody(l, names, selection, desktop, visible);
    }

    if (desktop) {
      return Material(
        color: ds.bg,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: ds.surface,
                        border: Border.all(color: ds.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          head,
                          if (strip != null) strip,
                          Expanded(child: body),
                          footer,
                        ],
                      ),
                    ),
                  ),
                  if (widget.detail != null) ...[
                    const SizedBox(width: 20),
                    SizedBox(width: 320, child: widget.detail!),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: ds.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (strip != null) strip,
          Expanded(child: body),
          footer,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ header

  Widget _head(
    AppLocalizations l,
    TodosView view,
    List<Todo> unplanned,
    List<Todo> allRows,
    bool desktop,
  ) {
    final withDue = unplanned.where((todo) => todo.dueDate != null).length;
    final active = allRows.where((todo) => todo.status != 'COMPLETED').length;
    final String title;
    final String subtitle;
    if (view is TodosInboxView) {
      title = l.inbox;
      subtitle = l.todoUnplannedContext(unplanned.length, withDue);
    } else if (view is TodosAllView) {
      title = l.allTasks;
      subtitle = l.todoAllSummary(allRows.length, active);
    } else {
      title = l.byDateTitle;
      subtitle = l.byDateContext;
    }
    final actions = <Widget>[
      ...widget.trailingActions,
      A2IconAction(
        icon: CupertinoIcons.settings,
        tooltip: l.settings,
        onPressed: () => context.push('/settings'),
      ),
    ];
    // The switch used to be an invisible 260x44 hit zone over the title. A
    // control you cannot see is a control you cannot learn, so the title now
    // carries the chevron itself and the whole title block is the hit area.
    final titleBlock = _titleBlock(l, title, subtitle);
    return desktop
        ? _cardHead(titleBlock, actions)
        : _dayHead(titleBlock, actions);
  }

  Widget _titleBlock(AppLocalizations l, String title, String subtitle) {
    final ds = context.ds;
    return Semantics(
      button: true,
      label: l.todosSwitchMode,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('todos-mode-switch'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _openModeSheet(l),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _type(
                        20,
                        FontWeight.w600,
                        ds.ink,
                        height: 1.3,
                      ).copyWith(letterSpacing: 0.1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.chevron_down, size: 15, color: ds.ink3),
                ],
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _type(11, FontWeight.w400, ds.ink3, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayHead(Widget titleBlock, List<Widget> actions) {
    final ds = context.ds;
    return Container(
      height: kA2TopBarHeight,
      padding: const EdgeInsets.only(left: 16, right: 4),
      color: ds.bg,
      child: Row(
        children: [
          Expanded(child: titleBlock),
          A2Clock(label: DateFormatters.formatTime(widget.now)),
          ...actions,
        ],
      ),
    );
  }

  Widget _cardHead(Widget titleBlock, List<Widget> actions) {
    final ds = context.ds;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(child: titleBlock),
          A2Clock(label: DateFormatters.formatTime(widget.now)),
          ...actions,
        ],
      ),
    );
  }

  Future<void> _openModeSheet(AppLocalizations l) async {
    final ds = context.ds;
    final view = ref.read(todosViewProvider);
    // A window has no bottom edge to slide from, so the same three rows open
    // as the product's dialog instead of a phone sheet.
    if (isWorkspaceLayout(context)) {
      await showDialog<void>(
        context: context,
        barrierColor: ds.scrim,
        builder: (dialogContext) => DsDialog(
          title: l.todosSwitchMode,
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeRow(
                icon: CupertinoIcons.tray,
                label: l.inbox,
                active: view is TodosInboxView,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _selectMode(const TodosInboxView());
                },
              ),
              _modeRow(
                icon: CupertinoIcons.list_bullet,
                label: l.allTasks,
                active: view is TodosAllView,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _selectMode(const TodosAllView());
                },
              ),
              _modeRow(
                icon: CupertinoIcons.calendar,
                label: l.byDateTitle,
                hint: l.pickDateHint,
                active: view is TodosDayView,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _selectMode(const TodosDayView());
                },
              ),
            ],
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: ds.scrim,
      builder: (sheetContext) => Material(
        color: ds.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ds.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _modeRow(
                icon: CupertinoIcons.tray,
                label: l.inbox,
                active: view is TodosInboxView,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _selectMode(const TodosInboxView());
                },
              ),
              _modeRow(
                icon: CupertinoIcons.list_bullet,
                label: l.allTasks,
                active: view is TodosAllView,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _selectMode(const TodosAllView());
                },
              ),
              _modeRow(
                icon: CupertinoIcons.calendar,
                label: l.byDateTitle,
                hint: l.pickDateHint,
                active: view is TodosDayView,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _selectMode(const TodosDayView());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeRow({
    required IconData icon,
    required String label,
    String? hint,
    required bool active,
    required VoidCallback onTap,
  }) {
    final ds = context.ds;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(icon, size: 19, color: active ? ds.primary : ds.ink3),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _type(
                    15,
                    active ? FontWeight.w600 : FontWeight.w400,
                    ds.ink,
                  ),
                ),
              ),
              if (hint != null)
                Text(hint, style: _type(12, FontWeight.w400, ds.ink3)),
              if (active) ...[
                const SizedBox(width: 10),
                Icon(CupertinoIcons.checkmark, size: 14, color: ds.primary),
              ],
            ],
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
    final dateText =
        '${DateFormat.MMMd(_locale).format(day)} '
        '${DateFormat.E(_locale).format(day)}';
    final delta = _daysBetween(day, today);
    final line1 = isToday ? l.today : dateText;
    final line2 = isToday
        ? '$dateText · ${day.year}'
        // The sign is the point: browsing into the past must not read "In 5
        // days". Only the relative label differs by direction; the year stays.
        : delta > 0
        ? '${l.inDaysCount(delta)} · ${day.year}'
        : '${l.daysAgo(-delta)} · ${day.year}';

    final chevron = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: ds.primarySoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(CupertinoIcons.chevron_down, size: 16, color: ds.primary),
      ),
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _type(17, FontWeight.w600, ds.ink, height: 1.4),
        ),
        Text(
          line2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _type(
            12,
            FontWeight.w400,
            ds.ink3,
          ).copyWith(fontFeatures: AppTypography.tabular),
        ),
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('todos-date-strip'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showMonthYearPicker(context, initial: day),
        child: Container(
          // 56 is the design's strip height; the inner controls stay at their
          // drawn sizes and grow only their touch targets.
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          decoration: BoxDecoration(
            // Inside the desktop card the strip stays on the card's surface;
            // on the phone it sits on the page background as the design draws.
            color: desktop ? ds.surface : ds.bg,
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 12),
              // "Today" is the second thing the design's strip does: tapping
              // the chevron opens the picker, tapping the day jumps back.
              if (!isToday)
                _dateStripAction(
                  label: l.today,
                  tooltip: l.goToToday,
                  onTap: () =>
                      ref.read(viewedDateProvider.notifier).state = today,
                ),
              if (!isToday) const SizedBox(width: 8),
              Tooltip(
                message: l.pickDateHint,
                child: Semantics(
                  button: true,
                  label: l.pickDateHint,
                  child: chevron,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateStripAction({
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('todos-date-strip-today'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // The visible pill is 28 high; the touch target is the design's 48.
          child: SizedBox(
            height: 48,
            child: Center(
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ds.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  style: _type(13, FontWeight.w500, ds.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ footer

  Widget _footer(AppLocalizations l, TodosView view, DateTime viewed) {
    if (view is TodosDayView) {
      final day = _dayOf(viewed);
      final plan = widget.onPlanDay;
      return A2PlanBar(
        label: _planLabel(l, day),
        actionLabel: l.planThisDay,
        onPressed: plan == null ? () {} : () => plan(day),
      );
    }
    return A2CaptureBar(
      placeholder: l.capturePlaceholder,
      hint: _captureFocused ? l.captureHintSubmit : l.captureHintEnter,
      onSubmit: _capture,
      onFocusChange: (focused) {
        if (_captureFocused == focused) return;
        setState(() => _captureFocused = focused);
      },
    );
  }

  String _planLabel(AppLocalizations l, DateTime day) {
    final date = DateFormat.MMMd(_locale).format(day);
    final isToday = _sameDay(day, _dayOf(widget.now));
    final suffix = isToday ? l.today : DateFormat.E(_locale).format(day);
    return l.planToDate('$date · $suffix');
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

  Widget _inboxBody(
    AppLocalizations l,
    List<Todo> todos,
    Map<int, String> names,
    WorkspaceSelection? selection,
    bool desktop,
    bool loading,
  ) {
    if (loading) return _loading();
    final withDue = <Todo>[
      for (final todo in todos)
        if (todo.dueDate != null) todo,
    ];
    final noDue = <Todo>[
      for (final todo in todos)
        if (todo.dueDate == null) todo,
    ];
    _pinInboxWindows(withDue, noDue);
    if (withDue.isEmpty && noDue.isEmpty) {
      return A2Empty(title: l.emptyUnplannedTitle, hint: l.emptyUnplannedHint);
    }
    final open = widget.onOpenTodo;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (withDue.isNotEmpty) ...[
          A2GroupHead(label: l.withDueUnplannedSection, count: withDue.length),
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
          A2GroupHead(label: l.noDueSection, count: noDue.length),
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
  ) {
    if (loading) return _loading();
    final today = _dayOf(widget.now);
    final dueToday = <Todo>[];
    final pastDue = <Todo>[];
    final later = <Todo>[];
    final noDue = <Todo>[];
    for (final todo in todos) {
      final due = todo.dueDate?.toLocal();
      if (due == null) {
        noDue.add(todo);
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
    // Finished work sinks inside its group, as in the design: the first row a
    // reader meets should be one they can act on.
    int byDue(Todo a, Todo b) {
      final aDone = a.status == 'COMPLETED' ? 1 : 0;
      final bDone = b.status == 'COMPLETED' ? 1 : 0;
      if (aDone != bDone) return aDone - bDone;
      return a.dueDate!.compareTo(b.dueDate!);
    }

    dueToday.sort(byDue);
    pastDue.sort(byDue);
    later.sort(byDue);
    _pinAllWindows(dueToday, pastDue, later, noDue);
    if (dueToday.isEmpty &&
        pastDue.isEmpty &&
        later.isEmpty &&
        noDue.isEmpty) {
      return A2Empty(title: l.allTasks, hint: l.noPendingTodos);
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

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (dueToday.isNotEmpty) ...[
          A2GroupHead(label: l.allDueTodaySection, count: dueToday.length),
          for (var index = 0; index < dueToday.length; index++)
            row(dueToday[index], _UndoSlot(_UndoGroup.allDueToday, index)),
        ],
        if (pastDue.isNotEmpty) ...[
          A2GroupHead(label: l.allPastDueSection, count: pastDue.length),
          for (var index = 0; index < pastDue.length; index++)
            row(pastDue[index], _UndoSlot(_UndoGroup.allPastDue, index)),
        ],
        if (later.isNotEmpty) ...[
          A2GroupHead(label: l.allLaterSection, count: later.length),
          for (var index = 0; index < later.length; index++)
            row(later[index], _UndoSlot(_UndoGroup.allLater, index)),
        ],
        if (noDue.isNotEmpty) ...[
          A2GroupHead(label: l.allUnplannedNoDueSection, count: noDue.length),
          for (var index = 0; index < noDue.length; index++)
            row(noDue[index], _UndoSlot(_UndoGroup.allNoDue, index)),
        ],
      ],
    );
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
  ) {
    final agenda = widget.dayAgenda;
    final allocations = <DayItem>[
      for (final item in agenda.allocations)
        if (item.todo == null || visible(item.todo!)) item,
    ]..sort((a, b) => a.start!.compareTo(b.start!));
    final events = <DayItem>[...agenda.events]
      ..sort((a, b) => a.start!.compareTo(b.start!));
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
    if (allocations.isEmpty && due.isEmpty && events.isEmpty) {
      return A2Empty(title: l.emptyDateTitle, hint: l.emptyDateHint);
    }
    final openTodo = widget.onOpenTodo;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (allocations.isNotEmpty) ...[
          A2GroupHead(label: l.datePlannedSection, count: allocations.length),
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
          A2GroupHead(label: l.dateDueSection, count: due.length),
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
        if (events.isNotEmpty) ...[
          A2GroupHead(label: l.dateEventsSection, count: events.length),
          for (final item in events)
            _eventRow(
              item,
              _eventMeta(l, item, names),
              desktop: desktop,
              selected: _isEventSelected(selection, item.event),
            ),
        ],
      ],
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
    return _maybeHover(
      desktop: desktop,
      selected: selected,
      builder: (background) => A2Row(
        title: todo.summary,
        checked: checked || inWindow,
        selected: selected,
        background: background,
        meta: meta,
        // The right edge carries the row's own verb: schedule while the task
        // is at rest, undo while the completion window is open. The title
        // stays the way into the full detail, so the two actions never share
        // a gesture.
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
            : _A2RowAction(
                actionKey: ValueKey(
                  'todo-schedule-${todo.id}-${occurrenceId ?? 'series'}',
                ),
                label: l.scheduleAction,
                tooltip: l.scheduleAction,
                onPressed: () => onSchedule(todo),
              ),
        onToggle: widget.onToggleTodo == null
            ? null
            : (value) =>
                  _toggle(todo, occurrenceId, value, slot: slot),
        onTap: onTap,
      ),
    );
  }

  Widget _eventRow(
    DayItem item,
    List<Widget> meta, {
    required bool desktop,
    required bool selected,
  }) {
    final event = item.event;
    final open = widget.onOpenEvent;
    return _maybeHover(
      desktop: desktop,
      selected: selected,
      builder: (background) => A2Row(
        title: item.title,
        showCheck: false,
        selected: selected,
        background: background,
        meta: meta,
        onTap: event == null || open == null ? null : () => open(event),
      ),
    );
  }

  Widget _maybeHover({
    required bool desktop,
    required bool selected,
    required Widget Function(Color? background) builder,
  }) {
    if (!desktop) return builder(null);
    return _HoverWrap(
      builder: (hovered) =>
          builder(hovered && !selected ? context.ds.surface2 : null),
    );
  }

  bool _isTodoSelected(WorkspaceSelection? selection, int id) =>
      selection is TodoSelection && selection.todo.id == id;

  bool _isEventSelected(
    WorkspaceSelection? selection,
    CalendaEventAdapter? event,
  ) =>
      selection is EventSelection &&
      event != null &&
      selection.event.drifId == event.drifId;

  // -------------------------------------------------------------------- meta

  List<Widget> _inboxMeta(
    AppLocalizations l,
    Todo todo,
    Map<int, String> names,
  ) {
    final parts = <Widget>[];
    final due = todo.dueDate?.toLocal();
    if (due != null) {
      parts.add(
        A2DueCapsule(
          label: l.dueValueLabel(_dueValue(l, due, includeToday: true)),
        ),
      );
    } else {
      parts.add(A2MetaText(l.inbox));
    }
    final name = names[todo.calendarId];
    if (name != null && name.isNotEmpty) {
      parts.add(const A2Sep());
      parts.add(A2MetaText(name));
    }
    return parts;
  }

  List<Widget> _allMeta(
    AppLocalizations l,
    Todo todo,
    TaskAllocationCalendarItem? allocation,
    Map<int, String> names,
  ) {
    final parts = <Widget>[];
    final due = todo.dueDate?.toLocal();
    if (allocation != null) {
      final start = allocation.allocation.startAt.toLocal();
      final end = allocation.allocation.endAt.toLocal();
      final sameDay = _sameDay(_dayOf(start), _dayOf(widget.now));
      parts.add(
        A2MetaText(
          l.plannedShortRangeLabel(
            _rangeLabel(start, end, includeDate: !sameDay),
          ),
          color: context.ds.work,
        ),
      );
      if (due != null) {
        parts.add(const A2Sep());
        parts.add(A2DueCapsule(label: l.dueValueLabel(_dueValue(l, due))));
      }
      return parts;
    }
    if (due != null) {
      parts.add(A2DueCapsule(label: l.dueValueLabel(_dueValue(l, due))));
      return parts;
    }
    parts.add(A2MetaText(l.inbox));
    final name = names[todo.calendarId];
    if (name != null && name.isNotEmpty) {
      parts.add(const A2Sep());
      parts.add(A2MetaText(name));
    }
    return parts;
  }

  List<Widget> _dayAllocationMeta(AppLocalizations l, DayItem item) {
    final parts = <Widget>[];
    final start = item.start;
    final end = item.end;
    if (start != null && end != null) {
      parts.add(
        A2MetaText(
          l.plannedShortRangeLabel(_rangeLabel(start, end, includeDate: false)),
          color: context.ds.work,
        ),
      );
    }
    final due = item.todo?.dueDate?.toLocal();
    if (due != null) {
      if (parts.isNotEmpty) parts.add(const A2Sep());
      parts.add(A2DueCapsule(label: l.dueValueLabel(_dueValue(l, due))));
    }
    return parts;
  }

  List<Widget> _deadlineMeta(AppLocalizations l, DayItem item) {
    final due = item.todo?.dueDate?.toLocal();
    if (due == null) return const [];
    return [
      A2DueCapsule(label: l.dueValueLabel(_dueValue(l, due))),
      if (item.completed) ...[const A2Sep(), A2MetaText(l.completed)],
    ];
  }

  List<Widget> _eventMeta(
    AppLocalizations l,
    DayItem item,
    Map<int, String> names,
  ) {
    final parts = <Widget>[];
    final start = item.start;
    final end = item.end;
    if (start == null) {
      parts.add(A2MetaText(l.allDay));
    } else if (end == null) {
      parts.add(A2MetaText(DateFormatters.formatTime(start)));
    } else {
      parts.add(
        A2MetaText(
          '${DateFormatters.formatTime(start)}–'
          '${DateFormatters.formatTime(end)}',
        ),
      );
    }
    final name = item.calendarName ?? names[item.event?.calendarId];
    if (name != null && name.isNotEmpty) {
      parts.add(const A2Sep());
      parts.add(A2MetaText(name));
    }
    return parts;
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

class _HoverWrap extends StatefulWidget {
  const _HoverWrap({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_HoverWrap> createState() => _HoverWrapState();
}

class _HoverWrapState extends State<_HoverWrap> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}

enum _UndoGroup {
  inboxWithDue,
  inboxNoDue,
  allDueToday,
  allPastDue,
  allLater,
  allNoDue,
  dayPlanned,
  dayDue;

  bool get isAllList =>
      this == allDueToday ||
      this == allPastDue ||
      this == allLater ||
      this == allNoDue;
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
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            key: actionKey,
            onTap: onPressed,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
                          color: ds.primarySoft,
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
                      color: ds.primary,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
