import 'package:flutter/cupertino.dart';
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

class ActionSection extends ConsumerWidget {
  const ActionSection({
    super.key,
    this.onNavigateToTodos,
    this.onEventTap,
    this.onTodoTap,
  });

  final VoidCallback? onNavigateToTodos;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(Todo todo)? onTodoTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        final totalCompleted = data.completedTodayTodos.length +
            data.completedTodayTaskInstances.length;

        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
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
                        ? (((err.error as RecurrenceExpansionException).message.contains('horizon'))
                            ? l.recurrenceTimezoneHorizonError
                            : (((err.error as RecurrenceExpansionException).message.contains('limit'))
                                ? l.recurrenceOccurrenceLimitError
                                : (err.error as RecurrenceExpansionException).message))
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
                  trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
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
            if (totalOverdue > 0 || data.hasEarlierMissed) ...[
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
            if (data.todayTaskInstances.isNotEmpty) ...[
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
            if (data.dueTodayTodos.isNotEmpty) ...[
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
            if (totalCompleted > 0) ...[
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
          Text(
            title,
            style: AppTypography.title.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
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
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
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
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          todo.dueDate != null
              ? l.deadlinePrefix(DateFormatters.formatDate(todo.dueDate!))
              : l.overdue,
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => onTodoTap?.call(todo),
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
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
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
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${instance.occurrence.displayLabel} · ${l.missed}',
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => onTodoTap?.call(instance.todo),
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
    return Card(
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

  Widget _buildTodayInstanceTile(
    BuildContext context,
    WidgetRef ref,
    ProjectedTaskInstance instance,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
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
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${instance.occurrence.displayLabel} · ${l.recurringTask}',
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => onTodoTap?.call(instance.todo),
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
      ...data.events.map((e) => _TimelineEntry.event(e)),
      ...data.allocations.map((a) => _TimelineEntry.allocation(a)),
    ]..sort((a, b) => a.start.compareTo(b.start));

    return items.map((entry) {
      if (entry.isEvent) {
        final event = entry.event!;
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
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
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '${DateFormatters.formatTime(event.start)} – ${DateFormatters.formatTime(event.end)} · ${l.eventLabel}',
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
            onTap: () => onEventTap?.call(event),
          ),
        );
      } else {
        final item = entry.allocation!;
        return Card(
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
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '${DateFormatters.formatTime(item.allocation.startAt.toLocal())} – ${DateFormatters.formatTime(item.allocation.endAt.toLocal())} · ${l.plannedExecution}',
              style: AppTypography.caption.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
            onTap: () => onTodoTap?.call(item.todo),
          ),
        );
      }
    }).toList();
  }

  Widget _buildDueTodayTile(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    AppLocalizations l,
    ThemeData theme,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
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
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          l.deadlineToday,
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 14),
        onTap: () => onTodoTap?.call(todo),
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
    return Card(
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
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          l.unplannedCount(data.unplannedCount),
          style: AppTypography.caption.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
        onTap: onNavigateToTodos,
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
            await ref.read(toggleTodoProvider)(
              id: todo.id,
              isCompleted: false,
            );
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
      onTap: () => onTodoTap?.call(todo),
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
      onTap: () => onTodoTap?.call(instance.todo),
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
}
