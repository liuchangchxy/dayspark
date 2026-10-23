import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/task_allocations_section.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';

class ActionSection extends ConsumerStatefulWidget {
  const ActionSection({
    super.key,
    this.onNavigateToTodos,
    this.onNavigateToCalendar,
    this.onEventTap,
    this.onTodoTap,
  });

  final VoidCallback? onNavigateToTodos;
  final VoidCallback? onNavigateToCalendar;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(Todo todo)? onTodoTap;

  @override
  ConsumerState<ActionSection> createState() => _ActionSectionState();
}

class _ActionSectionState extends ConsumerState<ActionSection> {
  int _filter = 0;
  Todo? _selectedTodo;
  CalendaEventAdapter? _selectedEvent;

  void _selectTodo(BuildContext context, Todo todo) {
    if (MediaQuery.sizeOf(context).width < 1000) {
      widget.onTodoTap?.call(todo);
    } else {
      setState(() {
        _selectedTodo = todo;
        _selectedEvent = null;
      });
    }
  }

  void _selectEvent(BuildContext context, CalendaEventAdapter event) {
    if (MediaQuery.sizeOf(context).width < 1000) {
      widget.onEventTap?.call(event);
    } else {
      setState(() {
        _selectedEvent = event;
        _selectedTodo = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildControls(context),
        Expanded(child: _buildContent(context, ref)),
      ],
    );
    if (MediaQuery.sizeOf(context).width < 1000 ||
        (_selectedTodo == null && _selectedEvent == null)) {
      return content;
    }
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final details = _selectedTodo?.description ?? _selectedEvent?.description;
    final selectedAllocations =
        ref
            .watch(actionProjectionProvider)
            .valueOrNull
            ?.allocations
            .where((item) => item.todo.id == _selectedTodo?.id)
            .toList() ??
        <TaskAllocationCalendarItem>[];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
          _selectedTodo = null;
          _selectedEvent = null;
        }),
      },
      child: Focus(
        autofocus: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            Container(
              key: const ValueKey('action-inspector'),
              width: 320,
              margin: const EdgeInsets.only(top: 16, right: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedTodo != null ? l.todos : l.eventLabel,
                          style: AppTypography.caption,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _selectedTodo = null;
                          _selectedEvent = null;
                        }),
                        icon: const Icon(CupertinoIcons.xmark),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                      ),
                    ],
                  ),
                  Text(
                    _selectedTodo?.summary ?? _selectedEvent!.title,
                    style: AppTypography.headline,
                  ),
                  const SizedBox(height: 20),
                  if (_selectedTodo?.dueDate != null)
                    Text(
                      l.deadlinePrefix(
                        DateFormatters.formatDate(_selectedTodo!.dueDate!),
                      ),
                    ),
                  if (_selectedEvent != null)
                    Text(
                      '${DateFormatters.formatTime(_selectedEvent!.start)} – ${DateFormatters.formatTime(_selectedEvent!.end)}',
                    ),
                  if (details != null && details.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      details,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body,
                    ),
                  ],
                  for (final item in selectedAllocations)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${l.plannedExecution} · ${DateFormatters.formatTime(item.allocation.startAt.toLocal())} – ${DateFormatters.formatTime(item.allocation.endAt.toLocal())}',
                        style: AppTypography.caption,
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (_selectedTodo != null) {
                          widget.onTodoTap?.call(_selectedTodo!);
                        } else {
                          widget.onEventTap?.call(_selectedEvent!);
                        }
                      },
                      icon: const Icon(CupertinoIcons.pencil, size: 16),
                      label: Text(
                        _selectedTodo != null ? l.editTodo : l.editEvent,
                      ),
                    ),
                  ),
                ],
              ),
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
    final six = ref.watch(sixThingsModeProvider).valueOrNull ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 28, 0, mobile ? 16 : 28, 8),
      child: Column(
        children: [
          if (mobile)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 17,
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
              // D Final keeps the All / Events / Todos pills on mobile only;
              // desktop expresses the same information as a summary line.
              if (mobile)
                ...[
                  l.actionAll,
                  l.calendarLegendEvent,
                  l.todos,
                ].asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        foregroundColor: _filter == entry.key
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        backgroundColor: _filter == entry.key
                            ? theme.colorScheme.primary.withValues(alpha: .08)
                            : null,
                      ),
                      onPressed: () => setState(() => _filter = entry.key),
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                )
              else
                _buildSummary(context, ref, theme, l),
              const Spacer(),
              // The mobile row already carries three filter pills plus the
              // calendar action, so the six-things toggle stays desktop-only
              // here; mobile reaches it from the Todo tab strip.
              if (!mobile)
                TextButton.icon(
                  onPressed: () => ref.read(setSixThingsModeProvider)(!six),
                  icon: Icon(
                    six
                        ? CupertinoIcons.checkmark_square_fill
                        : CupertinoIcons.square_grid_2x2,
                    size: 16,
                  ),
                  label: Text(l.sixThings),
                ),
              if (widget.onNavigateToCalendar != null)
                IconButton(
                  tooltip: l.calendar,
                  onPressed: widget.onNavigateToCalendar,
                  icon: const Icon(CupertinoIcons.calendar, size: 18),
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
      padding: const EdgeInsets.only(top: 10),
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
              const SizedBox(width: 12),
              SizedBox(
                width: 138,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final hour in [6, 9, 12, 15, 18, 21])
                      Text(
                        hour.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 9,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
    final separator = Text(
      ' · ',
      style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
    );
    return Row(
      children: [
        Text(
          '$events ${l.calendarLegendEvent}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        separator,
        Text(
          '$allocations ${l.calendarLegendAllocation}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (overdue > 0) ...[
          separator,
          Text(
            '$overdue ${l.overdue}',
            style: TextStyle(
              fontSize: 12,
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

    return projectionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.error('$e'))),
      data: (data) {
        if (data.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.sparkles,
                    size: 48,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.emptyActionHint,
                    style: AppTypography.body.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildInboxCard(context, ref, data, l, theme),
                ],
              ),
            ),
          );
        }

        final totalOverdue =
            data.overdueTodos.length + data.missedTaskInstances.length;
        final totalCompleted =
            data.completedTodayTodos.length +
            data.completedTodayTaskInstances.length;

        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width >= 1000 ? 28 : 16,
            vertical: 16,
          ),
          children: [
            // Ruling C: Unconfirmed legacy/unsupported recurrence discovery card
            // 0. Recurrence expansion errors (Ruling A / C distinction)
            if (data.recurrenceExpansionErrors.isNotEmpty) ...[
              Card(
                elevation: 0,
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: data.recurrenceExpansionErrors.map((err) {
                    final message = err.error is RecurrenceExpansionException
                        ? (((err.error as RecurrenceExpansionException).message
                                  .contains('horizon'))
                              ? l.recurrenceTimezoneHorizonError
                              : (((err.error as RecurrenceExpansionException)
                                        .message
                                        .contains('limit'))
                                    ? l.recurrenceOccurrenceLimitError
                                    : (err.error
                                              as RecurrenceExpansionException)
                                          .message))
                        : '${err.error}';
                    return ListTile(
                      leading: Icon(
                        CupertinoIcons.exclamationmark_circle,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        err.todo.summary,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        message,
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // 0. Unconfirmed recurrence card (Ruling C)
            if (data.unconfirmedRecurringCount > 0) ...[
              Card(
                elevation: 0,
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    l.recurringNeedConfirmationCount(
                      data.unconfirmedRecurringCount,
                    ),
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    l.legacyRecurrenceRequiresConfirmation,
                    style: AppTypography.caption,
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 14,
                  ),
                  onTap: () async {
                    if (data.unconfirmedRecurringTodos.isNotEmpty) {
                      await TaskAllocationsSection.confirmLegacyRecurrence(
                        context,
                        ref,
                        data.unconfirmedRecurringTodos.first,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // 1. Overdue & Missed section
            if (_filter != 1 &&
                (totalOverdue > 0 ||
                    data.hasEarlierMissed ||
                    data.hasEarlierHistory)) ...[
              _buildSectionHeader(
                context,
                title: '${l.overdue} ($totalOverdue)',
                icon: CupertinoIcons.exclamationmark_triangle_fill,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.xs),
              ...data.overdueTodos.map(
                (todo) => _buildOverdueTile(context, ref, todo, l, theme),
              ),
              ...data.missedTaskInstances.map(
                (instance) =>
                    _buildMissedInstanceTile(context, ref, instance, l, theme),
              ),
              ...data.earlierMissedSeries.map(
                (series) =>
                    _buildEarlierMissedTile(context, ref, series, l, theme),
              ),
              ...data.earlierHistorySeries.map(
                (series) =>
                    _buildEarlierHistoryTile(context, ref, series, l, theme),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 2. Today's timeline (Events + TaskAllocations)
            if (data.events.isNotEmpty || data.allocations.isNotEmpty) ...[
              _buildSectionHeader(
                context,
                title: l.todayTimeline,
                icon: CupertinoIcons.clock,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.xs),
              ..._buildTimelineItems(context, ref, data, l, theme),
              const SizedBox(height: AppSpacing.md),
            ],

            // 3. Today's actionable recurring TaskInstances
            if (_filter != 1 && data.todayTaskInstances.isNotEmpty) ...[
              _buildSectionHeader(
                context,
                title: '${l.todayTasks} (${data.todayTaskInstances.length})',
                icon: CupertinoIcons.repeat,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.xs),
              ...data.todayTaskInstances.map(
                (instance) =>
                    _buildTodayInstanceTile(context, ref, instance, l, theme),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 4. Due Today section (ordinary todos)
            if (_filter != 1 && data.dueTodayTodos.isNotEmpty) ...[
              _buildSectionHeader(
                context,
                title: '${l.dueTodaySection} (${data.dueTodayTodos.length})',
                icon: CupertinoIcons.calendar_today,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: AppSpacing.xs),
              ...data.dueTodayTodos.map(
                (todo) => _buildDueTodayTile(context, ref, todo, l, theme),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 5. Compact Inbox / Unplanned entry
            _buildInboxCard(context, ref, data, l, theme),
            const SizedBox(height: AppSpacing.md),

            // 6. Completed section (collapsed by default)
            if (_filter != 1 && totalCompleted > 0) ...[
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  leading: const Icon(CupertinoIcons.checkmark_seal),
                  title: Text(
                    '${l.completedTodaySection} ($totalCompleted)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  children: [
                    ...data.completedTodayTodos.map(
                      (todo) =>
                          _buildCompletedTile(context, ref, todo, l, theme),
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
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              title,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverdueTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Checkbox(
          value: false,
          activeColor: theme.colorScheme.error,
          onChanged: (val) async {
            if (val == true) {
              await ref.read(toggleTodoProvider)(
                id: todo.id,
                isCompleted: true,
              );
            }
          },
        ),
        title: Text(
          todo.summary,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          todo.dueDate != null
              ? l.deadlinePrefix(DateFormatters.formatDate(todo.dueDate!))
              : l.overdue,
          style: AppTypography.caption.copyWith(color: theme.colorScheme.error),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => _selectTodo(context, todo),
      ),
    );
  }

  Widget _buildMissedInstanceTile(
    BuildContext context,
    WidgetRef ref,
    ProjectedTaskInstance instance,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Checkbox(
          value: false,
          activeColor: theme.colorScheme.error,
          onChanged: (val) async {
            if (val == true) {
              await ref.read(toggleTodoProvider)(
                id: instance.todoId,
                isCompleted: true,
                occurrenceId: instance.occurrenceId,
              );
            }
          },
        ),
        title: Text(
          instance.todo.summary,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${instance.occurrence.displayLabel} · ${l.missed}',
          style: AppTypography.caption.copyWith(color: theme.colorScheme.error),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => _selectTodo(context, instance.todo),
      ),
    );
  }

  Widget _buildEarlierMissedTile(
    BuildContext context,
    WidgetRef ref,
    Todo series,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      key: ValueKey('earlier-missed-${series.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: Icon(
          CupertinoIcons.time,
          color: theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
        title: Text(
          '${l.earlierMissed} · ${series.summary}',
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () async {
          final selected = await TodoOccurrencePickerSheet.show(
            context,
            ref: ref,
            todo: series,
            initialPage: 2,
          );
          if (selected != null) {
            await ref.read(toggleTodoProvider)(
              id: selected.todoId,
              isCompleted: !selected.isCompleted,
              occurrenceId: selected.occurrenceId,
            );
          }
        },
      ),
    );
  }

  Widget _buildEarlierHistoryTile(
    BuildContext context,
    WidgetRef ref,
    Todo series,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      key: ValueKey('earlier-history-${series.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: Icon(
          CupertinoIcons.time,
          color: theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
        title: Text(
          '${l.earlierHistory} · ${series.summary}',
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () async {
          final selected = await TodoOccurrencePickerSheet.show(
            context,
            ref: ref,
            todo: series,
            initialPage: 26,
          );
          if (selected != null) {
            await ref.read(toggleTodoProvider)(
              id: selected.todoId,
              isCompleted: !selected.isCompleted,
              occurrenceId: selected.occurrenceId,
            );
          }
        },
      ),
    );
  }

  Widget _buildTodayInstanceTile(
    BuildContext context,
    WidgetRef ref,
    ProjectedTaskInstance instance,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Checkbox(
          value: false,
          onChanged: (val) async {
            if (val == true) {
              await ref.read(toggleTodoProvider)(
                id: instance.todoId,
                isCompleted: true,
                occurrenceId: instance.occurrenceId,
              );
            }
          },
        ),
        title: Text(
          instance.todo.summary,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${instance.occurrence.displayLabel} · ${l.recurringTask}',
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => _selectTodo(context, instance.todo),
      ),
    );
  }

  List<Widget> _buildTimelineItems(
    BuildContext context,
    WidgetRef ref,
    ActionProjectionData data,
    AppLocalizations l,
    ThemeData theme,
  ) {
    // Combine events and allocations, sorted chronologically
    final items = <_TimelineEntry>[
      ...data.events
          .where((_) => _filter != 2)
          .map((e) => _TimelineEntry.event(e)),
      ...data.allocations
          .where((_) => _filter != 1)
          .map((a) => _TimelineEntry.allocation(a)),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final now = DateTime.now();
    final current = items
        .where((entry) => !entry.start.isAfter(now) && entry.end.isAfter(now))
        .toList();
    final remaining = items
        .where(
          (entry) =>
              !current.contains(entry) &&
              (MediaQuery.sizeOf(context).width >= 700 ||
                  entry.end.isAfter(now)),
        )
        .toList();
    final future = remaining
        .where((entry) => entry.start.isAfter(now))
        .toList();
    final ordered = [...current, ...remaining];
    final rows = <Widget>[];
    for (final entry in ordered) {
      if (current.isNotEmpty && entry == current.first) {
        rows.add(
          _buildSectionHeader(
            context,
            title: l.actionNow,
            icon: CupertinoIcons.clock,
            color: AppColors.brandWarm,
          ),
        );
      }
      if (future.isNotEmpty && entry == future.first) {
        rows.add(
          _buildSectionHeader(
            context,
            title: l.upcoming,
            icon: CupertinoIcons.arrow_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      }
      rows.add(_buildTimelineEntry(context, ref, entry, l, theme));
    }
    return rows;
  }

  Widget _buildTimelineEntry(
    BuildContext context,
    WidgetRef ref,
    _TimelineEntry entry,
    AppLocalizations l,
    ThemeData theme,
  ) {
    if (entry.isEvent) {
      final event = entry.event!;
      return _ActionRowSurface(
        warm:
            !entry.start.isAfter(DateTime.now()) &&
            entry.end.isAfter(DateTime.now()),
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: ListTile(
          leading: Icon(
            CupertinoIcons.calendar,
            color: event.color ?? theme.colorScheme.primary,
          ),
          title: Text(
            event.title,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${DateFormatters.formatTime(event.start)} – ${DateFormatters.formatTime(event.end)} · ${l.eventLabel}',
            style: AppTypography.caption.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
          onTap: () => _selectEvent(context, event),
        ),
      );
    } else {
      final item = entry.allocation!;
      return _ActionRowSurface(
        warm:
            !entry.start.isAfter(DateTime.now()) &&
            entry.end.isAfter(DateTime.now()),
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        elevation: 0,
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: theme.colorScheme.secondary.withValues(alpha: 0.3),
          ),
        ),
        child: ListTile(
          leading: Checkbox(
            key: ValueKey('allocation-checkbox-${item.allocation.id}'),
            value: false,
            activeColor: theme.colorScheme.secondary,
            onChanged: (val) async {
              if (val == true) {
                await ref.read(toggleTodoProvider)(
                  id: item.todo.id,
                  isCompleted: true,
                  occurrenceId: item.allocation.occurrenceId,
                );
              }
            },
          ),
          title: Text(
            item.todo.summary,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${DateFormatters.formatTime(item.allocation.startAt.toLocal())} – ${DateFormatters.formatTime(item.allocation.endAt.toLocal())} · ${l.plannedExecution}',
            style: AppTypography.caption.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
          onTap: () => _selectTodo(context, item.todo),
        ),
      );
    }
  }

  Widget _buildDueTodayTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Checkbox(
          value: false,
          onChanged: (val) async {
            if (val == true) {
              await ref.read(toggleTodoProvider)(
                id: todo.id,
                isCompleted: true,
              );
            }
          },
        ),
        title: Text(
          todo.summary,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          l.deadlineToday,
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => _selectTodo(context, todo),
      ),
    );
  }

  Widget _buildInboxCard(
    BuildContext context,
    WidgetRef ref,
    ActionProjectionData data,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return _ActionRowSurface(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: Icon(
          CupertinoIcons.tray_full,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          l.unplannedInbox,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          l.unplannedCount(data.unplannedCount),
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
        onTap: widget.onNavigateToTodos,
      ),
    );
  }

  Widget _buildCompletedTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return ListTile(
      leading: Checkbox(
        value: true,
        onChanged: (val) async {
          if (val == false) {
            await ref.read(toggleTodoProvider)(id: todo.id, isCompleted: false);
          }
        },
      ),
      title: Text(
        todo.summary,
        style: AppTypography.body.copyWith(
          decoration: TextDecoration.lineThrough,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      subtitle: todo.completedAt != null
          ? Text(
              DateFormatters.formatTime(todo.completedAt!),
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            )
          : null,
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
    return ListTile(
      leading: Checkbox(
        value: true,
        onChanged: (val) async {
          if (val == false) {
            await ref.read(toggleTodoProvider)(
              id: instance.todoId,
              isCompleted: false,
              occurrenceId: instance.occurrenceId,
            );
          }
        },
      ),
      title: Text(
        instance.todo.summary,
        style: AppTypography.body.copyWith(
          decoration: TextDecoration.lineThrough,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      subtitle: Text(
        '${instance.occurrence.displayLabel}${instance.completedAt != null ? ' · ${DateFormatters.formatTime(instance.completedAt!)}' : ''}',
        style: AppTypography.caption.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
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

class _ActionRowSurface extends StatelessWidget {
  const _ActionRowSurface({
    super.key,
    required this.child,
    this.margin,
    this.elevation,
    this.color,
    this.shape,
    this.warm = false,
  });
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final Color? color;
  final ShapeBorder? shape;
  final bool warm;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warmInk = theme.brightness == Brightness.dark
        ? AppColors.darkWarning
        : AppColors.brandWarm;
    if (child is! ListTile) return child;
    final tile = child as ListTile;
    final mobile = MediaQuery.sizeOf(context).width < 700;
    final l = AppLocalizations.of(context)!;
    final metadata = tile.subtitle is Text
        ? (tile.subtitle as Text).data ?? ''
        : '';
    final time = RegExp(r'^\d{2}:\d{2}').firstMatch(metadata)?.group(0);
    final checkbox = tile.leading is Checkbox ? tile.leading : null;
    final planned = metadata.contains(l.plannedExecution);
    final deadline =
        metadata == l.deadlineToday ||
        metadata.startsWith(l.deadlinePrefix('').trim());
    final recurring =
        metadata.contains(l.recurringTask) || metadata.contains(l.missed);
    final icon = tile.leading is Icon
        ? tile.leading!
        : Icon(
            planned
                ? CupertinoIcons.clock
                : recurring
                ? CupertinoIcons.repeat
                : deadline
                ? CupertinoIcons.flag
                : CupertinoIcons.exclamationmark_triangle,
            size: 16,
            color: warm || deadline
                ? warmInk
                : theme.colorScheme.onSurfaceVariant,
          );
    final title = tile.title is Text
        ? (tile.title as Text).copyWithActionStyle(theme)
        : tile.title;
    final subtitle = Text(
      metadata,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: warm ? warmInk : theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Material(
      color: warm ? warmInk.withValues(alpha: .06) : Colors.transparent,
      child: InkWell(
        onTap: tile.onTap,
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
                width: mobile ? 48 : 64,
                child: Text(
                  time ?? (deadline ? '—' : ''),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Center(
                  child: IconTheme(
                    data: const IconThemeData(size: 16),
                    child: icon,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: mobile
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null) title,
                          if (metadata.isNotEmpty) subtitle,
                        ],
                      )
                    : Row(
                        children: [
                          Flexible(child: title ?? const SizedBox.shrink()),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Flexible(child: subtitle),
                          ],
                        ],
                      ),
              ),
              if (checkbox != null)
                SizedBox(width: 48, height: 48, child: checkbox)
              else
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(child: tile.trailing),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on Text {
  Widget copyWithActionStyle(ThemeData theme) => Text(
    data ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppTypography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
    ),
  );
}
