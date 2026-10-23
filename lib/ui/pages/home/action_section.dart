import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// Action answers exactly one question: what needs me now.
///
/// It therefore holds no filters, no management affordances and no diagnostics.
/// Everything it lists is either happening, overdue, or due today — and each
/// row opens the object's detail, never a form.
class ActionSection extends ConsumerStatefulWidget {
  const ActionSection({
    super.key,
    this.onNavigateToCalendar,
    this.onEventTap,
    this.onTodoTap,
    this.onEventEdit,
    this.onTodoEdit,
  });

  final VoidCallback? onNavigateToCalendar;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(Todo todo)? onTodoTap;
  final void Function(CalendaEventAdapter event)? onEventEdit;
  final void Function(Todo todo)? onTodoEdit;

  @override
  ConsumerState<ActionSection> createState() => _ActionSectionState();
}

class _ActionSectionState extends ConsumerState<ActionSection> {
  Todo? _selectedTodo;
  CalendaEventAdapter? _selectedEvent;

  bool get _hasSelection => _selectedTodo != null || _selectedEvent != null;

  void _selectTodo(BuildContext context, Todo todo) {
    if (!isWorkspaceLayout(context)) {
      widget.onTodoTap?.call(todo);
      return;
    }
    setState(() {
      _selectedTodo = todo;
      _selectedEvent = null;
    });
  }

  void _selectEvent(BuildContext context, CalendaEventAdapter event) {
    if (!isWorkspaceLayout(context)) {
      widget.onEventTap?.call(event);
      return;
    }
    setState(() {
      _selectedEvent = event;
      _selectedTodo = null;
    });
  }

  void _clearSelection() => setState(() {
    _selectedTodo = null;
    _selectedEvent = null;
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildControls(context),
        Expanded(child: _buildContent(context, ref)),
      ],
    );
    if (!isWorkspaceLayout(context) || !_hasSelection) return content;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _clearSelection,
      },
      child: Focus(
        autofocus: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            _Inspector(
              todo: _selectedTodo,
              event: _selectedEvent,
              onClose: _clearSelection,
              onEdit: () {
                if (_selectedTodo != null) {
                  widget.onTodoEdit?.call(_selectedTodo!);
                } else {
                  widget.onEventEdit?.call(_selectedEvent!);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 700;
    final date = ref.watch(actionDateProvider);
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? AppSpacing.lg : 28,
        0,
        mobile ? AppSpacing.lg : 28,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          if (mobile)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: List.generate(7, (index) {
                  final day = monday.add(Duration(days: index));
                  final selected = DateUtils.isSameDay(day, date);
                  return Expanded(
                    child: SizedBox(
                      height: 64,
                      child: TextButton(
                        key: ValueKey('action-week-$index'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          backgroundColor: selected
                              ? theme.colorScheme.primary.withValues(alpha: .09)
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () =>
                            ref.read(actionDateProvider.notifier).state =
                                DateTime(day.year, day.month, day.day),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat.E(
                                Localizations.localeOf(context).toString(),
                              ).format(day),
                              style: AppTypography.overline,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${day.day}',
                              style: AppTypography.title.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          Row(
            children: [
              Expanded(child: _buildSummary(context, ref, theme, l)),
              if (widget.onNavigateToCalendar != null)
                IconButton(
                  tooltip: l.calendar,
                  onPressed: widget.onNavigateToCalendar,
                  icon: const Icon(CupertinoIcons.calendar, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (!mobile) _buildRhythm(context, ref, theme, date),
        ],
      ),
    );
  }

  Widget _buildRhythm(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    DateTime date,
  ) {
    const startMinute = 6 * 60;
    const endMinute = 22 * 60;
    const span = endMinute - startMinute;
    final data = ref.watch(actionProjectionProvider).valueOrNull;
    final entries = <_TimelineEntry>[
      if (data != null) ...data.events.map(_TimelineEntry.event),
      if (data != null) ...data.allocations.map(_TimelineEntry.allocation),
    ];
    final now = DateTime.now();
    final dayStart = DateTime(date.year, date.month, date.day);
    double ratio(DateTime value) =>
        ((value.difference(dayStart).inMinutes - startMinute) / span).clamp(
          0.0,
          1.0,
        );
    final showNow =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final nowRatio = ((now.hour * 60 + now.minute - startMinute) / span).clamp(
      0.0,
      1.0,
    );

    return Padding(
      key: const ValueKey('action-rhythm'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = math.max(80.0, constraints.maxWidth - 12 - 138);
          return Row(
            children: [
              SizedBox(
                width: trackWidth,
                height: 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    for (final entry in entries)
                      if (entry.end.difference(dayStart).inMinutes >
                              startMinute &&
                          entry.start.difference(dayStart).inMinutes <
                              endMinute)
                        Positioned(
                          left: ratio(entry.start) * trackWidth,
                          width: math.max(
                            2.0,
                            (ratio(entry.end) - ratio(entry.start)) *
                                trackWidth,
                          ),
                          top: 1,
                          bottom: 1,
                          child: _rhythmBlock(theme, entry),
                        ),
                    if (showNow)
                      Positioned(
                        left: nowRatio * trackWidth - 0.75,
                        top: -2,
                        bottom: -2,
                        child: Container(
                          width: 1.5,
                          color: AppColors.brandWarm,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 138,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final hour in [6, 9, 12, 15, 18, 21])
                      Text(
                        hour.toString().padLeft(2, '0'),
                        style: AppTypography.overline.copyWith(
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rhythmBlock(ThemeData theme, _TimelineEntry entry) {
    final color = entry.isEvent
        ? (entry.event!.color ?? theme.colorScheme.primary)
        : theme.colorScheme.secondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: entry.isEvent ? .36 : .12),
        borderRadius: BorderRadius.circular(2),
        border: entry.isEvent
            ? null
            : Border.all(color: color.withValues(alpha: .55), width: 1),
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AppLocalizations l,
  ) {
    final data = ref.watch(actionProjectionProvider).valueOrNull;
    final events = data?.events.length ?? 0;
    final allocations = data?.allocations.length ?? 0;
    final overdue =
        (data?.overdueTodos.length ?? 0) +
        (data?.missedTaskInstances.length ?? 0);
    if (events == 0 && allocations == 0 && overdue == 0) {
      return Text(
        l.nothingScheduled,
        style: AppTypography.caption.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final separator = Text(
      ' · ',
      style: AppTypography.caption.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
    return Row(
      children: [
        Text(
          '$events ${l.calendarLegendEvent}',
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        separator,
        Text(
          '$allocations ${l.calendarLegendAllocation}',
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (overdue > 0) ...[
          separator,
          Text(
            '$overdue ${l.overdue}',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final projectionAsync = ref.watch(actionProjectionProvider);
    final horizontal = isWorkspaceLayout(context) ? 28.0 : AppSpacing.lg;

    return projectionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (data) {
        final totalOverdue =
            data.overdueTodos.length + data.missedTaskInstances.length;
        final totalCompleted =
            data.completedTodayTodos.length +
            data.completedTodayTaskInstances.length;
        final hasTimeline =
            data.events.isNotEmpty || data.allocations.isNotEmpty;
        final hasDueToday = data.dueTodayTodos.isNotEmpty;
        final hasTodayTasks = data.todayTaskInstances.isNotEmpty;

        if (totalOverdue == 0 &&
            !hasTimeline &&
            !hasDueToday &&
            !hasTodayTasks &&
            totalCompleted == 0) {
          return _emptyState(context, ref, l, theme);
        }

        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: AppSpacing.lg,
          ),
          children: [
            if (totalOverdue > 0) ...[
              _SectionHeader(
                title: '${l.overdue} · $totalOverdue',
                accent: theme.colorScheme.error,
              ),
              ...data.overdueTodos.map(
                (todo) => _buildOverdueTile(context, ref, todo, l),
              ),
              ...data.missedTaskInstances.map(
                (instance) =>
                    _buildMissedInstanceTile(context, ref, instance, l),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (data.todayTaskInstances.isNotEmpty) ...[
              _SectionHeader(title: l.todayTasks),
              ...data.todayTaskInstances.map(
                (instance) => _ActionRow(
                  key: ValueKey('action-instance-${instance.occurrenceId}'),
                  time: null,
                  dateHint: instance.occurrence.displayLabel,
                  icon: CupertinoIcons.repeat,
                  iconColor: theme.colorScheme.secondary,
                  title: instance.todo.summary,
                  meta: l.recurringTask,
                  completed: false,
                  onToggle: () => ref.read(toggleTodoProvider)(
                    id: instance.todoId,
                    isCompleted: true,
                    occurrenceId: instance.occurrenceId,
                  ),
                  onTap: () => _selectTodo(context, instance.todo),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (hasTimeline) ...[
              ..._buildTimelineItems(context, ref, data, l, theme),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (hasDueToday) ...[
              _SectionHeader(
                title: '${l.dueTodaySection} · ${data.dueTodayTodos.length}',
                accent: theme.colorScheme.primary,
              ),
              ...data.dueTodayTodos.map(
                (todo) => _buildDueTodayTile(context, ref, todo, l),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (totalCompleted > 0)
              _CompletedFold(
                count: totalCompleted,
                children: [
                  ...data.completedTodayTodos.map(
                    (todo) => _buildCompletedTile(context, ref, todo, l, theme),
                  ),
                  ...data.completedTodayTaskInstances.map(
                    (instance) => _buildCompletedInstanceTile(
                      context,
                      ref,
                      instance,
                      l,
                      theme,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// Nothing to do is a good outcome, so it is stated plainly rather than
  /// filled with management shortcuts.
  Widget _emptyState(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                CupertinoIcons.bolt,
                size: 40,
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l.actionNothingNow, style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.actionNothingNowHint,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverdueTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
  ) {
    return _ActionRow(
      key: ValueKey('action-overdue-${todo.id}'),
      time: todo.dueDate == null
          ? null
          : DateFormatters.formatTime(todo.dueDate!),
      dateHint: todo.dueDate == null
          ? null
          : DateFormatters.formatShortDate(todo.dueDate!),
      icon: CupertinoIcons.exclamationmark_triangle,
      iconColor: Theme.of(context).colorScheme.error,
      title: todo.summary,
      meta: todo.dueDate == null
          ? l.overdue
          : l.deadlinePrefix(DateFormatters.formatDate(todo.dueDate!)),
      completed: false,
      onToggle: () =>
          ref.read(toggleTodoProvider)(id: todo.id, isCompleted: true),
      onTap: () => _selectTodo(context, todo),
    );
  }

  Widget _buildMissedInstanceTile(
    BuildContext context,
    WidgetRef ref,
    ProjectedTaskInstance instance,
    AppLocalizations l,
  ) {
    return _ActionRow(
      key: ValueKey('action-missed-${instance.occurrenceId}'),
      time: null,
      dateHint: instance.occurrence.displayLabel,
      icon: CupertinoIcons.exclamationmark_triangle,
      iconColor: Theme.of(context).colorScheme.error,
      title: instance.todo.summary,
      meta: l.missed,
      completed: false,
      onToggle: () => ref.read(toggleTodoProvider)(
        id: instance.todoId,
        isCompleted: true,
        occurrenceId: instance.occurrenceId,
      ),
      onTap: () => _selectTodo(context, instance.todo),
    );
  }

  List<Widget> _buildTimelineItems(
    BuildContext context,
    WidgetRef ref,
    ActionProjectionData data,
    AppLocalizations l,
    ThemeData theme,
  ) {
    final now = DateTime.now();
    final date = ref.read(actionDateProvider);
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final items = <_TimelineEntry>[
      ...data.events.map(_TimelineEntry.event),
      ...data.allocations.map(_TimelineEntry.allocation),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // "Now" and "Later today" only mean something on the actual current day.
    // Any other day is simply that day's schedule, in time order.
    if (!isToday) {
      return [
        _SectionHeader(title: l.todayTimeline),
        for (final entry in items)
          _buildTimelineEntry(context, ref, entry, l, theme),
      ];
    }

    final current = items
        .where((entry) => !entry.start.isAfter(now) && entry.end.isAfter(now))
        .toList();
    final later = items.where((entry) => entry.start.isAfter(now)).toList();

    final rows = <Widget>[];
    if (current.isNotEmpty) {
      rows.add(_SectionHeader(title: l.actionNow, accent: AppColors.brandWarm));
      for (final entry in current) {
        rows.add(_buildTimelineEntry(context, ref, entry, l, theme, warm: true));
      }
    }
    if (later.isNotEmpty) {
      rows.add(_SectionHeader(title: l.laterToday));
      for (final entry in later) {
        rows.add(_buildTimelineEntry(context, ref, entry, l, theme));
      }
    }
    return rows;
  }

  Widget _buildTimelineEntry(
    BuildContext context,
    WidgetRef ref,
    _TimelineEntry entry,
    AppLocalizations l,
    ThemeData theme, {
    bool warm = false,
  }) {
    if (entry.isEvent) {
      final event = entry.event!;
      return _ActionRow(
        key: ValueKey('action-event-${event.drifId}-${event.start.millisecondsSinceEpoch}'),
        time: DateFormatters.formatTime(entry.start),
        icon: CupertinoIcons.circle_fill,
        iconColor: event.color ?? theme.colorScheme.primary,
        title: event.title,
        meta:
            '${DateFormatters.formatTime(entry.start)} – ${DateFormatters.formatTime(entry.end)}',
        warm: warm,
        onTap: () => _selectEvent(context, event),
      );
    }
    final item = entry.allocation!;
    return _ActionRow(
      key: ValueKey('action-allocation-${item.allocation.id}'),
      time: DateFormatters.formatTime(item.allocation.startAt.toLocal()),
      icon: CupertinoIcons.square,
      iconColor: theme.colorScheme.secondary,
      title: item.todo.summary,
      meta:
          '${DateFormatters.formatTime(item.allocation.startAt.toLocal())} – ${DateFormatters.formatTime(item.allocation.endAt.toLocal())} · ${l.plannedExecution}',
      warm: warm,
      completed: false,
      onToggle: () => ref.read(toggleTodoProvider)(
        id: item.todo.id,
        isCompleted: true,
        occurrenceId: item.allocation.occurrenceId,
      ),
      onTap: () => _selectTodo(context, item.todo),
    );
  }

  Widget _buildDueTodayTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
  ) {
    return _ActionRow(
      key: ValueKey('action-due-${todo.id}'),
      time: todo.dueDate == null
          ? null
          : DateFormatters.formatTime(todo.dueDate!),
      icon: CupertinoIcons.flag,
      iconColor: context.semantic.warning,
      title: todo.summary,
      meta: l.deadlineToday,
      completed: false,
      onToggle: () => ref.read(toggleTodoProvider)(id: todo.id, isCompleted: true),
      onTap: () => _selectTodo(context, todo),
    );
  }

  Widget _buildCompletedTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRow(
      time: todo.completedAt == null
          ? null
          : DateFormatters.formatTime(todo.completedAt!),
      title: todo.summary,
      completed: true,
      onToggle: () =>
          ref.read(toggleTodoProvider)(id: todo.id, isCompleted: false),
      onTap: () => _selectTodo(context, todo),
    );
  }

  Widget _buildCompletedInstanceTile(
    BuildContext context,
    WidgetRef ref,
    ProjectedTaskInstance instance,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRow(
      time: instance.completedAt == null
          ? null
          : DateFormatters.formatTime(instance.completedAt!),
      title: instance.todo.summary,
      completed: true,
      onToggle: () => ref.read(toggleTodoProvider)(
        id: instance.todoId,
        isCompleted: false,
        occurrenceId: instance.occurrenceId,
      ),
      onTap: () => _selectTodo(context, instance.todo),
    );
  }
}

class _TimelineEntry {
  final CalendaEventAdapter? event;
  final TaskAllocationCalendarItem? allocation;
  final DateTime start;

  _TimelineEntry.event(CalendaEventAdapter e)
    : event = e,
      allocation = null,
      start = e.start;

  _TimelineEntry.allocation(TaskAllocationCalendarItem a)
    : event = null,
      allocation = a,
      start = a.allocation.startAt.toLocal();

  bool get isEvent => event != null;
  DateTime get end => event?.end ?? allocation!.allocation.endAt.toLocal();
}

/// One action row: time on the left, what it is in the middle, done on the
/// right. Flat — a hairline separates rows, nothing draws a box around one.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.title,
    this.time,
    this.dateHint,
    this.icon,
    this.iconColor,
    this.meta,
    this.warm = false,
    this.completed,
    this.onToggle,
    required this.onTap,
  });

  final String title;
  final String? time;
  final String? dateHint;
  final IconData? icon;
  final Color? iconColor;
  final String? meta;
  final bool warm;
  final bool? completed;
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 700;
    final muted = context.semantic.textSecondary;
    final titleStyle = AppTypography.body.copyWith(
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
      decoration: completed == true ? TextDecoration.lineThrough : null,
    );
    return Material(
      color: warm
          ? AppColors.brandWarm.withValues(alpha: .06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: mobile ? 56 : 48),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: mobile ? 52 : 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      time ?? (dateHint ?? ''),
                      style: AppTypography.caption.copyWith(
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    icon,
                    size: 12,
                    color:
                        iconColor ??
                        (completed == true
                            ? context.semantic.textTertiary
                            : muted),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: mobile
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                            if (meta != null && meta!.isNotEmpty)
                              Text(
                                meta!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: warm
                                      ? (theme.brightness == Brightness.dark
                                            ? AppColors.darkWarning
                                            : AppColors.brandWarm)
                                      : muted,
                                ),
                              ),
                          ],
                        )
                      : Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                            if (meta != null && meta!.isNotEmpty) ...[
                              const SizedBox(width: AppSpacing.md),
                              Flexible(
                                child: Text(
                                  meta!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(
                                    color: warm
                                        ? (theme.brightness == Brightness.dark
                                              ? AppColors.darkWarning
                                              : AppColors.brandWarm)
                                        : muted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: onToggle == null
                    ? Center(
                        child: Icon(
                          CupertinoIcons.chevron_forward,
                          size: 14,
                          color: context.semantic.textTertiary,
                        ),
                      )
                    : Checkbox(
                        value: completed ?? false,
                        onChanged: (_) => onToggle!(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.accent});

  final String title;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, top: AppSpacing.xs),
      child: Text(
        title,
        style: AppTypography.overline.copyWith(
          color: accent ?? context.semantic.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CompletedFold extends StatelessWidget {
  const _CompletedFold({required this.count, required this.children});

  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: Icon(
          CupertinoIcons.checkmark_seal,
          size: 16,
          color: context.semantic.textTertiary,
        ),
        title: Text(
          '${l.completedTodaySection} · $count',
          style: AppTypography.overline.copyWith(
            color: context.semantic.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: children,
      ),
    );
  }
}

/// Desktop-only reading pane for the selected action item.
///
/// It is a detail surface, not an editor: it shows what the row cannot (the
/// note, the planned block) and offers Edit as a separate, deliberate step.
class _Inspector extends ConsumerWidget {
  const _Inspector({
    required this.todo,
    required this.event,
    required this.onClose,
    required this.onEdit,
  });

  final Todo? todo;
  final CalendaEventAdapter? event;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isTodo = todo != null;
    final description = todo?.description ?? event?.description;
    final allocations = isTodo
        ? ref
              .watch(actionProjectionProvider)
              .valueOrNull
              ?.allocations
              .where((item) => item.todo.id == todo!.id)
              .toList()
        : null;

    return Container(
      key: const ValueKey('action-inspector'),
      width: 340,
      margin: const EdgeInsets.only(
        top: AppSpacing.lg,
        right: AppSpacing.xl,
        bottom: AppSpacing.lg,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isTodo ? l.todoDetails : l.eventDetails,
                    style: AppTypography.overline.copyWith(
                      color: context.semantic.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(CupertinoIcons.xmark, size: 16),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).closeButtonTooltip,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              todo?.summary ?? event!.title,
              style: AppTypography.headline,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (todo?.dueDate != null)
              ScheduleRow(
                label: l.deadline,
                value: formatDeadline(context, todo!.dueDate!),
              ),
            if (event != null) ...[
              ScheduleRow(
                label: l.startTime,
                value: DateFormatters.formatTime(event!.start),
              ),
              ScheduleRow(
                label: l.endTime,
                value: DateFormatters.formatTime(event!.end),
              ),
            ],
            for (final item in allocations ?? const [])
              ScheduleRow(
                label: l.executionSchedule,
                value: formatExecutionRange(
                  context,
                  item.allocation.startAt,
                  item.allocation.endAt,
                  includeDate: false,
                ),
              ),
            if (description != null && description.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(description, style: AppTypography.body),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(CupertinoIcons.pencil, size: 15),
                label: Text(isTodo ? l.editTodo : l.editEvent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
