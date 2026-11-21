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
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/spec_components.dart';
import 'package:dayspark/ui/pages/home/day_agenda.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';

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
    this.initialCaptureExpanded = false,
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
  final bool initialCaptureExpanded;
  final String initialDraft;

  @override
  ConsumerState<A2TodayPage> createState() => _A2TodayPageState();
}

class _A2TodayPageState extends ConsumerState<A2TodayPage> {
  final ScrollController _scroll = ScrollController();
  int? _recentId;
  Timer? _recentTimer;
  bool _unplannedExpanded = false;
  bool _upcomingExpanded = false;
  bool _overdueExpanded = false;
  bool _completedExpanded = false;
  bool _missedExpanded = false;
  bool _earlierMissedExpanded = false;
  bool _toastVisible = false;
  Timer? _toastTimer;
  bool _capturing = false;
  bool _captureFocused = false;
  late String _captureDraft = widget.initialDraft;
  double? _lastViewport;
  late bool _captureExpanded = widget.initialCaptureExpanded;
  late final TextEditingController _desktopCaptureController =
      TextEditingController(text: widget.initialDraft);
  final FocusNode _desktopCaptureFocusNode = FocusNode();

  /// The one row that was just completed and can still be undone. It is kept
  /// rendered in its own section for five seconds even after the projection
  /// drops it, so a tick never makes the row jump away from under the finger.
  _RecentCompletion? _recent;
  Timer? _undoTimer;
  final GlobalKey _undoButtonKey = GlobalKey();

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
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
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

  Future<void> _capture(String text) async {
    if (_capturing) return;
    final l = AppLocalizations.of(context)!;
    _capturing = true;
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        _showToast(l.noCalendar);
        return;
      }
      final id = await ref.read(createTodoProvider)(
        calendarId: calendars.first.id,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
      );
      if (!mounted) return;
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
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      debugPrint('today: capture failed: $error');
      if (mounted) _showToast(l.actionFailedRetry);
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

  String _undoLabel(
    AppLocalizations l,
    String? occurrenceId, {
    String? displayLabel,
  }) {
    if (occurrenceId == null) return l.undo;
    final label = displayLabel ?? _occurrenceLabel(occurrenceId);
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

  Future<void> _toggleMissed(ProjectedTaskInstance instance, int index) {
    if (_recentMatches(instance.todo.id, instance.occurrenceId)) {
      return _setCompleted(instance.todo, instance.occurrenceId, false);
    }
    return _setCompleted(
      instance.todo,
      instance.occurrenceId,
      true,
      instance: instance,
      section: _RecentSection.missed,
      index: index,
    );
  }

  /// Every completion goes through the one callback the page was handed, so
  /// the undo action is the same write path (and keeps the occurrence id).
  Future<void> _setCompleted(
    Todo todo,
    String? occurrenceId,
    bool completed, {
    DayItem? item,
    ProjectedTaskInstance? instance,
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
        instance: instance,
        section: section ?? _RecentSection.unplanned,
        index: index,
      );
    } else {
      _clearUndo();
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    // The inline key beside the row is the undo affordance; the message only
    // reports what happened.
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(completed ? l.completed : l.openTask)),
      );
  }

  void _startUndo(
    AppLocalizations l,
    Todo todo,
    String? occurrenceId, {
    DayItem? item,
    ProjectedTaskInstance? instance,
    required _RecentSection section,
    required int index,
  }) {
    _undoTimer?.cancel();
    setState(() {
      _recent = _RecentCompletion(
        todo: todo,
        occurrenceId: occurrenceId,
        label: _undoLabel(
          l,
          occurrenceId,
          displayLabel: instance?.occurrence.displayLabel,
        ),
        section: section,
        index: index,
        completedAt: DateTime.now(),
        item: item,
        instance: instance,
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
    setState(() => _recent = null);
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
                  color: ds.primary,
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
    final count = projection?.unplannedCount ?? 0;
    return desktop
        ? _desktop(l, data, agenda, unplanned, count)
        : _mobile(l, data, agenda, unplanned, count);
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
    int unplannedCount,
  ) {
    final ds = context.ds;
    final projection = data.valueOrNull;
    final preview = <Todo>[
      for (final todo in unplanned)
        if (todo.dueDate == null) todo,
    ];
    // A row completed from this shelf is held in place for the undo window,
    // even though the projection has already dropped it.
    final shelfSource = _injectRecentTodos(preview, _RecentSection.unplanned);
    final shown = _unplannedExpanded
        ? shelfSource
        : shelfSource.take(3).toList();
    // What "Show less" can hide, and what the preview never carries: the
    // Unplanned bucket also holds todos that already have a deadline, and the
    // design keeps those out of the shelf. The head prints the bucket's real
    // count, so the shelf must offer a way to reach the rest.
    final expandable = shelfSource.length - shown.length;
    final beyondShelf = unplannedCount - preview.length;
    // T1: every section decides its own presence, and the empty box is only
    // the whole page when nothing at all remains — no timeline, no shelf.
    final sections = _sections(
      l,
      agenda,
      timeColumn: kA2TimeColumn,
      projection: projection,
    );
    final hasShelf = shelfSource.isNotEmpty || unplannedCount > 0;
    final empty = sections.isEmpty && !hasShelf;

    final overdueCount = agenda.overdueTodos.length +
        (projection?.missedTaskInstances.length ?? 0);
    final dueCount = agenda.dueTodos.length;
    final doneCount = (projection?.completedTodayTodos.length ?? 0) +
        (projection?.completedTodayTaskInstances.length ?? 0);
    final isPageEmpty = overdueCount == 0 &&
        dueCount == 0 &&
        unplannedCount == 0 &&
        doneCount == 0 &&
        agenda.events.isEmpty &&
        agenda.allocations.isEmpty;

    final summary = isPageEmpty
        ? l.emptyTodayTitle
        : '$overdueCount ${l.sectionOverdueLabel} · $dueCount ${l.sectionDueToday} · $unplannedCount ${l.inbox} · $doneCount ${l.completed}';

    final mobileContentHeader = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.MMMd(_locale).format(widget.now),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${DateFormat.E(_locale).format(widget.now)} · ${l.weekNumberLabel(isoWeekNumber(widget.now))}',
            style: const TextStyle(
              fontSize: 11,
              color: SpecTokens.muted,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 10,
              color: SpecTokens.faint,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );

    final children = <Widget>[
      mobileContentHeader,
      ...sections,
      if (hasShelf) ...[
        A2GroupHead(
          label: l.inbox,
          count: unplannedCount,
          countLabel: l.groupCountItems(unplannedCount),
          topBorder: true,
          trailing: Icon(
            // With nothing left to expand the tap leaves for the bucket's
            // own view, so the chevron must not promise a disclosure.
            _unplannedExpanded || expandable == 0
                ? CupertinoIcons.chevron_up
                : CupertinoIcons.chevron_down,
            size: 14,
            color: ds.ink3,
          ),
          onTap: expandable > 0
              ? () => setState(() => _unplannedExpanded = !_unplannedExpanded)
              : widget.onOpenUnplanned,
        ),
        for (final (index, todo) in shown.indexed)
          _unplannedRow(
            l,
            todo,
            highlighted: todo.id == _recentId,
            index: index,
          ),
        if (expandable > 0)
          _moreRow(l, expandable)
        else if (beyondShelf > 0)
          _showAllRow(l, beyondShelf),
      ],
      const SizedBox(height: 12),
    ];

    return Listener(
      onPointerDown: _onListPointerDown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          A2DayHead(
            title: l.today,
            subtitle:
                '${DateFormat.yMMMMd(_locale).format(widget.now)} · '
                '${DateFormat.E(_locale).format(widget.now)}',
            clock: DateFormatters.formatTime(widget.now),
            actions: [
              A2IconAction(
                icon: CupertinoIcons.search,
                tooltip: l.search,
                onPressed: () => context.push('/search'),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _listSlot(
                    l,
                    data,
                    // The empty box is centred in the space the list would have
                    // used. Inside the list it sat against the head with the
                    // whole lower half of the page blank.
                    empty
                        ? A2Empty(
                            icon: CupertinoIcons.time,
                            title: l.emptyTodayTitle,
                            hint: l.emptyTodayHint,
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
                                padding: EdgeInsets.zero,
                                children: children,
                              ),
                            ),
                          ),
                  ),
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
            hint: _captureFocused ? l.captureHintSubmit : l.captureHintEnter,
            initialDraft: _captureDraft,
            onDraftChanged: (draft) => _captureDraft = draft,
            onSubmit: _capture,
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
    required String label,
    int? count,
    bool danger = false,
    bool expanded = false,
    VoidCallback? onToggle,
    Widget? trailing,
  }) {
    final content = Container(
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
      return InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: content,
      );
    }
    return content;
  }

  Widget _desktopHead(
    AppLocalizations l,
    AsyncValue<ActionProjectionData> data,
    DayAgenda agenda,
    int unplannedCount,
  ) {
    final projection = data.valueOrNull;
    final overdueCount = agenda.overdueTodos.length +
        (projection?.missedTaskInstances.length ?? 0);
    final dueCount = agenda.dueTodos.length;
    final doneCount = (projection?.completedTodayTodos.length ?? 0) +
        (projection?.completedTodayTaskInstances.length ?? 0);
    final isEmpty = overdueCount == 0 &&
        dueCount == 0 &&
        unplannedCount == 0 &&
        doneCount == 0 &&
        agenda.events.isEmpty &&
        agenda.allocations.isEmpty;

    final summary = isEmpty
        ? l.emptyTodayTitle
        : '$overdueCount ${l.sectionOverdueLabel} · $dueCount ${l.sectionDueToday} · $unplannedCount ${l.inbox} · $doneCount ${l.completed}';

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
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
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

  void _submitDesktopCapture() {
    final text = _desktopCaptureController.text.trim();
    if (text.isEmpty) return;
    _desktopCaptureController.clear();
    setState(() {
      _captureDraft = '';
      _captureExpanded = false;
    });
    _capture(text);
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
                  setState(() => _captureExpanded = !_captureExpanded);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                  ),
                  child: const Icon(
                    CupertinoIcons.plus,
                    size: 16,
                    color: SpecTokens.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopCaptureExpandedPanel(AppLocalizations l) {
    if (!_captureExpanded) return const SizedBox.shrink();
    return Positioned(
      bottom: 82,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 620,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE1E1D9), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(25, 25, 24, 0.13),
                blurRadius: 55,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.captureTitle,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: SpecTokens.ink,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.captureDefaultDate,
                            style: const TextStyle(
                              fontSize: 10,
                              color: SpecTokens.muted,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('desktop-capture-collapse-btn'),
                      onTap: () => setState(() => _captureExpanded = false),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(CupertinoIcons.xmark, size: 12, color: SpecTokens.muted),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _desktopCaptureController,
                      decoration: InputDecoration(
                        hintText: l.captureInputPlaceholder,
                        hintStyle: const TextStyle(fontSize: 13, color: SpecTokens.faint),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: SpecTokens.hair),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 13, color: SpecTokens.ink),
                      onChanged: (val) => _captureDraft = val,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _captureExpanded = false),
                          child: Text(l.cancel, style: const TextStyle(fontSize: 12, color: SpecTokens.muted)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('desktop-capture-submit-btn'),
                          onPressed: _submitDesktopCapture,
                          style: FilledButton.styleFrom(
                            backgroundColor: SpecTokens.ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(l.captureSaveTodo, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
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
  }) {
    final l = AppLocalizations.of(context)!;
    final meta = <Widget>[
      if (calendarColor != null) ...[
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: calendarColor),
        ),
        const SizedBox(width: 4),
      ],
      if (calendarName != null) ...[
        Text(calendarName),
        const SizedBox(width: 4),
      ],
      if (rrule != null && rrule.isNotEmpty) ...[
        Text('· ${l.recurringTask}'),
        const SizedBox(width: 4),
      ],
      if (missedCount != null && missedCount > 0) ...[
        Text(
          '· ${l.missed} $missedCount',
          style: const TextStyle(color: SpecTokens.red),
        ),
        const SizedBox(width: 4),
      ],
    ];

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
    int unplannedCount,
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
    final preview = shelfSource.take(3).toList();
    final hidden = unplannedCount - preview.length;

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

    final missed =
        projection?.missedTaskInstances ?? const <ProjectedTaskInstance>[];
    final missedItems = _injectRecentInstances(missed, _RecentSection.missed);
    final visibleMissed = [
      for (final item in missedItems)
        if (!plannedTodoIds.contains(item.todo.id)) item,
    ];

    final timed = agenda.timed;
    bool isRunning(DayItem item) {
      final start = item.start;
      final end = item.end;
      if (start == null || end == null || item.allDay) return false;
      return !start.isAfter(widget.now) && end.isAfter(widget.now);
    }

    final running = timed.where(isRunning).toList();
    final rest = timed
        .where((item) => !isRunning(item) && !_hasEnded(item))
        .toList();
    final ended = timed.where(_hasEnded).toList();
    final endedItems = _injectRecentDayItems(ended, _RecentSection.ended);
    final runningItems = _injectRecentDayItems(running, _RecentSection.now);

    final upcoming = <({DayItem item, bool instance})>[
      for (final item in rest) (item: item, instance: false),
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
      if (visibleOverdue.isNotEmpty) ...[
        _groupHead(
          label: l.sectionOverdueLabel,
          count: visibleOverdue.length,
          danger: true,
        ),
        for (final item in visibleOverdue)
          _taskRow(
            key: ValueKey('overdue-${item.todo!.id}'),
            title: item.title,
            checked: item.completed,
            isOverdue: true,
            dueLabel: item.todo?.dueDate != null
                ? DateFormat.Md(_locale).format(item.todo!.dueDate!.toLocal())
                : l.sectionOverdueLabel,
            calendarName: item.calendarName,
            calendarColor: item.calendarColor,
            rrule: item.todo?.rrule,
            onToggle: (_) =>
                _setCompleted(item.todo!, item.occurrenceId, !item.completed),
            onTap: () => _openTodo(item.todo!),
            onSchedule: () => _scheduleTodo(item.todo!),
          ),
      ],
      if (visibleDue.isNotEmpty) ...[
        _groupHead(
          label: l.sectionDueToday,
          count: visibleDue.length,
        ),
        for (final item in visibleDue)
          _taskRow(
            key: ValueKey('due-${item.todo!.id}'),
            title: item.title,
            checked: item.completed,
            isOverdue: false,
            dueLabel: l.today,
            calendarName: item.calendarName,
            calendarColor: item.calendarColor,
            rrule: item.todo?.rrule,
            onToggle: (_) =>
                _setCompleted(item.todo!, item.occurrenceId, !item.completed),
            onTap: () => _openTodo(item.todo!),
            onSchedule: () => _scheduleTodo(item.todo!),
          ),
      ],
      if (visibleMissed.isNotEmpty) ...[
        _groupHead(
          label: l.missed,
          count: visibleMissed.length,
          danger: true,
        ),
        for (final missed in visibleMissed)
          _taskRow(
            key: ValueKey('missed-${missed.occurrenceId}'),
            title: missed.todo.summary,
            checked: false,
            isOverdue: true,
            dueLabel: missed.occurrence.displayLabel,
            rrule: missed.todo.rrule,
            missedCount: 1,
            onToggle: (_) => _setCompleted(
              missed.todo,
              missed.occurrenceId,
              true,
            ),
            onTap: () => _openTodo(missed.todo),
            onSchedule: () => _scheduleTodo(missed.todo),
          ),
      ],
      _groupHead(
        label: l.inbox,
        count: shelfSource.length,
        trailing: const Icon(
          CupertinoIcons.chevron_up,
          size: 11,
          color: SpecTokens.faint,
        ),
        onToggle: widget.onOpenUnplanned,
      ),
      if (preview.isEmpty && shelfSource.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
          child: Text(
            l.unplannedGroupEmpty,
            style: const TextStyle(
              fontSize: 11,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      for (final todo in preview)
        _taskRow(
          key: ValueKey('unplanned-${todo.id}'),
          title: todo.summary,
          checked: todo.status == 'COMPLETED',
          rrule: todo.rrule,
          onToggle: (_) =>
              _setCompleted(todo, null, todo.status != 'COMPLETED'),
          onTap: () => _openTodo(todo),
          onSchedule: () => _scheduleTodo(todo),
        ),
      if (hidden > 0) _showAllRow(l, hidden),
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
          visibleMissed.isEmpty &&
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
        ),
        for (var i = 0; i < endedItems.length; i++)
          _timeBlockRow(endedItems[i], isQuiet: true),
      ],
      if (runningItems.isNotEmpty) ...[
        _groupHead(
          label: l.sectionNow,
          trailing: Text(
            DateFormatters.formatTime(widget.now),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
        for (var i = 0; i < runningItems.length; i++)
          _timeBlockRow(runningItems[i]),
      ],
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
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: SpecEmpty(
            icon: CupertinoIcons.calendar,
            title: l.todayEmptyTime,
            hint: l.todayEmptyTimeWithHint,
          ),
        ),
      const SizedBox(height: 16),
    ];

    final desktopContent = Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _desktopHead(l, data, agenda, unplannedCount),
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
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 118),
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
        _desktopCaptureExpandedPanel(l),
        _desktopCaptureBar(l),
      ],
    );

    return _listSlot(l, data, desktopContent);
  }

  // ------------------------------------------------------------- sections

  /// The three-row preview shared by the upcoming and overdue sections, the
  /// same bound the unplanned shelf uses.
  static const int _sectionLimit = 3;

  /// Each time section renders only when it has something. A lone overdue item
  /// must not be read through an "empty day" box, and a section whose last row
  /// was just completed keeps that row for the undo window.
  List<Widget> _sections(
    AppLocalizations l,
    DayAgenda agenda, {
    required double timeColumn,
    ActionProjectionData? projection,
  }) {
    final ds = context.ds;
    final allCompletedTodos = projection?.completedTodayTodos ?? const <Todo>[];
    final allCompletedInstances =
        projection?.completedTodayTaskInstances ??
        const <ProjectedTaskInstance>[];
    // The freshly completed row already sits in its own section for the undo
    // window; counting it here too would show it twice once the fold opens.
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
    final completedCount = completedTodos.length + completedInstances.length;
    final missed =
        projection?.missedTaskInstances ?? const <ProjectedTaskInstance>[];
    final earlierMissed = projection?.earlierMissedSeries ?? const <Todo>[];
    final hasEarlierMissed = projection?.hasEarlierMissed ?? false;
    final timed = agenda.timed;
    bool isRunning(DayItem item) {
      final start = item.start;
      final end = item.end;
      if (start == null || end == null || item.allDay) return false;
      return !start.isAfter(widget.now) && end.isAfter(widget.now);
    }

    final running = timed.where(isRunning).toList();
    final rest = timed
        .where((item) => !isRunning(item) && !_hasEnded(item))
        .toList();
    // What already ended belongs to the day, not to "upcoming": a 09:00
    // meeting at 15:00 shown ahead of a 16:00 one reads as a lie about time.
    final ended = timed.where(_hasEnded).toList();
    // "Earlier today" is its own section: ticking a row here must keep it here
    // for the undo window, not clone it into Upcoming.
    final endedItems = _injectRecentDayItems(ended, _RecentSection.ended);
    final widgets = <Widget>[];

    // "Now" is the page's only anchor: it is never folded.
    final runningItems = _injectRecentDayItems(running, _RecentSection.now);
    if (runningItems.isNotEmpty) {
      widgets.add(
        A2GroupHead(
          label: l.sectionNow,
          tone: ds.primary,
          topBorder: false,
          trailing: Text(
            DateFormatters.formatTime(widget.now),
            style: TextStyle(
              fontSize: 11,
              color: ds.faint,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      );
      for (var i = 0; i < runningItems.length; i++) {
        widgets.add(
          _timelineItem(
            runningItems[i],
            timeColumn,
            section: _RecentSection.now,
            index: i,
          ),
        );
      }
    }

    // Upcoming: timed rows then pending recurring instances, capped at three
    // with "还有 M 项 · 展开" (T2). The head's chevron mirrors the shelf.
    final upcoming = <({DayItem item, bool instance})>[
      for (final item in rest) (item: item, instance: false),
      for (final instance in agenda.instances) (item: instance, instance: true),
    ];
    final upcomingItems = _injectRecentUpcoming(upcoming);
    if (upcomingItems.isNotEmpty) {
      final expanded = _upcomingExpanded;
      final collapsible = upcomingItems.length > _sectionLimit;
      final shown = expanded
          ? upcomingItems
          : upcomingItems.take(_sectionLimit).toList();
      final hidden = upcomingItems.length - shown.length;
      void toggle() => setState(() => _upcomingExpanded = !_upcomingExpanded);
      widgets.add(
        A2GroupHead(
          label: l.sectionUpcoming,
          topBorder: false,
          trailing: collapsible
              ? Icon(
                  expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 14,
                  color: ds.ink3,
                )
              : null,
          onTap: collapsible ? toggle : null,
        ),
      );
      for (var i = 0; i < shown.length; i++) {
        final entry = shown[i];
        if (entry.instance) {
          final instance = entry.item;
          widgets.add(
            A2TimelineItem(
              timeLabel: instance.start == null || instance.allDay
                  ? l.allDayLabel
                  : DateFormatters.formatTime(instance.start!),
              timeColumn: timeColumn,
              child: _block(
                l,
                instance,
                kind: A2BlockKind.due,
                accent: ds.work,
                section: _RecentSection.upcoming,
                index: i,
              ),
            ),
          );
        } else {
          widgets.add(
            _timelineItem(
              entry.item,
              timeColumn,
              section: _RecentSection.upcoming,
              index: i,
            ),
          );
        }
      }
      if (collapsible) {
        widgets.add(
          _entryRow(
            expanded ? l.collapseLabel : l.expandRemaining(hidden),
            onTap: toggle,
          ),
        );
      }
    }

    final dueItems = _injectRecentDayItems(
      agenda.dueTodos,
      _RecentSection.dueToday,
    );
    if (dueItems.isNotEmpty) {
      widgets.add(
        A2GroupHead(
          label: l.sectionDueToday,
          count: dueItems.length,
          tone: ds.warn,
          topBorder: false,
        ),
      );
      for (var i = 0; i < dueItems.length; i++) {
        widgets.add(
          _timelineItem(
            dueItems[i],
            timeColumn,
            section: _RecentSection.dueToday,
            index: i,
          ),
        );
      }
    }

    // Overdue is capped exactly like Upcoming (T2); it is the other section
    // that can grow without bound.
    final overdueItems = _injectRecentDayItems(
      agenda.overdueTodos,
      _RecentSection.overdue,
    );
    if (overdueItems.isNotEmpty) {
      final expanded = _overdueExpanded;
      final collapsible = overdueItems.length > _sectionLimit;
      final shown = expanded
          ? overdueItems
          : overdueItems.take(_sectionLimit).toList();
      final hidden = overdueItems.length - shown.length;
      void toggle() => setState(() => _overdueExpanded = !_overdueExpanded);
      widgets.add(
        A2GroupHead(
          label: l.sectionOverdueLabel,
          count: overdueItems.length,
          danger: true,
          tone: ds.danger,
          topBorder: false,
          trailing: collapsible
              ? Icon(
                  expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 14,
                  color: ds.ink3,
                )
              : null,
          onTap: collapsible ? toggle : null,
        ),
      );
      for (var i = 0; i < shown.length; i++) {
        widgets.add(
          _timelineItem(
            shown[i],
            timeColumn,
            section: _RecentSection.overdue,
            index: i,
          ),
        );
      }
      if (collapsible) {
        widgets.add(
          _entryRow(
            expanded ? l.collapseLabel : l.expandRemaining(hidden),
            onTap: toggle,
          ),
        );
      }
    }

    final missedItems = _injectRecentInstances(missed, _RecentSection.missed);
    if (missedItems.isNotEmpty || hasEarlierMissed) {
      widgets.add(
        A2GroupHead(
          label: l.missed,
          count: missedItems.isEmpty ? null : missedItems.length,
          countLabel: missedItems.isEmpty
              ? null
              : l.groupCountItems(missedItems.length),
          danger: true,
          tone: ds.danger,
          topBorder: false,
        ),
      );
      final shownMissed = _missedExpanded
          ? missedItems
          : missedItems.take(3).toList();
      for (var i = 0; i < shownMissed.length; i++) {
        widgets.add(
          _missedInstanceRow(
            shownMissed[i],
            section: _RecentSection.missed,
            index: i,
          ),
        );
      }
      final moreMissed = missedItems.length - shownMissed.length;
      if (moreMissed > 0) {
        widgets.add(
          _entryRow(
            _missedExpanded ? l.collapseLabel : l.expandRemaining(moreMissed),
            onTap: () => setState(() => _missedExpanded = !_missedExpanded),
          ),
        );
      }
      if (hasEarlierMissed) {
        widgets.add(
          _entryRow(
            _earlierMissedExpanded ? l.collapseLabel : l.earlierMissed,
            onTap: () => setState(
              () => _earlierMissedExpanded = !_earlierMissedExpanded,
            ),
          ),
        );
        if (_earlierMissedExpanded) {
          for (final todo in earlierMissed) {
            widgets.add(_seriesRow(todo));
          }
        }
      }
    }

    if (endedItems.isNotEmpty) {
      widgets.add(
        A2GroupHead(
          label: l.actionEarlierToday,
          count: endedItems.length,
          topBorder: false,
        ),
      );
      for (var i = 0; i < endedItems.length; i++) {
        widgets.add(
          _timelineItem(
            endedItems[i],
            timeColumn,
            section: _RecentSection.ended,
            index: i,
          ),
        );
      }
    }

    // Completed work stays folded at the end of the timeline (CORE_UX_SPEC
    // §2.6 / SPEC rule 18): one head with its count is the whole default.
    if (completedCount > 0) {
      widgets.add(
        A2GroupHead(
          label: l.completedTodaySection,
          count: completedCount,
          countLabel: l.groupCountItems(completedCount),
          topBorder: false,
          trailing: Icon(
            _completedExpanded
                ? CupertinoIcons.chevron_up
                : CupertinoIcons.chevron_down,
            size: 14,
            color: ds.ink3,
          ),
          onTap: () => setState(() => _completedExpanded = !_completedExpanded),
        ),
      );
      if (_completedExpanded) {
        for (final todo in completedTodos) {
          widgets.add(_completedTodoRow(todo));
        }
        for (final instance in completedInstances) {
          widgets.add(_completedInstanceRow(instance));
        }
      }
    }

    return widgets;
  }

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

  List<ProjectedTaskInstance> _injectRecentInstances(
    List<ProjectedTaskInstance> items,
    _RecentSection section,
  ) {
    final recent = _recent;
    final snapshot = recent?.instance;
    if (recent == null || snapshot == null || recent.section != section) {
      return items;
    }
    final key = _keyOf(recent.todo.id, recent.occurrenceId);
    if (items.any((item) => _keyOf(item.todo.id, item.occurrenceId) == key)) {
      return items;
    }
    final index = recent.index.clamp(0, items.length);
    return [...items.take(index), snapshot, ...items.skip(index)];
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

  Widget _timelineItem(
    DayItem item,
    double timeColumn, {
    _RecentSection section = _RecentSection.upcoming,
    int index = 0,
  }) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final isOverdue = item.kind == DayItemKind.deadline && _isOverdue(item);
    final timeLabel = switch (item.kind) {
      DayItemKind.event || DayItemKind.allocation =>
        item.allDay ? l.allDayLabel : DateFormatters.formatTime(item.start!),
      DayItemKind.deadline =>
        isOverdue
            ? DateFormat.Md(_locale).format(item.todo!.dueDate!.toLocal())
            : item.start == null
            ? l.today
            : DateFormatters.formatTime(item.start!),
      DayItemKind.instance =>
        item.start == null || item.allDay
            ? l.allDayLabel
            : DateFormatters.formatTime(item.start!),
    };
    final duration =
        item.kind == DayItemKind.event &&
            !item.allDay &&
            item.end != null &&
            item.start != null
        ? _minutes(item.end!.difference(item.start!).inMinutes)
        : null;
    final kind = switch (item.kind) {
      DayItemKind.event => A2BlockKind.event,
      DayItemKind.allocation => A2BlockKind.allocation,
      DayItemKind.deadline => A2BlockKind.due,
      DayItemKind.instance => A2BlockKind.due,
    };
    final accent = item.kind == DayItemKind.event
        ? item.calendarColor ?? ds.ink3
        : item.kind == DayItemKind.allocation
        ? ds.work
        : isOverdue
        ? ds.danger
        : ds.warn;
    final fill = item.kind == DayItemKind.event && item.calendarColor != null
        ? Color.alphaBlend(
            item.calendarColor!.withValues(alpha: 0.10),
            ds.surface,
          )
        : null;
    return A2TimelineItem(
      timeLabel: timeLabel,
      durationLabel: duration,
      timeColor: isOverdue
          ? ds.danger
          : item.kind == DayItemKind.deadline && !isOverdue
          ? ds.warn
          : null,
      timeColumn: timeColumn,
      child: _block(
        l,
        item,
        kind: kind,
        accent: accent,
        fill: fill,
        section: section,
        index: index,
      ),
    );
  }

  Widget _block(
    AppLocalizations l,
    DayItem item, {
    required A2BlockKind kind,
    required Color accent,
    Color? fill,
    _RecentSection section = _RecentSection.upcoming,
    int index = 0,
  }) {
    final ds = context.ds;
    final isOverdue = item.kind == DayItemKind.deadline && _isOverdue(item);
    final recent =
        item.todo != null && _recentMatches(item.todo!.id, item.occurrenceId);
    final done = item.completed || recent;
    final meta = <Widget>[];
    switch (item.kind) {
      case DayItemKind.event:
        if (item.calendarName != null) {
          meta.add(A2MetaText(item.calendarName!));
          meta.add(const A2Sep());
        }
        if (item.start != null && item.end != null) {
          meta.add(
            A2MetaText(
              '${DateFormatters.formatTime(item.start!)}–'
              '${DateFormatters.formatTime(item.end!)}',
            ),
          );
        }
      case DayItemKind.allocation:
        if (item.start != null && item.end != null) {
          meta.add(
            A2MetaText(
              l.plannedRangeLabel(
                '${DateFormatters.formatTime(item.start!)}–'
                '${DateFormatters.formatTime(item.end!)}',
              ),
              color: ds.work,
            ),
          );
        }
        final due = item.todo?.dueDate?.toLocal();
        if (due != null) {
          // T3: the merged block's tick completes the allocation and the
          // deadline as one fact, so the meta records both the completion and
          // the deadline it closed.
          if (done) {
            meta.add(const A2Sep());
            final completedAt = recent
                ? _recent?.completedAt
                : item.todo?.completedAt;
            meta.add(
              A2MetaText(_completedText(l, completedAt), color: ds.ink3),
            );
          }
          meta.add(const A2Sep());
          meta.add(A2MetaText(_dueText(l, due), color: ds.ink3));
        } else if (done) {
          final completedAt = recent
              ? _recent?.completedAt
              : item.todo?.completedAt;
          meta.add(const A2Sep());
          meta.add(A2MetaText(_completedText(l, completedAt), color: ds.ink3));
        }
      case DayItemKind.deadline:
        meta.add(
          A2MetaText(
            _dueText(l, item.todo!.dueDate!.toLocal(), prefixToday: true),
            color: isOverdue ? ds.danger : ds.warn,
            weight: FontWeight.w500,
          ),
        );
        if (done) {
          meta.add(const A2Sep());
          meta.add(A2MetaText(l.completed, color: ds.ink3));
        }
      case DayItemKind.instance:
        if (done) {
          meta.add(A2MetaText(l.completed, color: ds.ink3));
        }
    }
    if (item.kind == DayItemKind.deadline && isOverdue) {
      final days = _today
          .difference(
            DateTime(
              item.todo!.dueDate!.year,
              item.todo!.dueDate!.month,
              item.todo!.dueDate!.day,
            ),
          )
          .inDays;
      final due = item.todo!.dueDate!.toLocal();
      final hasTime = due.hour != 0 || due.minute != 0;
      // The time column already prints the date of an overdue row, so the meta
      // carries only what the column lacks. Repeating the date there pushed
      // the lateness past the ellipsis ("Due 11/11 10...").
      meta
        ..clear()
        ..add(
          A2MetaText(
            l.dueValueLabel(
              hasTime
                  ? DateFormatters.formatTime(due)
                  : DateFormat.Md(_locale).format(due),
            ),
            color: ds.danger,
            weight: FontWeight.w500,
          ),
        )
        ..add(const A2Sep())
        ..add(A2MetaText(l.overdueDays(days), color: ds.danger));
      if (done) {
        meta.add(const A2Sep());
        meta.add(A2MetaText(l.completed, color: ds.ink3));
      }
    }
    // The action chip ends the meta line, as in the design. It is a fixed mark
    // and the prose beside it gives way first, so the two cannot starve each
    // other; making it a row trailing would cut the two-line title instead.
    final scheduleChip =
        (item.kind == DayItemKind.deadline ||
                item.kind == DayItemKind.instance) &&
            !done
        ? A2InlineChip(
            label: l.scheduleAction,
            color: ds.warn,
            background: ds.warnSoft,
            onTap: () => _scheduleTodo(item.todo!),
          )
        : null;
    if (scheduleChip != null) {
      meta.add(const SizedBox(width: 6));
      meta.add(scheduleChip);
    }
    final recentState = _recent;
    final undo = recent && recentState != null
        ? _undoAction(recentState)
        : null;
    final checkable = item.kind != DayItemKind.event;
    return A2Block(
      kind: kind,
      title: item.title,
      accent: accent,
      fill: fill,
      done: done,
      checked: done,
      meta: meta,
      trailing: undo,
      onToggle: checkable ? (_) => _toggleItem(item, section, index) : null,
      onTap: item.kind == DayItemKind.event
          ? () => _openEvent(item.event!)
          : () => _openTodo(item.todo!),
    );
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

  bool _isOverdue(DayItem item) {
    final due = item.todo?.dueDate?.toLocal();
    if (due == null) return false;
    return DateTime(due.year, due.month, due.day).isBefore(_today);
  }

  String _minutes(int total) {
    final l = AppLocalizations.of(context)!;
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0) return l.durationMinutes(m);
    if (m == 0) return l.durationHours(h);
    return l.durationHoursMinutes(h, m);
  }

  Widget _unplannedRow(
    AppLocalizations l,
    Todo todo, {
    bool highlighted = false,
    bool compact = false,
    int index = 0,
  }) {
    final ds = context.ds;
    final recent = todo.id == _recentId;
    final undo =
        _recent != null &&
            _recent!.section == _RecentSection.unplanned &&
            _recentMatches(todo.id, null)
        ? _recent
        : null;
    return _maybeHover(
      builder: (background) => A2Row(
        title: todo.summary,
        checked: undo != null,
        background: highlighted ? ds.surface2 : background,
        padding: compact
            ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
            : const EdgeInsets.fromLTRB(12, 8, 16, 8),
        meta: [
          A2MetaText(recent ? l.justAddedLabel : l.inbox),
          const A2Sep(),
          A2MetaText(_calendarName(todo) ?? ''),
        ],
        onToggle: (_) => _toggleUnplanned(todo, index),
        // The row is the object; scheduling is a distinct, explicit action so
        // tapping a title can no longer hijack the detail view.
        onTap: () => _openTodo(todo),
        trailing: undo != null
            ? _undoAction(undo)
            : A2IconAction(
                icon: CupertinoIcons.calendar,
                tooltip: l.scheduleAction,
                onPressed: () => _scheduleTodo(todo),
              ),
      ),
    );
  }

  String? _calendarName(Todo todo) {
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    for (final calendar in calendars) {
      if (calendar.id == todo.calendarId) return calendar.name;
    }
    return null;
  }

  Widget _missedInstanceRow(
    ProjectedTaskInstance instance, {
    _RecentSection section = _RecentSection.missed,
    int index = 0,
  }) {
    final calendar = _calendarName(instance.todo);
    final undo =
        _recent != null &&
            _recent!.section == section &&
            _recentMatches(instance.todo.id, instance.occurrenceId)
        ? _recent
        : null;
    return _maybeHover(
      builder: (background) => A2Row(
        title: instance.todo.summary,
        checked: undo != null,
        background: background,
        meta: [
          A2MetaText(instance.occurrence.displayLabel),
          if (calendar != null) ...[const A2Sep(), A2MetaText(calendar)],
        ],
        onToggle: (_) => _toggleMissed(instance, index),
        onTap: () => _openTodo(instance.todo),
        trailing: undo != null ? _undoAction(undo) : null,
      ),
    );
  }

  Widget _completedTodoRow(Todo todo) {
    final calendar = _calendarName(todo);
    return _maybeHover(
      builder: (background) => A2Row(
        title: todo.summary,
        checked: true,
        background: background,
        meta: [if (calendar != null) A2MetaText(calendar)],
        // A completed row cannot be completed again; tapping its check undoes
        // the completion through the same writer, occurrence id and all.
        onToggle: (_) => _setCompleted(todo, null, false),
        onTap: () => _openTodo(todo),
      ),
    );
  }

  Widget _completedInstanceRow(ProjectedTaskInstance instance) {
    final calendar = _calendarName(instance.todo);
    return _maybeHover(
      builder: (background) => A2Row(
        title: instance.todo.summary,
        checked: true,
        background: background,
        meta: [
          A2MetaText(instance.occurrence.displayLabel),
          if (calendar != null) ...[const A2Sep(), A2MetaText(calendar)],
        ],
        onToggle: (_) =>
            _setCompleted(instance.todo, instance.occurrenceId, false),
        onTap: () => _openTodo(instance.todo),
      ),
    );
  }

  Widget _seriesRow(Todo todo) {
    final calendar = _calendarName(todo);
    return _maybeHover(
      builder: (background) => A2Row(
        title: todo.summary,
        showCheck: false,
        background: background,
        meta: [if (calendar != null) A2MetaText(calendar)],
        onTap: () => _openTodo(todo),
      ),
    );
  }

  /// A disclosure that is a row, not a section head: 13/400 tertiary text in
  /// the title column, exactly as the design prints "还有 N 项 · 展开全部".
  Widget _entryRow(
    String label, {
    required VoidCallback onTap,
    double paddingLeft = 12,
  }) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.fromLTRB(paddingLeft, 8, 16, 8),
          child: Row(
            children: [
              const SizedBox(width: kA2CheckSlot),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: ds.ink3,
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

  /// Desktop rows highlight on hover, matching the todo list. On touch there
  /// is no hover, so the extra state is not installed at all.
  Widget _maybeHover({required Widget Function(Color? background) builder}) {
    if (!isWorkspaceLayout(context)) return builder(null);
    return _HoverWrap(
      builder: (hovered) => builder(hovered ? context.ds.surface2 : null),
    );
  }

  /// The bucket holds items the shelf never previews (they have a deadline);
  /// this row is the only honest way to say so and to reach them.
  Widget _showAllRow(AppLocalizations l, int count, {double paddingLeft = 12}) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpenUnplanned,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.fromLTRB(paddingLeft, 8, 16, 8),
          child: Row(
            children: [
              // The design puts this label in the row's own title column, not
              // at the page gutter: the ring slot and its gap are kept empty.
              const SizedBox(width: kA2CheckSlot),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.expandRemaining(count),
                  style: TextStyle(
                    fontSize: 13,
                    color: ds.ink3,
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

  Widget _moreRow(AppLocalizations l, int more, {double paddingLeft = 12}) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _unplannedExpanded = !_unplannedExpanded),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: EdgeInsets.fromLTRB(paddingLeft, 8, 16, 8),
          child: Row(
            children: [
              const SizedBox(width: kA2CheckSlot),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _unplannedExpanded
                      ? l.collapseLabel
                      : l.expandRemaining(more),
                  style: TextStyle(
                    fontSize: 13,
                    color: ds.ink3,
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
  missed,
  unplanned,
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
    this.instance,
  });

  final Todo todo;
  final String? occurrenceId;
  final String label;
  final _RecentSection section;
  final int index;
  final DateTime completedAt;
  final DayItem? item;
  final ProjectedTaskInstance? instance;
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
