import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_colors.dart';
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
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';

/// Action answers exactly one question: what needs me today.
///
/// So it is one day wide — today — and it holds no date switcher, no counters
/// and no side pane. Browsing other days is Calendar's job; the rows here are
/// in time order and every one of them opens the object's detail.
class ActionSection extends ConsumerWidget {
  const ActionSection({
    super.key,
    this.onNavigateToCalendar,
    this.onEventTap,
    this.onTodoTap,
  });

  final VoidCallback? onNavigateToCalendar;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(Todo todo)? onTodoTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final projectionAsync = ref.watch(actionProjectionProvider);
    final horizontal = isWorkspaceLayout(context) ? 28.0 : AppSpacing.lg;

    return projectionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        debugPrint('action: projection error: $error');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l.actionFailedRetry,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ),
        );
      },
      data: (data) {
        final sections = _sections(context, ref, l, data);
        if (sections.isEmpty) {
          return _emptyState(context, l);
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.sm,
            horizontal,
            AppSpacing.xxl,
          ),
          children: sections,
        );
      },
    );
  }

  /// Ordered the way the day is lived: what is running, what is next, what
  /// must land today, what slipped, and finally what is already done.
  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    ActionProjectionData data,
  ) {
    final now = DateTime.now();
    final rows = <Widget>[];

    final current = <_Entry>[
      ...data.events.map(_Entry.event).where((e) => e.isCurrent(now)),
      ...data.allocations.map(_Entry.allocation).where((e) => e.isCurrent(now)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final later = <_Entry>[
      ...data.events.map(_Entry.event).where((e) => e.start.isAfter(now)),
      ...data.allocations
          .map(_Entry.allocation)
          .where((e) => e.start.isAfter(now)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    // Things that already happened today are still part of today's picture:
    // without this an event that ended an hour ago simply vanished.
    final earlier = <_Entry>[
      ...data.events.map(_Entry.event).where((e) => !e.end.isAfter(now)),
      ...data.allocations
          .map(_Entry.allocation)
          .where((e) => !e.end.isAfter(now)),
    ]..sort((a, b) => a.start.compareTo(b.start));

    if (current.isNotEmpty) {
      rows
        ..add(_SectionHeader(title: l.actionNow, accent: AppColors.brandWarm))
        ..addAll(current.map((e) => _entryRow(context, ref, l, e, warm: true)));
    }
    if (later.isNotEmpty) {
      rows
        ..add(_SectionHeader(title: l.laterToday))
        ..addAll(later.map((e) => _entryRow(context, ref, l, e)));
    }

    // "Today to finish" merges the two shapes of the same obligation: today's
    // recurring occurrences and ordinary todos due today.
    final dueAndDue = <Widget>[
      ...data.todayTaskInstances.map(
        (instance) => _instanceRow(context, ref, l, instance),
      ),
      ...data.dueTodayTodos.map((todo) => _todoRow(context, ref, l, todo)),
    ];
    if (dueAndDue.isNotEmpty) {
      rows
        ..add(_SectionHeader(title: l.dueTodaySection))
        ..addAll(dueAndDue);
    }

    final overdue = <Widget>[
      ...data.overdueTodos.map((todo) => _todoRow(context, ref, l, todo)),
      ...data.missedTaskInstances.map(
        (instance) => _instanceRow(context, ref, l, instance, missed: true),
      ),
    ];
    if (overdue.isNotEmpty) {
      rows
        ..add(
          _SectionHeader(
            title: l.overdue,
            accent: Theme.of(context).colorScheme.error,
          ),
        )
        ..addAll(overdue);
    }

    final completed = <Widget>[
      ...earlier.map((e) => _entryRow(context, ref, l, e)),
      ...data.completedTodayTodos.map(
        (todo) => _todoRow(context, ref, l, todo),
      ),
      ...data.completedTodayTaskInstances.map(
        (instance) => _instanceRow(context, ref, l, instance),
      ),
    ];
    if (completed.isNotEmpty) {
      rows
        ..add(_SectionHeader(title: l.actionEarlierToday))
        ..addAll(completed);
    }
    return rows;
  }

  Widget _entryRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    _Entry entry, {
    bool warm = false,
  }) {
    if (entry.isEvent) {
      final event = entry.event!;
      return _ActionRow(
        key: ValueKey(
          'action-event-${event.drifId}-${event.start.millisecondsSinceEpoch}',
        ),
        time: DateFormatters.formatTime(entry.start),
        meta: l.untilTime(DateFormatters.formatTime(entry.end)),
        title: event.title,
        warm: warm,
        onTap: () => onEventTap?.call(event),
      );
    }
    final item = entry.allocation!;
    final todo = item.todo;
    return _ActionRow(
      key: ValueKey('action-allocation-${item.allocation.id}'),
      time: DateFormatters.formatTime(item.allocation.startAt.toLocal()),
      meta: l.scheduledTimeLower,
      title: todo.summary,
      warm: warm,
      completed: todo.status == 'COMPLETED',
      // An allocation is bound to one occurrence, so ticking it must complete
      // that occurrence rather than ask which one the user means.
      onToggle: () => _complete(
        context,
        ref,
        todo,
        occurrenceId: item.allocation.occurrenceId,
      ),
      onTap: () => onTodoTap?.call(todo),
    );
  }

  Widget _todoRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Todo todo,
  ) {
    final clock = _deadlineClock(todo.dueDate);
    return _ActionRow(
      key: ValueKey('action-todo-${todo.id}'),
      time: clock ?? (todo.dueDate == null ? null : l.today),
      meta: todo.dueDate == null
          ? null
          : l.deadlinePrefix(DateFormatters.formatDate(todo.dueDate!)),
      title: todo.summary,
      completed: todo.status == 'COMPLETED',
      onToggle: () => _complete(context, ref, todo),
      onTap: () => onTodoTap?.call(todo),
    );
  }

  Widget _instanceRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    ProjectedTaskInstance instance, {
    bool missed = false,
  }) {
    final todo = instance.todo;
    return _ActionRow(
      key: ValueKey('action-instance-${instance.occurrenceId}'),
      time: formatOccurrenceAnchor(context, instance.occurrence.displayLabel),
      meta: missed ? l.missed : l.recurringTask,
      title: todo.summary,
      completed: instance.completedAt != null,
      onToggle: () => _completeOccurrence(context, ref, todo, instance),
      onTap: () => onTodoTap?.call(todo),
    );
  }

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    Todo todo, {
    String? occurrenceId,
  }) async {
    try {
      await toggleTodoCompletion(
        context,
        ref,
        todo: todo,
        completed: todo.status != 'COMPLETED',
        occurrenceId: occurrenceId,
      );
    } on Object catch (error) {
      if (context.mounted) showCompletionError(context, error);
    }
  }

  Future<void> _completeOccurrence(
    BuildContext context,
    WidgetRef ref,
    Todo todo,
    ProjectedTaskInstance instance,
  ) async {
    try {
      await ref.read(toggleTodoProvider)(
        id: instance.todoId,
        isCompleted: instance.completedAt == null,
        occurrenceId: instance.occurrenceId,
      );
    } on Object catch (error) {
      if (context.mounted) showCompletionError(context, error);
    }
  }

  /// A date-only deadline has no clock. Printing 00:00 invents a time the
  /// user never set, so the column falls back to the date it already shows.
  String? _deadlineClock(DateTime? due) {
    if (due == null) return null;
    if (due.hour == 0 && due.minute == 0) return null;
    return DateFormatters.formatTime(due);
  }

  /// Nothing to do is a good outcome, so it is stated plainly rather than
  /// filled with management shortcuts.
  Widget _emptyState(BuildContext context, AppLocalizations l) {
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
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.4),
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
}

class _Entry {
  const _Entry.event(this.event) : allocation = null;
  const _Entry.allocation(this.allocation) : event = null;

  final CalendaEventAdapter? event;
  final TaskAllocationCalendarItem? allocation;

  bool get isEvent => event != null;
  DateTime get start =>
      event?.start ?? allocation!.allocation.startAt.toLocal();
  DateTime get end => event?.end ?? allocation!.allocation.endAt.toLocal();

  bool isCurrent(DateTime now) => !start.isAfter(now) && end.isAfter(now);
}

/// One action row: time on the left, what it is in the middle, done on the
/// right. Flat — a hairline separates rows, nothing draws a box around one.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.title,
    this.time,
    this.meta,
    this.warm = false,
    this.completed,
    this.onToggle,
    required this.onTap,
  });

  final String title;
  final String? time;
  final String? meta;
  final bool warm;
  final bool? completed;
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = !isWorkspaceLayout(context);
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
                child: Text(
                  time ?? '',
                  style: AppTypography.caption.copyWith(
                    color: muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
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
                          style: AppTypography.caption.copyWith(color: muted),
                        ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, top: AppSpacing.lg),
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
