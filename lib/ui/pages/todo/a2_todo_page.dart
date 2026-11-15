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
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';

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
  bool _captureFocused = false;

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

  Future<void> _toggle(Todo todo, String? occurrenceId, bool completed) async {
    final callback = widget.onToggleTodo;
    if (callback == null) return;
    try {
      await callback(todo, occurrenceId, completed);
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
    }
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
        ref.watch(todoTagIdsMapProvider).valueOrNull ??
        const <int, Set<int>>{};
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
    final strip = view is TodosDayView ? _dateStrip(l, viewed) : null;
    final footer = _footer(l, view, viewed);

    final Widget body;
    if (view is TodosInboxView) {
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
    final content = desktop
        ? _cardHead(title, subtitle, actions)
        : A2DayHead(
            title: title,
            subtitle: subtitle,
            clock: DateFormatters.formatTime(widget.now),
            actions: actions,
          );
    return Stack(
      children: [
        content,
        Positioned(
          left: 0,
          top: desktop ? 6 : 5,
          width: 260,
          height: 44,
          child: GestureDetector(
            key: const ValueKey('todos-mode-switch'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _openModeSheet(l),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  Widget _cardHead(String title, String subtitle, List<Widget> actions) {
    final ds = context.ds;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _type(11, FontWeight.w400, ds.ink3, height: 1.5),
                ),
              ],
            ),
          ),
          A2Clock(label: DateFormatters.formatTime(widget.now)),
          ...actions,
        ],
      ),
    );
  }

  Future<void> _openModeSheet(AppLocalizations l) async {
    final ds = context.ds;
    final view = ref.read(todosViewProvider);
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
                  _selectMode(
                    TodosDayView(_dayOf(ref.read(viewedDateProvider))),
                  );
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

  Widget _dateStrip(AppLocalizations l, DateTime viewed) {
    final ds = context.ds;
    final day = _dayOf(viewed);
    final today = _dayOf(widget.now);
    final isToday = _sameDay(day, today);
    final dateText =
        '${DateFormat.MMMd(_locale).format(day)} '
        '${DateFormat.E(_locale).format(day)}';
    final line1 = isToday ? l.today : dateText;
    final line2 = isToday
        ? '$dateText · ${day.year}'
        : '${l.inDaysCount(_daysBetween(day, today).abs())} · ${day.year}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showMonthYearPicker(context, initial: day),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(
            color: ds.bg,
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
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
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: l.pickDateHint,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                      color: ds.ink3,
                    ),
                  ),
                ),
              ),
            ],
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

  Widget _inboxBody(
    AppLocalizations l,
    List<Todo> todos,
    Map<int, String> names,
    WorkspaceSelection? selection,
    bool desktop,
    bool loading,
  ) {
    if (loading) return _loading();
    if (todos.isEmpty) {
      return A2Empty(title: l.emptyUnplannedTitle, hint: l.emptyUnplannedHint);
    }
    final withDue = <Todo>[
      for (final todo in todos)
        if (todo.dueDate != null) todo,
    ];
    final noDue = <Todo>[
      for (final todo in todos)
        if (todo.dueDate == null) todo,
    ];
    final schedule = widget.onScheduleTodo;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (withDue.isNotEmpty) ...[
          A2GroupHead(label: l.withDueUnplannedSection, count: withDue.length),
          for (final todo in withDue)
            _todoRow(
              todo,
              meta: _inboxMeta(l, todo, names),
              desktop: desktop,
              selected: _isTodoSelected(selection, todo.id),
              checked: todo.status == 'COMPLETED',
              onTap: schedule == null ? null : () => schedule(todo),
            ),
        ],
        if (noDue.isNotEmpty) ...[
          A2GroupHead(label: l.noDueSection, count: noDue.length),
          for (final todo in noDue)
            _todoRow(
              todo,
              meta: _inboxMeta(l, todo, names),
              desktop: desktop,
              selected: _isTodoSelected(selection, todo.id),
              checked: todo.status == 'COMPLETED',
              onTap: schedule == null ? null : () => schedule(todo),
            ),
        ],
      ],
    );
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
    if (todos.isEmpty) {
      return A2Empty(title: l.allTasks, hint: l.emptyUnplannedHint);
    }
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
    int byDue(Todo a, Todo b) => a.dueDate!.compareTo(b.dueDate!);
    dueToday.sort(byDue);
    pastDue.sort(byDue);
    later.sort(byDue);

    final allocationByTodo = _earliestAllocations(allocations);
    final open = widget.onOpenTodo;
    Widget row(Todo todo) => _todoRow(
      todo,
      meta: _allMeta(l, todo, allocationByTodo[todo.id], names),
      desktop: desktop,
      selected: _isTodoSelected(selection, todo.id),
      checked: todo.status == 'COMPLETED',
      onTap: open == null ? null : () => open(todo),
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (dueToday.isNotEmpty) ...[
          A2GroupHead(label: l.allDueTodaySection, count: dueToday.length),
          for (final todo in dueToday) row(todo),
        ],
        if (pastDue.isNotEmpty) ...[
          A2GroupHead(label: l.allPastDueSection, count: pastDue.length),
          for (final todo in pastDue) row(todo),
        ],
        if (later.isNotEmpty) ...[
          A2GroupHead(label: l.allLaterSection, count: later.length),
          for (final todo in later) row(todo),
        ],
        if (noDue.isNotEmpty) ...[
          A2GroupHead(label: l.allUnplannedNoDueSection, count: noDue.length),
          for (final todo in noDue) row(todo),
        ],
      ],
    );
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
    final due = <DayItem>[
      for (final item in agenda.dueTodos)
        if (item.todo == null || visible(item.todo!)) item,
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
          for (final item in allocations)
            _todoRow(
              item.todo!,
              meta: _dayAllocationMeta(l, item),
              desktop: desktop,
              selected: _isTodoSelected(selection, item.todoId),
              checked: item.completed,
              occurrenceId: item.allocation?.allocation.occurrenceId,
              onTap: openTodo == null ? null : () => openTodo(item.todo!),
            ),
        ],
        if (due.isNotEmpty) ...[
          A2GroupHead(label: l.dateDueSection, count: due.length),
          for (final item in due)
            _todoRow(
              item.todo!,
              meta: _deadlineMeta(l, item),
              desktop: desktop,
              selected: _isTodoSelected(selection, item.todoId),
              checked: item.completed,
              onTap: openTodo == null ? null : () => openTodo(item.todo!),
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
  }) {
    return _maybeHover(
      desktop: desktop,
      selected: selected,
      builder: (background) => A2Row(
        title: todo.summary,
        checked: checked,
        selected: selected,
        background: background,
        meta: meta,
        onToggle: widget.onToggleTodo == null
            ? null
            : (value) => _toggle(todo, occurrenceId, value),
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
