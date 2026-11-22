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
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/design/spec_drawer_overlay.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';
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
  /// Returns whether the write actually happened; a dismissed occurrence
  /// picker must not read as a completion.
  final Future<bool> Function(Todo todo, String? occurrenceId, bool completed)?
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
  bool _completedOpen = false;

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

  bool _isOverdue(DateTime due) {
    final hasTime = due.hour != 0 || due.minute != 0;
    if (hasTime) {
      return due.isBefore(widget.now);
    }
    final today = _dayOf(widget.now);
    return _dayOf(due).isBefore(today);
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
      final noDateTodos = <Todo>[
        for (final todo in unplanned)
          if (todo.dueDate == null) todo,
      ];
      body = _dayBody(l, names, selection, desktop, visible, noDateTodos);
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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
      ),
    );
  }

  bool get _hasFilter =>
      ref.watch(todoCalendarFilterProvider) != null ||
      ref.watch(todoTagFilterProvider).isNotEmpty ||
      ref.watch(todoPriorityFilterProvider) != null;

  Widget _head(
    AppLocalizations l,
    TodosView view,
    List<Todo> unplanned,
    List<Todo> allRows,
    bool desktop,
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
      subtitle = l.todoUnplannedContext(unplanned.length, withDue);
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
    return Tooltip(
      message: l.filter,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('todos-filter-tool'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _showFilterSheet(context),
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
    return showDsSheet<void>(
      context: context,
      title: l.filter,
      actions: [
        DsButton(
          label: l.done,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      body: Consumer(
        builder: (ctx, r, _) {
          final calFilter = r.watch(todoCalendarFilterProvider);
          final tagFilter = r.watch(todoTagFilterProvider);
          final prioFilter = r.watch(todoPriorityFilterProvider);
          final hideCompleted =
              r.watch(hideCompletedProvider).valueOrNull ?? false;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DsGroupLabel(l.calendar),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final calendar in calendars)
                      DsChip(
                        label: calendar.name,
                        selected: calFilter == calendar.id,
                        leading: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: ColorUtils.parseHex(calendar.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        onTap: () =>
                            r.read(todoCalendarFilterProvider.notifier).state =
                                calFilter == calendar.id ? null : calendar.id,
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
                          selected: tagFilter.contains(tag.id),
                          leading: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: ColorUtils.parseHex(tag.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          onTap: () {
                            final next = {...tagFilter};
                            if (!next.remove(tag.id)) next.add(tag.id);
                            r.read(todoTagFilterProvider.notifier).state = next;
                          },
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
                      selected: prioFilter == null,
                      onTap: () =>
                          r.read(todoPriorityFilterProvider.notifier).state =
                              null,
                    ),
                    for (final entry in [
                      (1, l.priorityHigh),
                      (5, l.priorityMedium),
                      (9, l.priorityLow),
                    ])
                      DsChip(
                        label: entry.$2,
                        selected: prioFilter == entry.$1,
                        onTap: () =>
                            r.read(todoPriorityFilterProvider.notifier).state =
                                prioFilter == entry.$1 ? null : entry.$1,
                      ),
                  ],
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
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    r.read(todoCalendarFilterProvider.notifier).state = null;
                    r.read(todoTagFilterProvider.notifier).state = const {};
                    r.read(todoPriorityFilterProvider.notifier).state = null;
                  },
                  child: Text(
                    l.retry,
                    style: const TextStyle(color: SpecTokens.muted),
                  ),
                ),
              ],
            ),
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
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('todos-date-strip'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showMonthYearPicker(context, initial: day),
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
                  child: Semantics(
                    key: ValueKey('todos-date-strip-day-${_dateKey(days[i])}'),
                    button: true,
                    selected: _sameDay(days[i], day),
                    label:
                        '${DateFormat.E(_locale).format(days[i])} ${days[i].day}',
                    onTap: () =>
                        ref.read(viewedDateProvider.notifier).state = days[i],
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('todos-date-strip-today'),
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(viewedDateProvider.notifier).state = today,
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
      ),
    );
  }

  // ------------------------------------------------------------------ footer

  Widget _footer(AppLocalizations l, TodosView view, DateTime viewed) {
    // The spec floats one 560x54 capture pill over the page, bottom 18.
    final desktop = isWorkspaceLayout(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: A2CaptureBar(
            placeholder: l.capturePlaceholder,
            hint: _captureFocused ? l.captureHintSubmit : l.captureHintEnter,
            onSubmit: _capture,
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
          _groupHead(label: l.noDueSection, count: noDue.length),
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
    final done = <Todo>[];
    for (final todo in todos) {
      if (todo.status == 'COMPLETED') {
        done.add(todo);
        continue;
      }
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

    int byDueDate(Todo a, Todo b) => a.dueDate!.compareTo(b.dueDate!);
    dueToday.sort(byDueDate);
    pastDue.sort(byDueDate);
    later.sort(byDueDate);

    _pinAllWindows(dueToday, pastDue, later, noDue);
    final pinnedIds = {
      for (final e in _undoEntries.values)
        if (e.slot?.group.isAllList ?? false) e.todo.id,
    };
    done.removeWhere((todo) => pinnedIds.contains(todo.id));

    if (dueToday.isEmpty &&
        pastDue.isEmpty &&
        later.isEmpty &&
        noDue.isEmpty &&
        done.isEmpty) {
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
            label: l.allPastDueSection,
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
        if (done.isNotEmpty) ...[
          _groupHead(
            label: l.completedTodaySection,
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
    List<Todo> noDateTodos,
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
    final openTodo = widget.onOpenTodo;
    final hasNoContent =
        allocations.isEmpty && due.isEmpty && noDateTodos.isEmpty;

    return ListView(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 0, desktop ? 8 : 14, desktop ? 28 : 0, 118),
      children: [
        _bgBand(l, events, desktop),
        if (hasNoContent)
          A2Empty(title: l.emptyDateTitle, hint: l.emptyDateHint),
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
                onTap: () => _selectMode(const TodosInboxView()),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (widget.onOpenEvent != null && item.event != null) {
            widget.onOpenEvent!(item.event!);
          }
        },
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
    final parts = <Widget>[];
    final name = names[todo.calendarId];
    if (name != null && name.isNotEmpty) {
      parts.add(A2MetaText(name));
    } else {
      parts.add(A2MetaText(l.inbox));
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
      final name = names[todo.calendarId];
      if (name != null && name.isNotEmpty) {
        parts.add(const A2Sep());
        parts.add(A2MetaText(name));
      }
      return parts;
    }
    final name = names[todo.calendarId];
    if (name != null && name.isNotEmpty) {
      parts.add(A2MetaText(name));
    } else {
      parts.add(A2MetaText(l.inbox));
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
    return parts;
  }

  List<Widget> _deadlineMeta(AppLocalizations l, DayItem item) {
    if (item.completed) {
      return [A2MetaText(l.completed)];
    }
    return const [];
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
        ),
      ),
    );
  }
}

