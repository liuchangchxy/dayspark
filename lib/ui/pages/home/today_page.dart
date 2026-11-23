import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/utils/capture_parser.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/pages/todo/a2_composer.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/undo_bar.dart';

/// 今天: the real today, drawn as four time sections and an unplanned shelf.
///
/// It never reads a browsed date — the header is a read-only clock, and the
/// only creation entry is the capture row, which writes a bare Todo.
class A2TodayPage extends ConsumerStatefulWidget {
  const A2TodayPage({
    super.key,
    required this.now,
    required this.onOpenTodo,
    required this.onOpenEvent,
    required this.onToggleTodo,
    required this.onOpenUnplanned,
    required this.onScheduleTodo,
    this.initialDraft = '',
  });

  final DateTime now;
  final ValueChanged<Todo> onOpenTodo;
  final ValueChanged<CalendaEventAdapter> onOpenEvent;
  /// Returns whether the write actually happened: dismissing the occurrence
  /// picker is not a completion, and the row must not claim one.
  final Future<bool> Function(Todo todo, String? occurrenceId, bool completed)
  onToggleTodo;
  final VoidCallback onOpenUnplanned;
  final ValueChanged<Todo> onScheduleTodo;
  final String initialDraft;

  @override
  ConsumerState<A2TodayPage> createState() => _A2TodayPageState();
}

class _A2TodayPageState extends ConsumerState<A2TodayPage> {
  final ScrollController _scroll = ScrollController();
  int? _recentId;
  Timer? _recentTimer;
  bool _overdueExpanded = false;
  bool _unplannedExpanded = false;
  bool _upcomingExpanded = false;
  bool _completedExpanded = false;
  bool _endedExpanded = false;
  bool _desktopEndedExpanded = false;
  bool _toastVisible = false;
  Timer? _toastTimer;
  bool _capturing = false;
  bool _captureFocused = false;
  late String _captureDraft = widget.initialDraft;
  double? _lastViewport;
  A2CaptureState _desktopCaptureState = A2CaptureState.compact;
  late final TextEditingController _desktopCaptureController =
      TextEditingController(text: widget.initialDraft);
  final FocusNode _desktopCaptureFocusNode = FocusNode();

  String _formatDueLabel(
    AppLocalizations l,
    DateTime? dueDate, {
    bool isOverdue = false,
  }) {
    if (dueDate == null) return isOverdue ? l.sectionOverdueLabel : '';
    if (isOverdue) {
      final dDue = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final dNow = DateTime(widget.now.year, widget.now.month, widget.now.day);
      final days = dNow.difference(dDue).inDays;
      if (days > 0) return l.overdueDays(days);
    }
    return formatDueLabel(l, dueDate, widget.now);
  }

  /// The one row that was just completed and can still be undone. It is kept
  /// rendered in its own section for five seconds even after the projection
  /// drops it, so a tick never makes the row jump away from under the finger.
  _RecentCompletion? _recent;
  Timer? _undoTimer;
  final GlobalKey _undoButtonKey = GlobalKey();
  final GlobalKey _shelfKey = GlobalKey();
  final GlobalKey _shelfBottomKey = GlobalKey();

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  String get _locale => Localizations.localeOf(context).toString();

  static int isoWeekNumber(DateTime date) {
    final thursday = DateTime(date.year, date.month, date.day + (4 - date.weekday));
    final firstThursdayOfYear = DateTime(thursday.year, 1, 4);
    final firstThursday = DateTime(thursday.year, 1, 4 + (4 - firstThursdayOfYear.weekday));
    return 1 + (thursday.difference(firstThursday).inDays ~/ 7);
  }

  /// The keyboard arrives one or more frames after focus, and the Scaffold
  /// reserves its space by shrinking the body rather than by leaving an inset
  /// for this page to read. The shelf therefore follows the list's own
  /// viewport: when it shrinks under a focused capture row, the group the row
  /// feeds is scrolled back above it.
  void _onViewportChanged(ScrollMetrics metrics) {
    final previous = _lastViewport;
    _lastViewport = metrics.viewportDimension;
    if (!_captureFocused) return;
    // A list that first appears while the capture row is focused already sits
    // under the keyboard, so there is no shrink to notice: take its first
    // metrics as the moment to bring the shelf up.
    final shrank = previous != null && metrics.viewportDimension < previous;
    if (!shrank && previous != null) return;
    if (metrics.extentAfter <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToShelf());
  }

  void _scrollToShelf() {
    if (!mounted || !_scroll.hasClients) return;
    final ctx = _shelfKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _desktopCaptureController.dispose();
    _desktopCaptureFocusNode.dispose();
    _recentTimer?.cancel();
    _toastTimer?.cancel();
    _undoTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _capture(String text) async {
    if (_capturing) return false;
    final l = AppLocalizations.of(context)!;
    _capturing = true;
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        _showToast(l.noCalendar);
        return false;
      }
      final id = await ref.read(createTodoProvider)(
        calendarId:
            resolveNewEntryCalendarId(
              calendars: calendars,
              preferredId: ref.read(defaultCalendarIdProvider),
            ) ??
            calendars.first.id,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
      );
      if (!mounted) return true;
      setState(() {
        _recentId = id;
        _unplannedExpanded = false;
      });
      _recentTimer?.cancel();
      _recentTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _recentId = null);
      });
      _showToast(l.captureAddedToast);
      if (_scroll.hasClients) {
        final ctx = _shelfKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      }
      return true;
    } catch (error) {
      debugPrint('today: capture failed: $error');
      if (mounted) _showToast(l.actionFailedRetry);
      return false;
    } finally {
      _capturing = false;
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() {
      _lastToast = message;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  String _lastToast = '';

  String _keyOf(int todoId, String? occurrenceId) =>
      '$todoId:${occurrenceId ?? ''}';

  bool _recentMatches(int todoId, String? occurrenceId) {
    final recent = _recent;
    if (recent == null) return false;
    return _keyOf(recent.todo.id, recent.occurrenceId) ==
        _keyOf(todoId, occurrenceId);
  }

  /// An occurrence id is `v2:DATE:2026-10-06` / `v2:LOCAL:2026-10-06T12:00:00`;
  /// the undo key reads out the nominal anchor, the same text the row's meta
  /// prints, so "Undo · 2026-10-06" says which occurrence is being rolled back.
  String? _occurrenceLabel(String? occurrenceId) {
    if (occurrenceId == null) return null;
    final match = RegExp(r'^v2:[A-Z]+:(.+)$').firstMatch(occurrenceId);
    final value = match?.group(1);
    if (value == null || value.isEmpty) return null;
    return value.replaceFirst('T', '  ');
  }

  String _undoLabel(AppLocalizations l, String? occurrenceId) {
    if (occurrenceId == null) return l.undo;
    final label = _occurrenceLabel(occurrenceId);
    if (label == null || label.isEmpty) return l.undo;
    return l.undoOccurrence(label);
  }

  Future<void> _toggleItem(DayItem item, _RecentSection section, int index) {
    final todo = item.todo!;
    if (_recentMatches(todo.id, item.occurrenceId)) {
      return _setCompleted(todo, item.occurrenceId, false);
    }
    return _setCompleted(
      todo,
      item.occurrenceId,
      todo.status != 'COMPLETED',
      item: item,
      section: section,
      index: index,
    );
  }

  Future<void> _toggleUnplanned(Todo todo, int index) {
    if (_recentMatches(todo.id, null)) {
      return _setCompleted(todo, null, false);
    }
    return _setCompleted(
      todo,
      null,
      true,
      section: _RecentSection.unplanned,
      index: index,
    );
  }

  Future<void> _completeMissed(_MissedCardData card) async {
    _clearUndo();
    final occurrenceId = card.latest?.occurrenceId;
    await _setCompleted(card.todo, occurrenceId, true);
  }

  /// Every completion goes through the one callback the page was handed, so
  /// the undo action is the same write path (and keeps the occurrence id).
  Future<void> _setCompleted(
    Todo todo,
    String? occurrenceId,
    bool completed, {
    DayItem? item,
    _RecentSection? section,
    int index = 0,
  }) async {
    try {
      final changed = await widget.onToggleTodo(todo, occurrenceId, completed);
      if (!changed) return;
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
      return;
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    if (l == null) return;
    // R5: completion is one fact every surface shares. Re-read the projection
    // in place instead of waiting for the user to leave and come back.
    _retryProjection();
    if (completed) {
      _startUndo(
        l,
        todo,
        occurrenceId,
        item: item,
        section: section ?? _RecentSection.unplanned,
        index: index,
      );
      showUndoBar(
        context,
        message: l.markedCompleted(todo.summary),
        undoLabel: l.undo,
        onUndo: () => _setCompleted(todo, occurrenceId, false),
      );
    } else {
      _clearUndo();
      if (!isWorkspaceLayout(context)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l.openTask)),
        );
      }
    }
  }

  void _startUndo(
    AppLocalizations l,
    Todo todo,
    String? occurrenceId, {
    DayItem? item,
    required _RecentSection section,
    required int index,
  }) {
    _undoTimer?.cancel();
    setState(() {
      _recent = _RecentCompletion(
        todo: todo,
        occurrenceId: occurrenceId,
        label: _undoLabel(l, occurrenceId),
        section: section,
        index: index,
        completedAt: DateTime.now(),
        item: item,
      );
    });
    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _recent = null);
    });
  }

  void _clearUndo() {
    if (_recent == null) return;
    _undoTimer?.cancel();
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
    setState(() => _recent = null);
  }

  ({int overdue, int due, int noDue, int done}) _summaryCounts(
    ActionProjectionData? projection,
    List<Todo> unplanned,
  ) {
    final recent = _recent;
    final recentKey = recent == null
        ? null
        : _keyOf(recent.todo.id, recent.occurrenceId);
    final completedTodos = projection?.completedTodayTodos ?? const <Todo>[];
    final completedInstances =
        projection?.completedTodayTaskInstances ??
        const <ProjectedTaskInstance>[];
    final recentCompleted =
        recent != null &&
        (recent.occurrenceId == null
            ? completedTodos.any((todo) => todo.id == recent.todo.id)
            : completedInstances.any(
                (instance) =>
                    _keyOf(instance.todo.id, instance.occurrenceId) ==
                    recentKey,
              ));
    final missedSeries = <int>{
      for (final instance
          in projection?.missedTaskInstances ??
              const <ProjectedTaskInstance>[])
        if (_keyOf(instance.todo.id, instance.occurrenceId) != recentKey)
          instance.todo.id,
      for (final todo
          in projection?.earlierMissedSeries ?? const <Todo>[])
        todo.id,
    };
    final recentTodoId = recent?.occurrenceId == null ? recent?.todo.id : null;
    final overdueCount = (projection?.overdueTodos ?? const <Todo>[])
            .where((todo) => todo.id != recentTodoId)
            .length +
        missedSeries.length;
    final dueCount = (projection?.dueTodayTodos ?? const <Todo>[])
        .where((todo) => todo.id != recentTodoId)
        .length;
    final noDueCount = unplanned
        .where(
          (todo) =>
              todo.dueDate == null &&
              !missedSeries.contains(todo.id) &&
              todo.id != recentTodoId,
        )
        .length;
    final doneCount =
        completedTodos.length +
        completedInstances.length +
        (recent != null && !recentCompleted ? 1 : 0);
    return (
      overdue: overdueCount,
      due: dueCount,
      noDue: noDueCount,
      done: doneCount,
    );
  }

  void _openTodo(Todo todo) {
    _clearUndo();
    widget.onOpenTodo(todo);
  }

  void _openEvent(CalendaEventAdapter event) {
    _clearUndo();
    widget.onOpenEvent(event);
  }

  void _scheduleTodo(Todo todo) {
    _clearUndo();
    widget.onScheduleTodo(todo);
  }

  Future<bool> _openCaptureComposer(String? title) async {
    _clearUndo();
    final text = title?.trim() ?? '';
    final parsed = text.isEmpty
        ? emptyCaptureDraft
        : parseCapture(text, DateTime.now());
    final saved = await showA2Composer(
      context,
      contextDate: widget.now,
      initialTitle: text.isEmpty ? null : text,
      initialStart: parsed.start,
      initialEnd: parsed.end,
    );
    if (!saved || !mounted) return false;
    _desktopCaptureController.clear();
    setState(() => _captureDraft = '');
    return true;
  }

  /// Any press outside the undo key closes the window: the key is a one-shot
  /// offer, not a persistent state. The key itself is excluded by hit test,
  /// otherwise the press that should undo would dismiss the button first.
  void _onListPointerDown(PointerDownEvent event) {
    if (_recent == null) return;
    final ctx = _undoButtonKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final local = box.globalToLocal(event.position);
        if ((Offset.zero & box.size).contains(local)) return;
      }
    }
    _clearUndo();
  }

  Widget _undoAction(_RecentCompletion recent) {
    final ds = context.ds;
    final desktop = isWorkspaceLayout(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: _undoButtonKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => _setCompleted(recent.todo, recent.occurrenceId, false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                recent.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: desktop ? const Color(0xFF6B9EFF) : ds.primary,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _retryProjection() {
    ref.invalidate(actionProjectionProvider);
    ref.invalidate(pendingTodosProvider);
    ref.invalidate(unplannedTodosProvider);
    ref.invalidate(allActiveTaskAllocationsProvider);
    ref.invalidate(actionDueTodayTodosProvider);
    ref.invalidate(actionOverdueTodosProvider);
    ref.invalidate(actionCompletedTodayTodosProvider);
    ref.invalidate(actionActiveRecurringTodosProvider);
    ref.invalidate(actionAllNotDeletedTodosProvider);
    ref.invalidate(actionTaskInstanceStatesProvider);
    ref.invalidate(eventCandidatesInDateRangeProvider);
    ref.invalidate(taskAllocationsInDateRangeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final data = ref.watch(actionProjectionProvider);
    final unplannedAsync = ref.watch(unplannedTodosProvider);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final names = {for (final c in calendars) c.id: c.name};
    final colors = {
      for (final c in calendars) c.id: ColorUtils.parseHex(c.color),
    };

    // The head, the clock and the capture row are the page, not the data:
    // they stay put while the projection loads or after it fails.
    final projection = data.valueOrNull;
    final agenda = DayAgenda.build(
      day: _today,
      events: projection?.events ?? const [],
      allocations: projection?.allocations ?? const [],
      dueTodos: projection?.dueTodayTodos ?? const [],
      overdueTodos: projection?.overdueTodos ?? const [],
      instances: projection?.todayTaskInstances ?? const [],
      calendarNames: names,
      calendarColors: colors,
    );
    final unplanned = unplannedAsync.valueOrNull ?? const <Todo>[];
    return desktop
        ? _desktop(l, data, agenda, unplanned)
        : _mobile(l, data, agenda, unplanned);
  }

  /// The list slot: a spinner while the first value is on its way, the typed
  /// failure if it never arrives, the list itself once there is data.
  Widget _listSlot(
    AppLocalizations l,
    AsyncValue<ActionProjectionData> data,
    Widget list,
  ) {
    if (data.hasError && !data.hasValue) {
      debugPrint('today: projection error: ${data.error}');
      return _errorState(l);
    }
    if (data.isLoading && !data.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data.hasError) {
      // A previous value is still holdable, so the page degrades to the stale
      // list plus a retry strip instead of wiping the day to an error box.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _retryStrip(l),
          Expanded(child: list),
        ],
      );
    }
    return list;
  }

  Widget _errorState(AppLocalizations l) {
    final ds = context.ds;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 24,
              color: ds.ink3,
            ),
            const SizedBox(height: 8),
            Text(
              l.actionFailedRetry,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ds.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _retryProjection, child: Text(l.retry)),
          ],
        ),
      ),
    );
  }

  Widget _retryStrip(AppLocalizations l) {
    final ds = context.ds;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      decoration: BoxDecoration(
        color: ds.warnSoft,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.actionFailedRetry,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: ds.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          TextButton(onPressed: _retryProjection, child: Text(l.retry)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- mobile

  Widget _mobile(
    AppLocalizations l,
    AsyncValue<ActionProjectionData> data,
    DayAgenda agenda,
    List<Todo> unplanned,
  ) {
    final projection = data.valueOrNull;
    final plannedTodoIds = <int>{
      for (final a in agenda.allocations)
        if (a.todo != null) a.todo!.id,
    };

    final noDue = <Todo>[
      for (final todo in unplanned)
        if (todo.dueDate == null && !plannedTodoIds.contains(todo.id)) todo,
    ];
    final shelfSource = _injectRecentTodos(noDue, _RecentSection.unplanned);
    final noDueCount = noDue.length;
    final shownUnplanned = _unplannedExpanded
        ? shelfSource
        : shelfSource.take(3).toList();
    final expandableUnplanned = shelfSource.length - shownUnplanned.length;

    final allCompletedTodos = projection?.completedTodayTodos ?? const <Todo>[];
    final allCompletedInstances =
        projection?.completedTodayTaskInstances ??
        const <ProjectedTaskInstance>[];
    final recent = _recent;
    final recentKey = recent == null
        ? null
        : _keyOf(recent.todo.id, recent.occurrenceId);
    final completedTodos = recentKey == null
        ? allCompletedTodos
        : [
            for (final todo in allCompletedTodos)
              if (_keyOf(todo.id, null) != recentKey) todo,
          ];
    final completedInstances = recentKey == null
        ? allCompletedInstances
        : [
            for (final instance in allCompletedInstances)
              if (_keyOf(instance.todo.id, instance.occurrenceId) != recentKey)
                instance,
          ];

    final visibleCompletedTodos = [
      for (final todo in completedTodos)
        if (!plannedTodoIds.contains(todo.id)) todo,
    ];
    final visibleCompletedInstances = [
      for (final instance in completedInstances)
        if (!plannedTodoIds.contains(instance.todo.id)) instance,
    ];
    final completedCount =
        visibleCompletedTodos.length + visibleCompletedInstances.length;

    final overdueItems = _injectRecentDayItems(
      agenda.overdueTodos,
      _RecentSection.overdue,
    );
    final visibleOverdue = [
      for (final item in overdueItems)
        if (item.todo != null && !plannedTodoIds.contains(item.todo!.id)) item,
    ];

    final dueItems = _injectRecentDayItems(
      agenda.dueTodos,
      _RecentSection.dueToday,
    );
    final visibleDue = [
      for (final item in dueItems)
        if (item.todo != null && !plannedTodoIds.contains(item.todo!.id)) item,
    ];

    final missedCards = _missedCards(projection, plannedTodoIds);

    final timed = agenda.timed;
    bool isRunning(DayItem item) {
      final start = item.start;
      final end = item.end;
      if (start == null || end == null || item.allDay) return false;
      return !start.isAfter(widget.now) && end.isAfter(widget.now);
    }

    final running = timed.where(isRunning).toList();
    final rest = timed
        .where((item) => !item.allDay && !isRunning(item) && !_hasEnded(item))
        .toList();
    final ended = timed.where(_hasEnded).toList();
    final endedItems = _injectRecentDayItems(ended, _RecentSection.ended);
    final runningItems = _injectRecentDayItems(running, _RecentSection.now);

    final upcoming = <({DayItem item, bool instance})>[
      for (final item in rest)
        if (!item.allDay) (item: item, instance: false),
      for (final instance in agenda.instances) (item: instance, instance: true),
    ];
    final upcomingItems = _injectRecentUpcoming(upcoming);
    final shownUpcoming = _upcomingExpanded
        ? upcomingItems
        : upcomingItems.take(3).toList();
    final upcomingHidden = upcomingItems.length - shownUpcoming.length;

    final allDayEvents = agenda.events.where((e) => e.allDay).toList();

    final hasTimeItems = allDayEvents.isNotEmpty ||
        endedItems.isNotEmpty ||
        runningItems.isNotEmpty ||
        upcomingItems.isNotEmpty;

    final counts = _summaryCounts(projection, unplanned);
    final isPageEmpty = _recent == null &&
        counts.overdue == 0 &&
        counts.due == 0 &&
        counts.noDue == 0 &&
        counts.done == 0 &&
        !hasTimeItems;

    final summary = isPageEmpty
        ? l.emptyTodayTitle
        : '${counts.overdue} ${l.todaySummaryOverdue} · ${counts.due} ${l.sectionDueToday} · ${counts.noDue} ${l.todayNoDateGroup} · ${counts.done} ${l.completed}';

    final mobileContentHeader = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.MMMd(_locale).format(widget.now),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              fontVariations: [FontVariation('wght', 650)],
              letterSpacing: 0.26,
              height: 1.22,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${DateFormat.E(_locale).format(widget.now)} · ${l.weekNumberLabel(isoWeekNumber(widget.now))}',
            style: const TextStyle(
              fontSize: 10.5,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          if (!isPageEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              style: const TextStyle(
                fontSize: 9.5,
                color: SpecTokens.faint,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ],
        ],
      ),
    );

    final children = <Widget>[
      mobileContentHeader,
      if (plannedTodoIds.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(19, 4, 19, 4),
          child: Text(
            l.plannedTodosMovedToTimeline(plannedTodoIds.length),
            style: const TextStyle(
              fontSize: 10,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      for (final card in missedCards) _missedCard(l, card),
      if (visibleOverdue.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _groupHead(
            label: l.sectionOverdueLabel,
            count: visibleOverdue.length,
            danger: true,
          ),
        ),
        for (var i = 0;
            i <
                (_overdueExpanded
                    ? visibleOverdue.length
                    : (visibleOverdue.length > 3 ? 3 : visibleOverdue.length));
            i++)
          _taskRow(
            key: ValueKey('overdue-${visibleOverdue[i].todo!.id}'),
            title: visibleOverdue[i].title,
            checked: visibleOverdue[i].completed,
            isOverdue: true,
            dueLabel: _formatDueLabel(l, visibleOverdue[i].todo?.dueDate, isOverdue: true),
            calendarName: visibleOverdue[i].calendarName,
            calendarColor: visibleOverdue[i].calendarColor,
            rrule: visibleOverdue[i].todo?.rrule,
            highlighted: visibleOverdue[i].todo?.id == _recentId,
            trailing: _undoFor(visibleOverdue[i].todo?.id, visibleOverdue[i].occurrenceId, _RecentSection.overdue),
            onToggle: (_) => _toggleItem(visibleOverdue[i], _RecentSection.overdue, i),
            onTap: () => _openTodo(visibleOverdue[i].todo!),
            onSchedule: () => _scheduleTodo(visibleOverdue[i].todo!),
          ),
        if (!_overdueExpanded && visibleOverdue.length > 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _moreRow(
              l,
              visibleOverdue.length,
              label: l.viewAllNItems(visibleOverdue.length),
              paddingLeft: 33,
              expanded: false,
              onTap: () => setState(() => _overdueExpanded = true),
            ),
          )
        else if (_overdueExpanded && visibleOverdue.length > 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _moreRow(
              l,
              0,
              paddingLeft: 33,
              expanded: true,
              onTap: () => setState(() => _overdueExpanded = false),
            ),
          ),
      ],
      if (visibleDue.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _groupHead(
            label: l.sectionDueToday,
            count: visibleDue.length,
          ),
        ),
        for (var i = 0; i < visibleDue.length && i < 2; i++)
          _taskRow(
            key: ValueKey('due-${visibleDue[i].todo!.id}'),
            title: visibleDue[i].title,
            checked: visibleDue[i].completed,
            isOverdue: false,
            dueLabel: _formatDueLabel(l, visibleDue[i].todo?.dueDate),
            calendarName: visibleDue[i].calendarName,
            calendarColor: visibleDue[i].calendarColor,
            rrule: visibleDue[i].todo?.rrule,
            highlighted: visibleDue[i].todo?.id == _recentId,
            trailing: _undoFor(visibleDue[i].todo?.id, visibleDue[i].occurrenceId, _RecentSection.dueToday),
            onToggle: (_) => _toggleItem(visibleDue[i], _RecentSection.dueToday, i),
            onTap: () => _openTodo(visibleDue[i].todo!),
            onSchedule: () => _scheduleTodo(visibleDue[i].todo!),
          ),
      ],
      if (shelfSource.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _groupHead(
            key: _shelfKey,
            label: l.todayNoDateGroup,
            count: noDueCount,
            trailing: const Icon(
              CupertinoIcons.chevron_up,
              size: 11,
              color: SpecTokens.faint,
            ),
            onToggle: widget.onOpenUnplanned,
          ),
        ),
        for (final todo in shownUnplanned)
          _taskRow(
            key: ValueKey('unplanned-${todo.id}'),
            title: todo.summary,
            checked: todo.status == 'COMPLETED',
            calendarName: _calendarName(todo),
            calendarColor: _calendarColor(todo),
            rrule: todo.rrule,
            highlighted: todo.id == _recentId,
            trailing: _undoFor(todo.id, null, _RecentSection.unplanned),
            onToggle: (_) => _toggleUnplanned(todo, 0),
            onTap: () => _openTodo(todo),
            onSchedule: () => _scheduleTodo(todo),
          ),
        if (expandableUnplanned > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _moreRow(
              l,
              expandableUnplanned,
              label: l.expandRemaining(expandableUnplanned),
              paddingLeft: 12,
              expanded: _unplannedExpanded,
              onTap: () => setState(() => _unplannedExpanded = !_unplannedExpanded),
            ),
          )
        else if (_unplannedExpanded && shelfSource.length > 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _moreRow(
              l,
              0,
              paddingLeft: 12,
              expanded: true,
              onTap: () => setState(() => _unplannedExpanded = false),
            ),
          ),
        KeyedSubtree(
          key: _shelfBottomKey,
          child: const SizedBox.shrink(),
        ),
      ],
      if (completedCount > 0) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _groupHead(
            label: l.completedTodaySection,
            count: completedCount,
            expanded: _completedExpanded,
            onToggle: () => setState(() => _completedExpanded = !_completedExpanded),
          ),
        ),
        if (_completedExpanded) ...[
          for (final todo in visibleCompletedTodos)
            _taskRow(
              key: ValueKey('completed-${todo.id}'),
              title: todo.summary,
              checked: true,
              calendarName: _calendarName(todo),
              calendarColor: _calendarColor(todo),
              rrule: todo.rrule,
              onToggle: (_) => _setCompleted(todo, null, false),
              onTap: () => _openTodo(todo),
            ),
          for (final instance in visibleCompletedInstances)
            _taskRow(
              key: ValueKey('completed-inst-${instance.occurrenceId}'),
              title: instance.todo.summary,
              checked: true,
              calendarName: _calendarName(instance.todo),
              calendarColor: _calendarColor(instance.todo),
              rrule: instance.todo.rrule,
              onToggle: (_) => _setCompleted(instance.todo, instance.occurrenceId, false),
              onTap: () => _openTodo(instance.todo),
              onSchedule: () => _scheduleTodo(instance.todo),
            ),
        ],
      ],
      if (allDayEvents.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SpecAlldayStrip(
            label: l.allDayLabel,
            items: [
              for (final ev in allDayEvents)
                SpecAlldayItem(
                  title: ev.title,
                  barColor: ev.calendarColor,
                  bgColor: ev.calendarColor?.withValues(alpha: 0.12),
                  onTap: () => _openEvent(ev.event!),
                ),
            ],
          ),
        ),
      if (endedItems.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _groupHead(
            label: l.actionEarlierToday,
            count: endedItems.length,
            expanded: _endedExpanded,
            onToggle: () => setState(() => _endedExpanded = !_endedExpanded),
          ),
        ),
        if (_endedExpanded)
          for (var i = 0; i < endedItems.length; i++)
            _mobileTimeRow(endedItems[i], isQuiet: true, section: _RecentSection.ended, index: i),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _groupHead(
          label: l.sectionNow,
          danger: true,
          trailing: Text(
            DateFormatters.formatTime(widget.now),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: SpecTokens.red,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ),
      for (var i = 0; i < runningItems.length; i++)
        _mobileTimeRow(runningItems[i], section: _RecentSection.now, index: i),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SpecNowLine(marginLeft: 42.0),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _groupHead(
          label: l.sectionUpcoming,
          count: upcomingItems.length,
          expanded: _upcomingExpanded,
          onToggle: upcomingItems.length > 3
              ? () => setState(() => _upcomingExpanded = !_upcomingExpanded)
              : null,
        ),
      ),
      for (var i = 0; i < shownUpcoming.length; i++)
        _mobileTimeRow(
          shownUpcoming[i].item,
          section: _RecentSection.upcoming,
          index: i,
        ),
      if (upcomingHidden > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _moreRow(
            l,
            upcomingHidden,
            paddingLeft: 42,
            expanded: _upcomingExpanded,
            onTap: () => setState(() => _upcomingExpanded = !_upcomingExpanded),
          ),
        )
      else if (_upcomingExpanded && upcomingItems.length > 3)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _moreRow(
            l,
            0,
            paddingLeft: 42,
            expanded: true,
            onTap: () => setState(() => _upcomingExpanded = false),
          ),
        ),
      const SizedBox(height: 80),
    ];

    final listContent = isPageEmpty
        ? ListView(
            key: const ValueKey('a2-today-list'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            children: [
              mobileContentHeader,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 12),
                child: Center(
                  child: Text(
                    l.emptyTodayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ),
            ],
          )
        : NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              _onViewportChanged(notification.metrics);
              return false;
            },
            child: Listener(
              onPointerDown: _onListPointerDown,
              child: ListView(
                key: const ValueKey('a2-today-list'),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
                children: children,
              ),
            ),
          );

    return Listener(
      onPointerDown: _onListPointerDown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpecMobileTopBar(
            title: l.today,
            searchTooltip: l.search,
            onSearch: () => context.push('/search'),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _listSlot(l, data, listContent),
                ),
                if (_toastVisible && _lastToast.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(child: _Toast(label: _lastToast)),
                  ),
              ],
            ),
          ),
          A2CaptureBar(
            fieldKey: const ValueKey('today-capture-field'),
            placeholder: l.capturePlaceholder,
            hint: _captureFocused
                ? l.captureHintSubmit
                : (isWorkspaceLayout(context) ? l.captureHintEnter : ''),
            initialDraft: _captureDraft,
            onDraftChanged: (draft) => _captureDraft = draft,
            onSubmit: _capture,
            onExpand: () {
              _openCaptureComposer(_captureDraft);
            },
            onParsedSubmit: _openCaptureComposer,
            onFocusChange: (focused) {
              if (_captureFocused != focused) {
                setState(() => _captureFocused = focused);
              }
              if (focused) {
                _clearUndo();
                _scrollToShelf();
              }
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- desktop

  Widget _zoneLabel(String label) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: SpecTokens.hair,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHead({
    Key? key,
    required String label,
    int? count,
    bool danger = false,
    bool expanded = false,
    VoidCallback? onToggle,
    Widget? trailing,
  }) {
    final content = Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 31),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      margin: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: danger ? SpecTokens.red : SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: danger ? const Color(0xFFC98078) : SpecTokens.faint,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null)
            trailing
          else if (onToggle != null)
            Icon(
              expanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
              size: 11,
              color: SpecTokens.faint,
            ),
        ],
      ),
    );
    if (onToggle != null) {
      return FocusableTap(
        onTap: onToggle,
        semanticsLabel: label,
        borderRadius: BorderRadius.circular(4),
        child: content,
      );
    }
    return content;
  }

  Widget _desktopHead(
    AppLocalizations l,
    DayAgenda agenda,
    ({int overdue, int due, int noDue, int done}) counts,
  ) {
    final isEmpty = counts.overdue == 0 &&
        counts.due == 0 &&
        counts.noDue == 0 &&
        counts.done == 0 &&
        agenda.events.isEmpty &&
        agenda.allocations.isEmpty;

    final summary = isEmpty
        ? l.emptyTodayTitle
        : '${counts.overdue} ${l.todaySummaryOverdue} · ${counts.due} ${l.sectionDueToday} · ${counts.noDue} ${l.todayNoDateGroup} · ${counts.done} ${l.completed}';

    final weekText = l.weekNumberLabel(isoWeekNumber(widget.now));
    final dateTitle = DateFormat.MMMd(_locale).format(widget.now);
    final dateSub = '${DateFormat.E(_locale).format(widget.now)} · $weekText';

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 13),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      dateTitle,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        fontVariations: [FontVariation('wght', 650)],
                        letterSpacing: 0.26,
                        height: 1.22,
                        color: SpecTokens.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      dateSub,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: SpecTokens.muted,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: SpecTokens.faint,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitDesktopCapture() async {
    final text = _desktopCaptureController.text.trim();
    if (text.isEmpty) return;
    final parsed = parseCapture(text, DateTime.now());
    if (parsed.start != null) {
      await _openCaptureComposer(text);
      return;
    }
    final saved = await _capture(text);
    if (!mounted || !saved) return;
    // A failed write keeps the sentence exactly where the user typed it.
    if (_desktopCaptureController.text.trim() != text) return;
    _desktopCaptureController.clear();
    setState(() => _captureDraft = '');
  }

  Widget _desktopCaptureBar(AppLocalizations l) {
    return Positioned(
      bottom: 18,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 560,
          height: 54,
          padding: const EdgeInsets.fromLTRB(15, 0, 8, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: const Color(0xFFE1E1D9), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(25, 25, 24, 0.08),
                blurRadius: 28,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 25,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: SpecTokens.wash,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.checkmark_alt, size: 10, color: SpecTokens.muted),
                    const SizedBox(width: 4),
                    Text(
                      l.captureTypeTodo,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: SpecTokens.ink2,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l.captureDefaultDate,
                style: const TextStyle(
                  fontSize: 10,
                  color: SpecTokens.faint,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('desktop-capture-input'),
                  controller: _desktopCaptureController,
                  focusNode: _desktopCaptureFocusNode,
                  decoration: InputDecoration(
                    hintText: l.captureInputPlaceholder,
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: SpecTokens.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                  onSubmitted: (_) => _submitDesktopCapture(),
                  onChanged: (val) => _captureDraft = val,
                ),
              ),
              const Text(
                '↵',
                style: TextStyle(
                  fontSize: 12,
                  color: SpecTokens.faint,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                key: const ValueKey('desktop-capture-expand-btn'),
                onTap: () {
                  _openCaptureComposer(_desktopCaptureController.text);
                },
                borderRadius: BorderRadius.circular(17),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SpecTokens.ink,
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.plus,
                      size: 15,
                      color: Colors.white,
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

  Widget _taskRow({
    Key? key,
    required String title,
    bool checked = false,
    bool isOverdue = false,
    String? dueLabel,
    String? calendarName,
    Color? calendarColor,
    String? rrule,
    int? missedCount,
    ValueChanged<bool>? onToggle,
    VoidCallback? onTap,
    VoidCallback? onSchedule,
    Widget? trailing,
    bool highlighted = false,
    String? planLabel,
    bool showCheck = true,
  }) {
    final l = AppLocalizations.of(context)!;
    final meta = buildSharedRowMeta(
      context,
      calendarName: calendarName,
      calendarColor: calendarColor,
      rrule: rrule,
      missedCount: missedCount,
      planLabel: planLabel,
    );

    if (!isWorkspaceLayout(context)) {
      return _mobileTaskRow(
        key: key,
        title: title,
        checked: checked,
        isOverdue: isOverdue,
        dueLabel: dueLabel,
        meta: meta,
        onToggle: onToggle,
        onTap: onTap,
        onSchedule: onSchedule,
        scheduleTooltip: l.scheduleAction,
        trailing: trailing,
        highlighted: highlighted,
        showCheck: showCheck,
      );
    }

    return SpecTaskRow(
      key: key,
      title: title,
      checked: checked,
      isOverdue: isOverdue,
      dueLabel: dueLabel,
      meta: meta,
      onToggle: onToggle,
      onTap: onTap,
      onSchedule: onSchedule,
      scheduleTooltip: l.scheduleAction,
      trailing: trailing,
      selected: highlighted,
      showCheck: showCheck,
    );
  }

  Widget _mobileTaskRow({
    Key? key,
    required String title,
    bool checked = false,
    bool isOverdue = false,
    String? dueLabel,
    List<Widget> meta = const [],
    ValueChanged<bool>? onToggle,
    VoidCallback? onTap,
    VoidCallback? onSchedule,
    Widget? trailing,
    bool highlighted = false,
    bool showCheck = true,
    String? scheduleTooltip,
  }) {
    final visualRow = Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted ? SpecTokens.hair : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF3F3EE), width: 1.0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 22,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: checked ? SpecTokens.faint : SpecTokens.ink,
                    decoration: checked ? TextDecoration.lineThrough : null,
                    decorationColor: SpecTokens.faint,
                    fontFamilyFallback: AppTypography.fallback,
                    height: 1.35,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                    child: SizedBox(
                      height: 16,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: double.infinity,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: meta,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (dueLabel != null && dueLabel.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 1.5,
              ),
              decoration: BoxDecoration(
                color: isOverdue ? const Color(0x1AEA5545) : SpecTokens.wash,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                dueLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: isOverdue ? SpecTokens.red : SpecTokens.muted,
                  fontFeatures: AppTypography.tabular,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing,
          ],
          if (onSchedule != null) ...[
            const SizedBox(width: 4),
            const SizedBox(
              width: 32,
              height: 36,
              child: Center(
                child: Icon(
                  CupertinoIcons.calendar,
                  size: 13,
                  color: SpecTokens.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Stack(
      key: key,
      children: [
        FocusableTap(
          onTap: onTap,
          semanticsLabel: title,
          child: visualRow,
        ),
        if (showCheck)
          Positioned(
            left: 3,
            top: 0,
            bottom: 0,
            width: 48,
            child: Center(
              child: SpecCheck(
                checked: checked,
                onChanged: onToggle,
                label: title,
                touchTargetSize: 48,
              ),
            ),
          ),
        if (onSchedule != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 54,
            child: Tooltip(
              message: scheduleTooltip ?? '',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSchedule,
              ),
            ),
          ),
      ],
    );
  }

  Widget _mobileTimeRow(
    DayItem item, {
    bool isQuiet = false,
    _RecentSection section = _RecentSection.now,
    int index = 0,
  }) {
    final l = AppLocalizations.of(context)!;
    final isPlan = item.kind == DayItemKind.allocation;
    final isPlanOrInstance = item.kind == DayItemKind.allocation || item.kind == DayItemKind.instance;
    final isSeries = item.todo?.rrule != null && item.todo!.rrule!.isNotEmpty;
    final timeStr = item.start != null
        ? DateFormatters.formatTime(item.start!)
        : (item.allDay ? l.allDayLabel : '');
    final recent = item.todo != null && _recentMatches(item.todo!.id, item.occurrenceId);
    final done = item.completed || recent;

    final timeRange = item.start != null && item.end != null
        ? '${DateFormatters.formatTime(item.start!)}–${DateFormatters.formatTime(item.end!)}'
        : (item.calendarName ?? '');

    final metaParts = <String>[];
    if (item.calendarName != null && !isPlan) {
      metaParts.add(item.calendarName!);
    }
    if (isPlan && item.start != null && item.end != null) {
      metaParts.add(l.plannedRangeLabel(timeRange));
    } else {
      metaParts.add(timeRange);
    }

    if (isPlan) {
      if (item.todo?.dueDate != null) {
        final due = item.todo!.dueDate!.toLocal();
        if (done) {
          final completedAt = recent ? _recent?.completedAt : item.todo?.completedAt;
          metaParts.add(_completedText(l, completedAt));
        }
        metaParts.add(_dueText(l, due));
      } else if (done) {
        final completedAt = recent ? _recent?.completedAt : item.todo?.completedAt;
        metaParts.add(_completedText(l, completedAt));
      }
    } else if (isSeries) {
      metaParts.add(l.recurringTask);
    }
    final metaText = metaParts.join(' · ');

    final recentState = _recent;
    final undo = recent && recentState != null ? _undoAction(recentState) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(top: 7, right: 8),
              child: Text(
                timeStr,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 9,
                  color: SpecTokens.faint,
                  fontFeatures: AppTypography.tabular,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          ),
          Expanded(
            child: SpecTimeBlock(
              kind: isPlanOrInstance ? SpecTimeBlockKind.plan : SpecTimeBlockKind.event,
              title: item.title,
              meta: metaText,
              barColor: item.calendarColor ?? (isPlan ? SpecTokens.work : SpecTokens.scheduleBlue),
              bgColor: isQuiet ? SpecTokens.wash : null,
              done: done,
              checked: done,
              trailing: undo,
              onToggle: null,
              onTap: () {
                if (item.event != null) {
                  _openEvent(item.event!);
                } else if (item.todo != null) {
                  _openTodo(item.todo!);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeBlockRow(DayItem item, {bool isQuiet = false}) {
    final isPlan = item.kind == DayItemKind.allocation;
    final timeStr = item.start != null
        ? DateFormatters.formatTime(item.start!)
        : '';
    final metaStr = item.start != null && item.end != null
        ? '${DateFormatters.formatTime(item.start!)}–${DateFormatters.formatTime(item.end!)}'
        : (item.calendarName ?? '');
    final fullMeta = (item.calendarName != null && !isPlan)
        ? '${item.calendarName} · $metaStr'
        : metaStr;

    return SpecTimelineRow(
      timeLabel: timeStr,
      dotColor: item.calendarColor ?? (isPlan ? SpecTokens.work : SpecTokens.ink),
      child: SpecTimeBlock(
        kind: isPlan ? SpecTimeBlockKind.plan : SpecTimeBlockKind.event,
        title: item.title,
        meta: fullMeta,
        barColor: item.calendarColor ?? (isPlan ? SpecTokens.work : SpecTokens.scheduleBlue),
        bgColor: isQuiet ? SpecTokens.wash : null,
        onTap: () {
          if (item.event != null) {
            _openEvent(item.event!);
          } else if (item.todo != null) {
            _openTodo(item.todo!);
          }
        },
      ),
    );
  }

  Widget _desktop(
    AppLocalizations l,
    AsyncValue<ActionProjectionData> data,
    DayAgenda agenda,
    List<Todo> unplanned,
  ) {
    final projection = data.valueOrNull;
    final plannedTodoIds = <int>{
      for (final a in agenda.allocations)
        if (a.todo != null) a.todo!.id,
    };

    final noDue = <Todo>[
      for (final todo in unplanned)
        if (todo.dueDate == null && !plannedTodoIds.contains(todo.id)) todo,
    ];
    final shelfSource = _injectRecentTodos(noDue, _RecentSection.unplanned);
    final noDueCount = noDue.length;
    final preview = shelfSource.take(3).toList();
    final hidden = shelfSource.length - preview.length;

    final allCompletedTodos = projection?.completedTodayTodos ?? const <Todo>[];
    final allCompletedInstances =
        projection?.completedTodayTaskInstances ??
        const <ProjectedTaskInstance>[];
    final recent = _recent;
    final recentKey = recent == null
        ? null
        : _keyOf(recent.todo.id, recent.occurrenceId);
    final completedTodos = recentKey == null
        ? allCompletedTodos
        : [
            for (final todo in allCompletedTodos)
              if (_keyOf(todo.id, null) != recentKey) todo,
          ];
    final completedInstances = recentKey == null
        ? allCompletedInstances
        : [
            for (final instance in allCompletedInstances)
              if (_keyOf(instance.todo.id, instance.occurrenceId) != recentKey)
                instance,
          ];

    final visibleCompletedTodos = [
      for (final todo in completedTodos)
        if (!plannedTodoIds.contains(todo.id)) todo,
    ];
    final visibleCompletedInstances = [
      for (final instance in completedInstances)
        if (!plannedTodoIds.contains(instance.todo.id)) instance,
    ];
    final completedCount =
        visibleCompletedTodos.length + visibleCompletedInstances.length;

    final overdueItems = _injectRecentDayItems(
      agenda.overdueTodos,
      _RecentSection.overdue,
    );
    final visibleOverdue = [
      for (final item in overdueItems)
        if (item.todo != null && !plannedTodoIds.contains(item.todo!.id)) item,
    ];

    final dueItems = _injectRecentDayItems(
      agenda.dueTodos,
      _RecentSection.dueToday,
    );
    final visibleDue = [
      for (final item in dueItems)
        if (item.todo != null && !plannedTodoIds.contains(item.todo!.id)) item,
    ];

    final missedCards = _missedCards(projection, plannedTodoIds);

    final timed = agenda.timed;
    bool isRunning(DayItem item) {
      final start = item.start;
      final end = item.end;
      if (start == null || end == null || item.allDay) return false;
      return !start.isAfter(widget.now) && end.isAfter(widget.now);
    }

    final running = timed.where(isRunning).toList();
    final rest = timed
        .where((item) => !item.allDay && !isRunning(item) && !_hasEnded(item))
        .toList();
    final ended = timed.where(_hasEnded).toList();
    final endedItems = _injectRecentDayItems(ended, _RecentSection.ended);
    final runningItems = _injectRecentDayItems(running, _RecentSection.now);

    final upcoming = <({DayItem item, bool instance})>[
      for (final item in rest)
        if (!item.allDay) (item: item, instance: false),
      for (final instance in agenda.instances) (item: instance, instance: true),
    ];
    final upcomingItems = _injectRecentUpcoming(upcoming);

    final allDayEvents = agenda.events.where((e) => e.allDay).toList();

    final taskChildren = <Widget>[
      _zoneLabel(l.tasksZoneLabel),
      if (plannedTodoIds.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Text(
            l.plannedTodosMovedToTimeline(plannedTodoIds.length),
            style: const TextStyle(
              fontSize: 10,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      for (final card in missedCards) _missedCard(l, card),
      if (visibleOverdue.isNotEmpty) ...[
        _groupHead(
          label: l.sectionOverdueLabel,
          count: visibleOverdue.length,
          danger: true,
        ),
        for (var i = 0; i < visibleOverdue.length && i < 3; i++)
          _taskRow(
            key: ValueKey('overdue-${visibleOverdue[i].todo!.id}'),
            title: visibleOverdue[i].title,
            checked: visibleOverdue[i].completed,
            isOverdue: isOverdueByDate(visibleOverdue[i].todo?.dueDate, widget.now),
            dueLabel: _formatDueLabel(l, visibleOverdue[i].todo?.dueDate, isOverdue: true),
            calendarName: visibleOverdue[i].calendarName,
            calendarColor: visibleOverdue[i].calendarColor,
            rrule: visibleOverdue[i].todo?.rrule,
            onToggle: (_) =>
                _toggleItem(visibleOverdue[i], _RecentSection.overdue, i),
            onTap: () => _openTodo(visibleOverdue[i].todo!),
            onSchedule: () => _scheduleTodo(visibleOverdue[i].todo!),
          ),
        if (visibleOverdue.length > 3)
          _moreRow(
            l,
            visibleOverdue.length,
            label: l.viewAllNItems(visibleOverdue.length),
            onTap: () => context.push('/todo?mode=all'),
          ),
      ],
      if (visibleDue.isNotEmpty) ...[
        _groupHead(
          label: l.sectionDueToday,
          count: visibleDue.length,
        ),
        for (var i = 0; i < visibleDue.length && i < 2; i++)
          _taskRow(
            key: ValueKey('due-${visibleDue[i].todo!.id}'),
            title: visibleDue[i].title,
            checked: visibleDue[i].completed,
            isOverdue: false,
            dueLabel: _formatDueLabel(l, visibleDue[i].todo?.dueDate),
            calendarName: visibleDue[i].calendarName,
            calendarColor: visibleDue[i].calendarColor,
            rrule: visibleDue[i].todo?.rrule,
            onToggle: (_) =>
                _toggleItem(visibleDue[i], _RecentSection.dueToday, i),
            onTap: () => _openTodo(visibleDue[i].todo!),
            onSchedule: () => _scheduleTodo(visibleDue[i].todo!),
          ),
      ],
      if (shelfSource.isNotEmpty) ...[
        _groupHead(
          label: l.todayNoDateGroup,
          count: noDueCount,
          trailing: const Icon(
            CupertinoIcons.chevron_up,
            size: 11,
            color: SpecTokens.faint,
          ),
          onToggle: widget.onOpenUnplanned,
        ),
        for (var i = 0; i < preview.length; i++)
          _taskRow(
            key: ValueKey('unplanned-${preview[i].id}'),
            title: preview[i].summary,
            checked: preview[i].status == 'COMPLETED',
            calendarName: _calendarName(preview[i]),
            calendarColor: _calendarColor(preview[i]),
            rrule: preview[i].rrule,
            onToggle: (_) => _toggleUnplanned(preview[i], i),
            onTap: () => _openTodo(preview[i]),
            onSchedule: () => _scheduleTodo(preview[i]),
          ),
        if (hidden > 0) _showAllRow(l, hidden, paddingLeft: 12),
      ],
      if (completedCount > 0) ...[
        _groupHead(
          label: l.completedTodaySection,
          count: completedCount,
          expanded: _completedExpanded,
          onToggle: () =>
              setState(() => _completedExpanded = !_completedExpanded),
        ),
        if (_completedExpanded) ...[
          for (final todo in visibleCompletedTodos)
            _taskRow(
              key: ValueKey('completed-${todo.id}'),
              title: todo.summary,
              checked: true,
              rrule: todo.rrule,
              onToggle: (_) => _setCompleted(todo, null, false),
              onTap: () => _openTodo(todo),
              onSchedule: () => _scheduleTodo(todo),
            ),
          for (final instance in visibleCompletedInstances)
            _taskRow(
              key: ValueKey('completed-inst-${instance.occurrenceId}'),
              title: instance.todo.summary,
              checked: true,
              rrule: instance.todo.rrule,
              onToggle: (_) => _setCompleted(
                instance.todo,
                instance.occurrenceId,
                false,
              ),
              onTap: () => _openTodo(instance.todo),
              onSchedule: () => _scheduleTodo(instance.todo),
            ),
        ],
      ],
      if (visibleOverdue.isEmpty &&
          visibleDue.isEmpty &&
          missedCards.isEmpty &&
          shelfSource.isEmpty &&
          completedCount == 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: SpecEmpty(
            icon: CupertinoIcons.checkmark_alt,
            title: l.todayCleanTitle,
            hint: l.todayCleanSub,
          ),
        ),
      const SizedBox(height: 16),
    ];

    final timeChildren = <Widget>[
      _zoneLabel(l.timeZoneLabel),
      if (allDayEvents.isNotEmpty)
        SpecAlldayStrip(
          label: l.allDayLabel,
          items: [
            for (final ev in allDayEvents)
              SpecAlldayItem(
                title: ev.title,
                barColor: ev.calendarColor,
                bgColor: ev.calendarColor?.withValues(alpha: 0.12),
                onTap: () => _openEvent(ev.event!),
              ),
          ],
        ),
      if (endedItems.isNotEmpty) ...[
        _groupHead(
          label: l.actionEarlierToday,
          count: endedItems.length,
          expanded: _desktopEndedExpanded,
          onToggle: () => setState(() => _desktopEndedExpanded = !_desktopEndedExpanded),
        ),
        if (_desktopEndedExpanded)
          for (var i = 0; i < endedItems.length; i++)
            _timeBlockRow(endedItems[i], isQuiet: true),
      ],
      _groupHead(
        label: l.sectionNow,
        danger: true,
        trailing: Text(
          DateFormatters.formatTime(widget.now),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: SpecTokens.red,
            fontFeatures: AppTypography.tabular,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
      ),
      for (var i = 0; i < runningItems.length; i++)
        _timeBlockRow(runningItems[i]),
      const SpecNowLine(),
      if (upcomingItems.isNotEmpty) ...[
        _groupHead(
          label: l.sectionUpcoming,
          count: upcomingItems.length,
        ),
        for (var i = 0; i < upcomingItems.length; i++)
          _timeBlockRow(upcomingItems[i].item),
      ],
      if (allDayEvents.isEmpty &&
          endedItems.isEmpty &&
          runningItems.isEmpty &&
          upcomingItems.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 12),
          child: Text(
            l.todayEmptyTime,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      const SizedBox(height: 16),
    ];

    final desktopContent = Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _desktopHead(l, agenda, _summaryCounts(data.valueOrNull, unplanned)),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: SpecTokens.paper,
                        border: Border(
                          right: BorderSide(color: SpecTokens.hair, width: 1),
                        ),
                      ),
                      child: Listener(
                        onPointerDown: _onListPointerDown,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 118),
                          children: taskChildren,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: SpecTokens.paper,
                      child: Listener(
                        onPointerDown: _onListPointerDown,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(30, 14, 30, 118),
                          children: timeChildren,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  onCancel: () => setState(() => _desktopCaptureState = A2CaptureState.compact),
                  onDiscard: () {
                    _desktopCaptureController.clear();
                    setState(() {
                      _captureDraft = '';
                      _desktopCaptureState = A2CaptureState.compact;
                    });
                  },
                  onSubmit: () async {
                    await _submitDesktopCapture();
                    setState(() => _desktopCaptureState = A2CaptureState.compact);
                  },
                  onSubmitLater: () async {
                    await _submitDesktopCapture();
                    setState(() => _desktopCaptureState = A2CaptureState.compact);
                  },
                ),
              ),
            ),
          ),
        _desktopCaptureBar(l),
      ],
    );

    return _listSlot(l, data, desktopContent);
  }

  // ------------------------------------------------------------- recent injections

  /// Re-insert a just-completed timeline row where it stood while the
  /// projection no longer carries it.
  List<DayItem> _injectRecentDayItems(
    List<DayItem> items,
    _RecentSection section,
  ) {
    final recent = _recent;
    final snapshot = recent?.item;
    if (recent == null || snapshot == null || recent.section != section) {
      return items;
    }
    final key = _keyOf(recent.todo.id, recent.occurrenceId);
    if (items.any(
      (item) =>
          item.todo != null && _keyOf(item.todo!.id, item.occurrenceId) == key,
    )) {
      return items;
    }
    final index = recent.index.clamp(0, items.length);
    return [
      ...items.take(index),
      _completedCopy(snapshot),
      ...items.skip(index),
    ];
  }

  List<({DayItem item, bool instance})> _injectRecentUpcoming(
    List<({DayItem item, bool instance})> items,
  ) {
    final recent = _recent;
    final snapshot = recent?.item;
    if (recent == null ||
        snapshot == null ||
        recent.section != _RecentSection.upcoming) {
      return items;
    }
    final key = _keyOf(recent.todo.id, recent.occurrenceId);
    if (items.any(
      (entry) =>
          entry.item.todo != null &&
          _keyOf(entry.item.todo!.id, entry.item.occurrenceId) == key,
    )) {
      return items;
    }
    final index = recent.index.clamp(0, items.length);
    return [
      ...items.take(index),
      (
        item: _completedCopy(snapshot),
        instance: snapshot.kind == DayItemKind.instance,
      ),
      ...items.skip(index),
    ];
  }

  List<_MissedCardData> _missedCards(
    ActionProjectionData? projection,
    Set<int> plannedTodoIds,
  ) {
    final cards = <int, _MissedCardData>{};
    for (final instance
        in projection?.missedTaskInstances ?? const <ProjectedTaskInstance>[]) {
      if (plannedTodoIds.contains(instance.todo.id)) continue;
      final existing = cards[instance.todo.id];
      if (existing == null) {
        cards[instance.todo.id] = _MissedCardData(
          todo: instance.todo,
          latest: instance,
        );
        continue;
      }
      existing.count += 1;
      final latest = existing.latest;
      if (latest == null ||
          instance.occurrence.nominalAnchor.canonical.compareTo(
                latest.occurrence.nominalAnchor.canonical,
              ) >
              0) {
        existing.latest = instance;
      }
    }
    for (final todo in projection?.earlierMissedSeries ?? const <Todo>[]) {
      if (plannedTodoIds.contains(todo.id)) continue;
      cards.putIfAbsent(todo.id, () => _MissedCardData(todo: todo));
    }
    return cards.values.toList();
  }

  Widget _missedCard(AppLocalizations l, _MissedCardData card) {
    final repeat = _missedRepeatLabel(card.todo, l);
    final subtitle = l.missedCardSubtitle(
      repeat.isEmpty ? l.repeatCustom : repeat,
      card.count,
    );
    return Container(
      key: ValueKey('missed-card-${card.todo.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: SpecTokens.borderRadius6,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: SpecTokens.paper,
                borderRadius: SpecTokens.borderRadius6,
                border: Border.all(color: const Color(0xFFE3C8C2)),
              ),
              padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openTodo(card.todo),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.todo.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                                color: SpecTokens.ink,
                                fontFamilyFallback: AppTypography.fallback,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 9,
                                color: SpecTokens.red,
                                fontFamilyFallback: AppTypography.fallback,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _completeMissed(card),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: SpecTokens.paper,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFE3C8C2),
                          ),
                        ),
                        child: Text(
                          l.completeThisOccurrence,
                          style: const TextStyle(
                            fontSize: 9,
                            color: SpecTokens.red,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 3,
                child: ColoredBox(color: SpecTokens.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _missedRepeatLabel(Todo todo, AppLocalizations l) {
    final raw = todo.rrule ?? todo.recurrenceRule;
    if (raw == null || raw.isEmpty) return '';
    final rule = raw.startsWith('RRULE:') ? raw.substring(6) : raw;
    final parts = <String, String>{};
    for (final part in rule.split(';')) {
      final split = part.indexOf('=');
      if (split <= 0) continue;
      parts[part.substring(0, split).toUpperCase()] = part.substring(split + 1);
    }
    if (parts['FREQ']?.toUpperCase() == 'WEEKLY') {
      final byDay = parts['BYDAY'];
      final codes = byDay == null || byDay.isEmpty
          ? const <String>[]
          : [
              for (final code in byDay.split(','))
                if (code.trim().isNotEmpty) code.trim().toUpperCase(),
            ];
      if (codes.length <= 1) {
        final weekday = codes.isEmpty
            ? _recurrenceAnchor(todo)?.weekday
            : _weekdayIndex(codes.first);
        if (weekday != null) {
          final full = DateFormat.EEEE(
            _locale,
          ).format(DateTime(2024, 1, weekday));
          final day = _locale.startsWith('zh') && full.characters.length > 2
              ? full.characters.last.toString()
              : full;
          if (day.isNotEmpty) return l.missedCardRepeatWeekly(day);
        }
      }
    }
    final description = describeRepeat(context, rule);
    final split = description.indexOf(' · ');
    return split < 0 ? description : description.substring(0, split);
  }

  DateTime? _recurrenceAnchor(Todo todo) {
    final value = todo.recurrenceAnchorValue;
    if (value != null) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return todo.startDate ?? todo.dueDate;
  }

  int? _weekdayIndex(String code) {
    const codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    for (var i = 0; i < codes.length; i++) {
      if (code.endsWith(codes[i])) return i + 1;
    }
    return null;
  }

  List<Todo> _injectRecentTodos(List<Todo> items, _RecentSection section) {
    final recent = _recent;
    if (recent == null || recent.section != section) return items;
    final key = _keyOf(recent.todo.id, recent.occurrenceId);
    if (items.any((todo) => _keyOf(todo.id, null) == key)) return items;
    final index = recent.index.clamp(0, items.length);
    return [...items.take(index), recent.todo, ...items.skip(index)];
  }

  DayItem _completedCopy(DayItem item) {
    if (item.completed) return item;
    return DayItem(
      kind: item.kind,
      title: item.title,
      start: item.start,
      end: item.end,
      todo: item.todo,
      event: item.event,
      allocation: item.allocation,
      occurrenceId: item.occurrenceId,
      calendarName: item.calendarName,
      calendarColor: item.calendarColor,
      completed: true,
      allDay: item.allDay,
    );
  }

  /// Ended: the item has a span and that span closed before the clock.
  bool _hasEnded(DayItem item) {
    final end = item.end;
    if (end == null || item.allDay) return false;
    return !end.isAfter(widget.now);
  }



  /// T3's other half: when the row knows when it was completed, the meta says
  /// so, because finishing before the deadline is the fact worth keeping.
  String _completedText(AppLocalizations l, DateTime? completedAt) {
    final at = completedAt?.toLocal();
    if (at == null) return l.completed;
    return '${l.completed} ${DateFormatters.formatTime(at)}';
  }

  String _dueText(
    AppLocalizations l,
    DateTime due, {
    bool prefixToday = false,
  }) {
    final isToday =
        due.year == _today.year &&
        due.month == _today.month &&
        due.day == _today.day;
    final hasTime = due.hour != 0 || due.minute != 0;
    if (isToday && hasTime) {
      return prefixToday
          ? l.dueTodayTimeLabel(DateFormatters.formatTime(due))
          : l.dueValueLabel(DateFormatters.formatTime(due));
    }
    final date = DateFormat.Md(_locale).format(due);
    return l.dueValueLabel(
      hasTime ? '$date ${DateFormatters.formatTime(due)}' : date,
    );
  }

  String? _calendarName(Todo todo) {
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    for (final calendar in calendars) {
      if (calendar.id == todo.calendarId) return calendar.name;
    }
    return null;
  }

  Color? _calendarColor(Todo todo) {
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    for (final calendar in calendars) {
      if (calendar.id == todo.calendarId) {
        return ColorUtils.parseHex(calendar.color);
      }
    }
    return null;
  }

  Widget? _undoFor(int? todoId, String? occurrenceId, _RecentSection section) {
    final recent = _recent;
    if (recent != null &&
        recent.section == section &&
        todoId != null &&
        _recentMatches(todoId, occurrenceId)) {
      return _undoAction(recent);
    }
    return null;
  }

  /// The bucket holds items the shelf never previews (they have a deadline);
  /// this row is the only honest way to say so and to reach them.
  Widget _showAllRow(
    AppLocalizations l,
    int count, {
    double paddingLeft = 42,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpenUnplanned,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.fromLTRB(paddingLeft, 0, 3, 0),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.arrow_right,
                size: 10,
                color: SpecTokens.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l.todayViewNoDate(count),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: SpecTokens.muted,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreRow(
    AppLocalizations l,
    int more, {
    String? label,
    double paddingLeft = 42,
    VoidCallback? onTap,
    bool expanded = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => setState(() => _unplannedExpanded = !_unplannedExpanded),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.fromLTRB(paddingLeft, 0, 3, 0),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.arrow_right,
                size: 10,
                color: SpecTokens.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label ?? (expanded ? l.collapseLabel : l.expandRemaining(more)),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: SpecTokens.muted,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which section a just-completed row belongs to, so it can be re-inserted
/// where it stood instead of appearing somewhere it never lived.
enum _RecentSection {
  now,
  upcoming,
  ended,
  dueToday,
  overdue,
  unplanned,
}

class _MissedCardData {
  _MissedCardData({required this.todo, this.latest});

  final Todo todo;
  ProjectedTaskInstance? latest;
  int count = 1;
}

class _RecentCompletion {
  const _RecentCompletion({
    required this.todo,
    required this.occurrenceId,
    required this.label,
    required this.section,
    required this.index,
    required this.completedAt,
    this.item,
  });

  final Todo todo;
  final String? occurrenceId;
  final String label;
  final _RecentSection section;
  final int index;
  final DateTime completedAt;
  final DayItem? item;
}



class _Toast extends StatelessWidget {
  const _Toast({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ds.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.checkmark, size: 13, color: ds.success),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: ds.bg,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
