import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_actions.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';

/// Today answers one question: what needs me today.
///
/// What is running gets a warm label and a progress rule; what is next stays
/// in time order; deadlines that do not occupy the timeline sit under their own
/// label; what slipped is marked, not disguised. Nothing here is a card.
class ActionSection extends ConsumerStatefulWidget {
  const ActionSection({
    super.key,
    this.onNavigateToCalendar,
    this.onNavigateToUnplanned,
    this.onEventTap,
    this.onTodoTap,
    this.detail,
    this.date,
  });

  final VoidCallback? onNavigateToCalendar;
  final VoidCallback? onNavigateToUnplanned;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(Todo todo)? onTodoTap;

  /// Desktop right-hand selection pane; when present it replaces the rail.
  final Widget? detail;
  final DateTime? date;

  @override
  ConsumerState<ActionSection> createState() => _ActionSectionState();
}

class _ActionSectionState extends ConsumerState<ActionSection> {
  bool _doneOpen = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final projectionAsync = ref.watch(actionProjectionProvider);
    final unplanned = ref.watch(unplannedTodosProvider).valueOrNull ?? const [];

    return projectionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        debugPrint('action: projection error: $error');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s5),
            child: Text(
              l.actionFailedRetry,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: context.ds.ink2),
            ),
          ),
        );
      },
      data: (data) {
        final model = _Model.build(data, widget.date ?? DateTime.now());
        final column = _column(context, l, model, desktop);
        if (!desktop) return column;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s6,
                  AppSpacing.s5,
                  AppSpacing.s6,
                  AppSpacing.s8,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: column,
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              color: context.ds.line,
            ),
            SizedBox(
              width: widget.detail != null ? 388 : 300,
              child: ColoredBox(
                color: widget.detail != null
                    ? context.ds.surface
                    : context.ds.bg,
                child: widget.detail ?? _rail(context, l, unplanned),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _column(
    BuildContext context,
    AppLocalizations l,
    _Model model,
    bool desktop,
  ) {
    final ds = context.ds;
    final children = <Widget>[];

    if (!desktop) {
      children.add(_DayHead(model: model, l: l, date: widget.date));
    }

    for (final item in model.current) {
      children.add(
        _NowCard(
          key: item.isEvent
              ? ValueKey(
                  'action-event-${item.event!.start.millisecondsSinceEpoch}',
                )
              : ValueKey('action-allocation-${item.allocation!.allocation.id}'),
          entry: item,
          desktop: desktop,
          onTap: item.isEvent
              ? () => widget.onEventTap?.call(item.event!)
              : () => widget.onTodoTap?.call(item.allocation!.todo),
          onToggle: item.isEvent
              ? null
              : () {
                  final todo = item.allocation!.todo;
                  _complete(
                    context,
                    todo,
                    occurrenceId: item.allocation!.allocation.occurrenceId,
                  );
                },
        ),
      );
    }

    if (model.later.isNotEmpty) {
      children.add(
        DsSectionLabel(
          l.laterToday,
          padding: EdgeInsets.fromLTRB(
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s5 + 2,
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s2,
          ),
        ),
      );
      for (final entry in model.later) {
        children.add(
          entry.isEvent
              ? _EventRow(
                  event: entry.event!,
                  desktop: desktop,
                  onTap: () => widget.onEventTap?.call(entry.event!),
                )
              : _AllocationRow(
                  key: ValueKey(
                    'action-allocation-${entry.allocation!.allocation.id}',
                  ),
                  item: entry.allocation!,
                  desktop: desktop,
                  showCheck: !desktop,
                  onTap: () => widget.onTodoTap?.call(entry.allocation!.todo),
                  onToggle: () => _complete(
                    context,
                    entry.allocation!.todo,
                    occurrenceId:
                        entry.allocation!.allocation.occurrenceId,
                  ),
                ),
        );
      }
    }

    if (model.dueToday.isNotEmpty || model.dueInstances.isNotEmpty) {
      children.add(
        DsSectionLabel(
          l.dueTodaySection,
          padding: EdgeInsets.fromLTRB(
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s5 + 2,
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s1,
          ),
        ),
      );
      for (final instance in model.dueInstances) {
        children.add(
          _InstanceRow(
            instance: instance,
            desktop: desktop,
            onTap: () => widget.onTodoTap?.call(instance.todo),
            onToggle: () => _completeOccurrence(instance),
          ),
        );
      }
      for (final todo in model.dueToday) {
        children.add(
          TodoListTile(
            summary: todo.summary,
            isCompleted: false,
            priority: todo.priority,
            todoId: todo.id,
            dueDate: todo.dueDate,
            startDate: todo.startDate,
            todo: todo,
            onTap: () => widget.onTodoTap?.call(todo),
            onToggle: (occurrenceId, completed) => ref
                .read(toggleTodoProvider)(
                  id: todo.id,
                  isCompleted: completed,
                  occurrenceId: occurrenceId,
                )
                .catchError((Object error) {
                  if (context.mounted) showCompletionError(context, error);
                }),
          ),
        );
      }
    }

    if (model.overdue.isNotEmpty || model.missedInstances.isNotEmpty) {
      children.add(
        DsSectionLabel(
          l.overdue,
          color: ds.danger,
          padding: EdgeInsets.fromLTRB(
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s5 + 2,
            desktop ? 0 : AppSpacing.s4,
            AppSpacing.s1,
          ),
        ),
      );
      for (final todo in model.overdue) {
        children.add(
          TodoListTile(
            summary: todo.summary,
            isCompleted: false,
            priority: todo.priority,
            todoId: todo.id,
            dueDate: todo.dueDate,
            startDate: todo.startDate,
            todo: todo,
            onTap: () => widget.onTodoTap?.call(todo),
            onToggle: (occurrenceId, completed) => ref
                .read(toggleTodoProvider)(
                  id: todo.id,
                  isCompleted: completed,
                  occurrenceId: occurrenceId,
                )
                .catchError((Object error) {
                  if (context.mounted) showCompletionError(context, error);
                }),
          ),
        );
      }
      for (final instance in model.missedInstances) {
        children.add(
          _InstanceRow(
            instance: instance,
            desktop: desktop,
            missed: true,
            onTap: () => widget.onTodoTap?.call(instance.todo),
            onToggle: () => _completeOccurrence(instance),
          ),
        );
      }
    }

    if (model.unplannedCount > 0) {
      children.add(
        _UnplannedShortcut(
          count: model.unplannedCount,
          desktop: desktop,
          onTap: widget.onNavigateToUnplanned,
        ),
      );
    }

    if (model.isQuiet) {
      children.add(
        DsEmpty(
          icon: CupertinoIcons.time,
          title: l.actionNothingNow,
          message: l.actionNothingNowHint,
          action: DsButton(
            label: l.todos,
            tone: DsButtonTone.secondary,
            small: true,
            onPressed: widget.onNavigateToUnplanned,
          ),
        ),
      );
    }

    if (model.completedCount > 0) {
      children.add(
        _DoneDisclosure(
          count: model.completedCount,
          open: _doneOpen,
          desktop: desktop,
          onTap: () => setState(() => _doneOpen = !_doneOpen),
        ),
      );
      if (_doneOpen) {
        for (final entry in model.earlier) {
          children.add(
            entry.isEvent
                ? _EventRow(
                    event: entry.event!,
                    desktop: desktop,
                    muted: true,
                    onTap: () => widget.onEventTap?.call(entry.event!),
                  )
                : _AllocationRow(
                    item: entry.allocation!,
                    desktop: desktop,
                    muted: true,
                    onTap: () => widget.onTodoTap?.call(entry.allocation!.todo),
                    onToggle: () {},
                  ),
          );
        }
        for (final todo in model.completed) {
          children.add(
            TodoListTile(
              summary: todo.summary,
              isCompleted: true,
              priority: todo.priority,
              todoId: todo.id,
              dueDate: todo.dueDate,
              todo: todo,
              onTap: () => widget.onTodoTap?.call(todo),
              onToggle: (occurrenceId, completed) => ref.read(toggleTodoProvider)(
                id: todo.id,
                isCompleted: completed,
                occurrenceId: occurrenceId,
              ),
            ),
          );
        }
        for (final instance in model.completedInstances) {
          children.add(
            _InstanceRow(
              instance: instance,
              desktop: desktop,
              onTap: () => widget.onTodoTap?.call(instance.todo),
              onToggle: () {},
            ),
          );
        }
      }
    }

    children.add(const SizedBox(height: AppSpacing.s6));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _rail(BuildContext context, AppLocalizations l, List<Todo> unplanned) {
    final ds = context.ds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4 + 2,
        AppSpacing.s4 + 2,
        AppSpacing.s4 + 2,
        AppSpacing.s6,
      ),
      children: [
        Text(
          '${l.inbox} · ${unplanned.length}',
          style: AppTypography.overline.copyWith(
            fontSize: 12,
            letterSpacing: 0,
            color: ds.ink3,
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          l.unplannedRailHint,
          style: AppTypography.small.copyWith(color: ds.ink3),
        ),
        const SizedBox(height: AppSpacing.s3),
        if (unplanned.isEmpty)
          Text(
            l.unplannedRailEmpty,
            style: AppTypography.small.copyWith(color: ds.ink3),
          )
        else
          for (final todo in unplanned.take(12))
            _RailRow(
              todo: todo,
              onTap: () => widget.onTodoTap?.call(todo),
              onSchedule: () async {
                final ok = await scheduleTodoBlock(context, ref, todo);
                if (ok && context.mounted) {
                  ref.invalidate(actionProjectionProvider);
                }
              },
            ),
      ],
    );
  }

  Future<void> _complete(
    BuildContext context,
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

  Future<void> _completeOccurrence(ProjectedTaskInstance instance) async {
    try {
      await ref.read(toggleTodoProvider)(
        id: instance.todoId,
        isCompleted: instance.completedAt == null,
        occurrenceId: instance.occurrenceId,
      );
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
    }
  }
}

// ---------------------------------------------------------------- model

class _Model {
  _Model({
    required this.current,
    required this.later,
    required this.earlier,
    required this.dueToday,
    required this.dueInstances,
    required this.overdue,
    required this.missedInstances,
    required this.completed,
    required this.completedInstances,
    required this.unplannedCount,
  });

  final List<_Entry> current;
  final List<_Entry> later;
  final List<_Entry> earlier;
  final List<Todo> dueToday;
  final List<ProjectedTaskInstance> dueInstances;
  final List<Todo> overdue;
  final List<ProjectedTaskInstance> missedInstances;
  final List<Todo> completed;
  final List<ProjectedTaskInstance> completedInstances;
  final int unplannedCount;

  int get completedCount =>
      earlier.length + completed.length + completedInstances.length;

  bool get isQuiet =>
      current.isEmpty &&
      later.isEmpty &&
      dueToday.isEmpty &&
      dueInstances.isEmpty &&
      overdue.isEmpty &&
      missedInstances.isEmpty;

  static _Model build(ActionProjectionData data, DateTime now) {
    _Entry eventEntry(CalendaEventAdapter event) => _Entry.event(event);
    _Entry allocEntry(TaskAllocationCalendarItem item) =>
        _Entry.allocation(item);

    final entries = <_Entry>[
      ...data.events.map(eventEntry),
      ...data.allocations.map(allocEntry),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final current = <_Entry>[];
    final later = <_Entry>[];
    final earlier = <_Entry>[];
    for (final entry in entries) {
      if (entry.isCurrent(now)) {
        current.add(entry);
      } else if (entry.start.isAfter(now)) {
        later.add(entry);
      } else if (!entry.end.isAfter(now)) {
        earlier.add(entry);
      }
    }

    final plannedIds = {
      for (final item in data.allocations) item.todo.id,
    };
    return _Model(
      current: current,
      later: later,
      earlier: earlier,
      dueToday: data.dueTodayTodos
          .where((todo) => !plannedIds.contains(todo.id))
          .toList(),
      dueInstances: data.todayTaskInstances,
      overdue: data.overdueTodos,
      missedInstances: data.missedTaskInstances,
      completed: data.completedTodayTodos,
      completedInstances: data.completedTodayTaskInstances,
      unplannedCount: data.unplannedCount,
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

// ---------------------------------------------------------------- pieces

class _DayHead extends StatelessWidget {
  const _DayHead({required this.model, required this.l, this.date});

  final _Model model;
  final AppLocalizations l;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final day = date ?? DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final weekday = DateFormat.E(locale).format(day);
    final md = DateFormat.Md(locale).format(day);
    final note = model.unplannedCount > 0
        ? l.unplannedCount(model.unplannedCount)
        : l.allScheduled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        2,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.today,
            style: AppTypography.display.copyWith(color: ds.ink),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            '$weekday${locale.startsWith('zh') ? '，' : ', '}$md · $note',
            style: AppTypography.caption.copyWith(color: ds.ink3),
          ),
        ],
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({
    super.key,
    required this.entry,
    required this.desktop,
    required this.onTap,
    this.onToggle,
  });

  final _Entry entry;
  final bool desktop;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final total = entry.end.difference(entry.start).inSeconds;
    final elapsed = now.difference(entry.start).inSeconds;
    final pct = total <= 0
        ? 4.0
        : ((elapsed / total) * 100).clamp(4.0, 100.0);
    final title = entry.isEvent
        ? entry.event!.title
        : entry.allocation!.todo.summary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: desktop ? 0 : AppSpacing.s4),
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.s3 + 2,
            0,
            AppSpacing.s4,
          ),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ds.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    entry.isEvent ? l.inProgress : l.executingPlan,
                    style: AppTypography.overline.copyWith(
                      fontSize: 11,
                      color: ds.warm,
                    ),
                  ),
                  const Spacer(),
                  if (onToggle != null)
                    DsCheck(
                      checked: entry.allocation!.todo.status == 'COMPLETED',
                      size: 18,
                      compact: true,
                      onChanged: (_) => onToggle!(),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: ds.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '${DateFormatters.formatTime(entry.start)}–${DateFormatters.formatTime(entry.end)}'
                '${entry.isEvent ? '' : ' · ${l.plannedExecution}'}',
                style: AppTypography.small.copyWith(
                  color: ds.ink2,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              Container(
                height: 2,
                color: ds.line,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct / 100,
                  child: ColoredBox(color: ds.warm),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.desktop,
    required this.onTap,
    this.muted = false,
  });

  final CalendaEventAdapter event;
  final bool desktop;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return _TimeRow(
      desktop: desktop,
      time: event.isAllDay
          ? AppLocalizations.of(context)!.allDay
          : DateFormatters.formatTime(event.start),
      title: event.title,
      meta: [
        if (!event.isAllDay)
          '${DateFormatters.formatTime(event.start)}–${DateFormatters.formatTime(event.end)}',
        if (event.location != null && event.location!.isNotEmpty)
          event.location!,
      ],
      onTap: onTap,
      muted: muted,
      titleColor: muted ? ds.ink3 : ds.ink,
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    super.key,
    required this.item,
    required this.desktop,
    required this.onTap,
    this.onToggle,
    this.showCheck = false,
    this.muted = false,
  });

  final TaskAllocationCalendarItem item;
  final bool desktop;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final bool showCheck;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final todo = item.todo;
    final start = item.allocation.startAt.toLocal();
    final end = item.allocation.endAt.toLocal();
    return _TimeRow(
      desktop: desktop,
      time: DateFormatters.formatTime(start),
      timeMuted: true,
      leading: showCheck
          ? DsCheck(
              checked: todo.status == 'COMPLETED',
              size: 19,
              compact: true,
              onChanged: onToggle == null ? null : (_) => onToggle!(),
            )
          : null,
      title: todo.summary,
      meta: [
        '${l.plannedExecution} ${DateFormatters.formatTime(start)}–${DateFormatters.formatTime(end)}',
        if (todo.dueDate != null)
          l.deadlinePrefix(DateFormatters.formatShortDate(todo.dueDate!)),
      ],
      onTap: onTap,
      muted: muted,
      titleColor: muted ? ds.ink3 : ds.ink,
      metaWarnIndex: todo.dueDate != null ? 1 : null,
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.desktop,
    required this.time,
    required this.title,
    required this.meta,
    required this.onTap,
    this.leading,
    this.muted = false,
    this.timeMuted = false,
    this.titleColor,
    this.metaWarnIndex,
  });

  final bool desktop;
  final String time;
  final String title;
  final List<String> meta;
  final VoidCallback onTap;
  final Widget? leading;
  final bool muted;
  final bool timeMuted;
  final Color? titleColor;
  final int? metaWarnIndex;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return DsRow(
      title: title,
      onTap: onTap,
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 0 : AppSpacing.s4,
        vertical: 9,
      ),
      titleStyle: AppTypography.body.copyWith(color: titleColor ?? ds.ink),
      leading: leading,
      meta: meta.isEmpty
          ? null
          : DsMeta(
              parts: [
                for (var i = 0; i < meta.length; i++)
                  DsMetaPart(
                    meta[i],
                    color: metaWarnIndex == i ? ds.warn : null,
                  ),
              ],
            ),
      trailing: null,
    );
  }
}

class _InstanceRow extends StatelessWidget {
  const _InstanceRow({
    required this.instance,
    required this.desktop,
    required this.onTap,
    required this.onToggle,
    this.missed = false,
  });

  final ProjectedTaskInstance instance;
  final bool desktop;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final label = formatOccurrenceAnchor(
      context,
      instance.occurrence.displayLabel,
    );
    return _TimeRow(
      desktop: desktop,
      time: label,
      title: instance.todo.summary,
      meta: [missed ? l.missed : l.recurringTask],
      onTap: onTap,
      leading: DsCheck(
        checked: instance.completedAt != null,
        size: 19,
        compact: true,
        onChanged: (_) => onToggle(),
      ),
      muted: instance.completedAt != null,
      metaWarnIndex: missed ? 0 : null,
      titleColor: missed ? ds.ink3 : ds.ink,
    );
  }
}

class _UnplannedShortcut extends StatelessWidget {
  const _UnplannedShortcut({
    required this.count,
    required this.desktop,
    this.onTap,
  });

  final int count;
  final bool desktop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            margin: EdgeInsets.fromLTRB(
              desktop ? 0 : AppSpacing.s4,
              AppSpacing.s1,
              desktop ? 0 : AppSpacing.s4,
              AppSpacing.s2,
            ),
            height: 46,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: ds.lineSoft),
              ),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.tray, size: 17, color: ds.ink2),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  l.inbox,
                  style: AppTypography.body.copyWith(color: ds.ink2),
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: AppTypography.caption.copyWith(
                    color: ds.ink3,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
                const SizedBox(width: AppSpacing.s1),
                Icon(CupertinoIcons.chevron_right, size: 15, color: ds.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneDisclosure extends StatelessWidget {
  const _DoneDisclosure({
    required this.count,
    required this.open,
    required this.desktop,
    required this.onTap,
  });

  final int count;
  final bool open;
  final bool desktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: desktop ? 0 : AppSpacing.s4),
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Icon(
                  open
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 14,
                  color: ds.ink3,
                ),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  l.completed,
                  style: AppTypography.caption.copyWith(
                    color: ds.ink2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppSpacing.s1),
                Text(
                  '$count',
                  style: AppTypography.caption.copyWith(color: ds.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.todo,
    required this.onTap,
    required this.onSchedule,
  });

  final Todo todo;
  final VoidCallback onTap;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ds.lineSoft)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: ds.ink,
                        ),
                      ),
                      if (todo.dueDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          l.deadlinePrefix(
                            DateFormatters.formatShortDate(todo.dueDate!),
                          ),
                          style: TextStyle(fontSize: 11.5, color: ds.ink3),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                DsButton(
                  label: l.schedule,
                  tone: DsButtonTone.ghost,
                  small: true,
                  onPressed: onSchedule,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
