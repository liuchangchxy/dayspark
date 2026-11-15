import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
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
  });

  final DateTime now;
  final ValueChanged<Todo> onOpenTodo;
  final ValueChanged<CalendaEventAdapter> onOpenEvent;
  final Future<void> Function(Todo todo, String? occurrenceId, bool completed)
  onToggleTodo;
  final VoidCallback onOpenUnplanned;
  final ValueChanged<Todo> onScheduleTodo;

  @override
  ConsumerState<A2TodayPage> createState() => _A2TodayPageState();
}

class _A2TodayPageState extends ConsumerState<A2TodayPage> {
  final ScrollController _scroll = ScrollController();
  int? _recentId;
  Timer? _recentTimer;
  bool _unplannedExpanded = false;
  bool _toastVisible = false;
  Timer? _toastTimer;
  bool _capturing = false;
  bool _captureFocused = false;
  double? _lastViewport;

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  String get _locale => Localizations.localeOf(context).toString();

  /// The keyboard arrives one or more frames after focus, and the Scaffold
  /// reserves its space by shrinking the body rather than by leaving an inset
  /// for this page to read. The shelf therefore follows the list's own
  /// viewport: when it shrinks under a focused capture row, the group the row
  /// feeds is scrolled back above it.
  void _onViewportChanged(ScrollMetrics metrics) {
    final previous = _lastViewport;
    _lastViewport = metrics.viewportDimension;
    if (previous == null || !_captureFocused) return;
    if (metrics.viewportDimension >= previous) return;
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
    _recentTimer?.cancel();
    _toastTimer?.cancel();
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

  Future<void> _toggle(Todo todo, String? occurrenceId) async {
    try {
      await widget.onToggleTodo(
        todo,
        occurrenceId,
        todo.status != 'COMPLETED',
      );
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
    }
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
    if (data.hasError) {
      debugPrint('today: projection error: ${data.error}');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.actionFailedRetry,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.ds.ink2,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      );
    }
    if (data.isLoading && !data.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    return list;
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
    final preview = <Todo>[
      for (final todo in unplanned)
        if (todo.dueDate == null) todo,
    ];
    final shown = _unplannedExpanded ? preview : preview.take(3).toList();
    final inPreview = preview;
    // What "Show less" can hide, and what the preview never carries: the
    // Unplanned bucket also holds todos that already have a deadline, and the
    // design keeps those out of the shelf. The head prints the bucket's real
    // count, so the shelf must offer a way to reach the rest.
    final expandable = inPreview.length - shown.length;
    final beyondShelf = unplannedCount - inPreview.length;
    final empty = agenda.isEmpty && preview.isEmpty;

    final children = <Widget>[
      if (!empty) ...[
        ..._sections(l, agenda, timeColumn: kA2TimeColumn),
        if (preview.isNotEmpty || unplannedCount > 0) ...[
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
                ? () => setState(
                    () => _unplannedExpanded = !_unplannedExpanded,
                  )
                : widget.onOpenUnplanned,
          ),
          for (final todo in shown)
            _unplannedRow(l, todo, highlighted: todo.id == _recentId),
          if (expandable > 0)
            _moreRow(l, expandable)
          else if (beyondShelf > 0)
            _showAllRow(l, beyondShelf),
        ],
      ],
      const SizedBox(height: 12),
    ];

    return Column(
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
            A2IconAction(
              icon: CupertinoIcons.settings,
              tooltip: l.settings,
              onPressed: () => context.push('/settings'),
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
                          child: ListView(
                            key: const ValueKey('a2-today-list'),
                            controller: _scroll,
                            padding: EdgeInsets.zero,
                            children: children,
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
          onSubmit: _capture,
          onFocusChange: (focused) {
            if (_captureFocused != focused) {
              setState(() => _captureFocused = focused);
            }
            if (focused) _scrollToShelf();
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------- desktop

  Widget _desktop(
    AppLocalizations l,
    AsyncValue<ActionProjectionData> data,
    DayAgenda agenda,
    List<Todo> unplanned,
    int unplannedCount,
  ) {
    final ds = context.ds;
    final noDue = <Todo>[
      for (final todo in unplanned)
        if (todo.dueDate == null) todo,
    ];
    // The panel scrolls, so it carries the whole shelf; only the bucket's
    // deadline-bearing items need a way out.
    final preview = noDue;
    final beyondShelf = unplannedCount - noDue.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _listSlot(
                  l,
                  data,
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: agenda.isEmpty
                          ? [
                              SizedBox(
                                height: 320,
                                child: A2Empty(
                                  title: l.emptyTodayTitle,
                                  hint: l.emptyTodayHint,
                                ),
                              ),
                            ]
                          : _sections(l, agenda, timeColumn: 46),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 320,
                child: Container(
                  decoration: BoxDecoration(
                    color: ds.surface,
                    border: Border.all(color: ds.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                    children: [
                      A2GroupHead(
                        label: l.inbox,
                        count: unplannedCount,
                        countLabel: l.groupCountItems(unplannedCount),
                        topBorder: false,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        trailing: Icon(
                          CupertinoIcons.chevron_up,
                          size: 14,
                          color: ds.ink3,
                        ),
                        onTap: widget.onOpenUnplanned,
                      ),
                      if (preview.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Text(
                            l.unplannedGroupEmpty,
                            style: TextStyle(
                              fontSize: 12,
                              color: ds.ink3,
                              fontFamilyFallback: AppTypography.fallback,
                            ),
                          ),
                        ),
                      for (final todo in preview)
                        _unplannedRow(l, todo, compact: true),
                      if (beyondShelf > 0)
                        _showAllRow(l, beyondShelf),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sections

  List<Widget> _sections(
    AppLocalizations l,
    DayAgenda agenda, {
    required double timeColumn,
  }) {
    final ds = context.ds;
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
    final widgets = <Widget>[];

    if (running.isNotEmpty) {
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
      for (final item in running) {
        widgets.add(_timelineItem(item, timeColumn));
      }
    }

    if (rest.isNotEmpty || agenda.instances.isNotEmpty) {
      widgets.add(
        A2GroupHead(label: l.sectionUpcoming, topBorder: false),
      );
      for (final item in rest) {
        widgets.add(_timelineItem(item, timeColumn));
      }
      for (final instance in agenda.instances) {
        widgets.add(
          A2TimelineItem(
            timeLabel: l.allDayLabel,
            timeColumn: timeColumn,
            child: _block(
              l,
              instance,
              kind: A2BlockKind.due,
              accent: ds.work,
            ),
          ),
        );
      }
    }

    if (agenda.dueTodos.isNotEmpty) {
      widgets.add(
        A2GroupHead(
          label: l.sectionDueToday,
          count: agenda.dueTodos.length,
          tone: ds.warn,
          topBorder: false,
        ),
      );
      for (final item in agenda.dueTodos) {
        widgets.add(_timelineItem(item, timeColumn));
      }
    }

    if (agenda.overdueTodos.isNotEmpty) {
      widgets.add(
        A2GroupHead(
          label: l.sectionOverdueLabel,
          count: agenda.overdueTodos.length,
          danger: true,
          tone: ds.danger,
          topBorder: false,
        ),
      );
      for (final item in agenda.overdueTodos) {
        widgets.add(_timelineItem(item, timeColumn));
      }
    }

    if (ended.isNotEmpty) {
      widgets.add(
        A2GroupHead(
          label: l.actionEarlierToday,
          count: ended.length,
          topBorder: false,
        ),
      );
      for (final item in ended) {
        widgets.add(_timelineItem(item, timeColumn));
      }
    }

    return widgets;
  }

  /// Ended: the item has a span and that span closed before the clock.
  bool _hasEnded(DayItem item) {
    final end = item.end;
    if (end == null || item.allDay) return false;
    return !end.isAfter(widget.now);
  }

  Widget _timelineItem(DayItem item, double timeColumn) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final isOverdue = item.kind == DayItemKind.deadline &&
        _isOverdue(item);
    final timeLabel = switch (item.kind) {
      DayItemKind.event || DayItemKind.allocation =>
        item.allDay ? l.allDayLabel : DateFormatters.formatTime(item.start!),
      DayItemKind.deadline => isOverdue
          ? DateFormat.Md(_locale).format(item.todo!.dueDate!.toLocal())
          : item.start == null
          ? l.today
          : DateFormatters.formatTime(item.start!),
      DayItemKind.instance => l.allDayLabel,
    };
    final duration = item.kind == DayItemKind.event &&
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
      child: _block(l, item, kind: kind, accent: accent, fill: fill),
    );
  }

  Widget _block(
    AppLocalizations l,
    DayItem item, {
    required A2BlockKind kind,
    required Color accent,
    Color? fill,
  }) {
    final ds = context.ds;
    final isOverdue = item.kind == DayItemKind.deadline && _isOverdue(item);
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
          meta.add(const A2Sep());
          meta.add(A2MetaText(_dueText(l, due), color: ds.ink3));
        }
      case DayItemKind.deadline:
        meta.add(
          A2MetaText(
            _dueText(
              l,
              item.todo!.dueDate!.toLocal(),
              prefixToday: true,
            ),
            color: isOverdue ? ds.danger : ds.warn,
            weight: FontWeight.w500,
          ),
        );
      case DayItemKind.instance:
        break;
    }
    if (item.kind == DayItemKind.deadline && isOverdue) {
      final days = _today
          .difference(DateTime(
            item.todo!.dueDate!.year,
            item.todo!.dueDate!.month,
            item.todo!.dueDate!.day,
          ))
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
    }
    // The action chip ends the meta line, as in the design. It is a fixed mark
    // and the prose beside it gives way first, so the two cannot starve each
    // other; making it a row trailing would cut the two-line title instead.
    final scheduleChip =
        item.kind == DayItemKind.deadline || item.kind == DayItemKind.instance
        ? A2InlineChip(
            label: l.scheduleAction,
            color: ds.warn,
            background: ds.warnSoft,
            onTap: () => widget.onScheduleTodo(item.todo!),
          )
        : null;
    if (scheduleChip != null) {
      meta.add(const SizedBox(width: 6));
      meta.add(scheduleChip);
    }
    final checkable = item.kind != DayItemKind.event;
    return A2Block(
      kind: kind,
      title: item.title,
      accent: accent,
      fill: fill,
      done: item.completed,
      checked: item.completed,
      meta: meta,
      onToggle: checkable
          ? (_) => _toggle(item.todo!, item.occurrenceId)
          : null,
      onTap: item.kind == DayItemKind.event
          ? () => widget.onOpenEvent(item.event!)
          : () => widget.onOpenTodo(item.todo!),
    );
  }

  String _dueText(AppLocalizations l, DateTime due, {bool prefixToday = false}) {
    final isToday = due.year == _today.year &&
        due.month == _today.month &&
        due.day == _today.day;
    final hasTime = due.hour != 0 || due.minute != 0;
    if (isToday && hasTime) {
      return prefixToday
          ? l.dueTodayTimeLabel(DateFormatters.formatTime(due))
          : l.dueValueLabel(DateFormatters.formatTime(due));
    }
    final date = DateFormat.Md(_locale).format(due);
    return l.dueValueLabel(hasTime ? '$date ${DateFormatters.formatTime(due)}' : date);
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
  }) {
    final ds = context.ds;
    final recent = todo.id == _recentId;
    return A2Row(
      title: todo.summary,
      checked: false,
      background: highlighted ? ds.primarySoft : null,
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : const EdgeInsets.fromLTRB(12, 8, 16, 8),
      meta: [
        A2MetaText(recent ? l.justAddedLabel : l.inbox),
        const A2Sep(),
        A2MetaText(_calendarName(todo) ?? ''),
      ],
      onToggle: (_) => _toggle(todo, null),
      onTap: () => widget.onScheduleTodo(todo),
    );
  }

  String? _calendarName(Todo todo) {
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    for (final calendar in calendars) {
      if (calendar.id == todo.calendarId) return calendar.name;
    }
    return null;
  }

  /// The bucket holds items the shelf never previews (they have a deadline);
  /// this row is the only honest way to say so and to reach them.
  Widget _showAllRow(
    AppLocalizations l,
    int count, {
    double paddingLeft = 12,
  }) {
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
                  _unplannedExpanded ? l.collapseLabel : l.expandRemaining(more),
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
