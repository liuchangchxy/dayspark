import 'package:flutter/cupertino.dart';
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
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/c_day_timeline.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/todo/todo_completion.dart';
import 'package:dayspark/ui/widgets/todo/todo_quick_create_sheet.dart';

/// Today answers one question: what does the day actually look like.
///
/// The answer is drawn to scale. Hours are a fixed height, events and allocated
/// tasks occupy the span they really take, the gaps between them are shown as
/// gaps, and the now-line sits where the clock is. The panel on the right holds
/// what the timeline cannot: the day's tasks, its count, and the next opening.
class ActionSection extends ConsumerStatefulWidget {
  const ActionSection({
    super.key,
    this.onNavigateToCalendar,
    this.onNavigateToUnplanned,
    this.onEventTap,
    this.onTodoTap,
    this.detail,
    this.date,
    this.now,
  });

  final VoidCallback? onNavigateToCalendar;
  final VoidCallback? onNavigateToUnplanned;
  final void Function(CalendaEventAdapter event)? onEventTap;
  final void Function(Todo todo)? onTodoTap;

  /// Desktop right-hand selection pane; when present it replaces the panel.
  final Widget? detail;
  final DateTime? date;

  /// The instant the page draws its now-line at. Defaults to the wall clock;
  /// tests pin it so a capture does not drift with the machine's time.
  final DateTime? now;

  @override
  ConsumerState<ActionSection> createState() => _ActionSectionState();
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _ActionSectionState extends ConsumerState<ActionSection> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final desktop = isWorkspaceLayout(context);
    final projectionAsync = ref.watch(actionProjectionProvider);

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
        final now = widget.now ?? DateTime.now();
        final day = widget.date ?? now;
        final model = _Model.build(data, day, now, l);
        return desktop
            ? _desktop(context, l, data, model, day, now)
            : _mobile(context, l, data, model, day, now);
      },
    );
  }

  Widget _desktop(
    BuildContext context,
    AppLocalizations l,
    ActionProjectionData data,
    _Model model,
    DateTime day,
    DateTime now,
  ) {
    final ds = context.ds;
    final panelWidth = widget.detail != null ? 388.0 : 356.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  AppSpacing.s5,
                  0,
                  AppSpacing.s3,
                ),
                child: _DayHeader(l: l, model: model, day: day, now: now),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.s5,
                          right: AppSpacing.s5,
                        ),
                        child: CDayTimeline(
                          day: day,
                          now: now,
                          events: model.dayEvents,
                          allocations: data.allocations,
                          onEventTap: widget.onEventTap,
                          onAllocationTap: (item) =>
                              widget.onTodoTap?.call(item.todo),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s5),
                      child: Container(
                        width: panelWidth,
                        decoration: BoxDecoration(
                          color: ds.surface,
                          border: Border.all(color: ds.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child:
                            widget.detail ??
                            _TodayPanel(
                              l: l,
                              model: model,
                              onTodoTap: widget.onTodoTap,
                              onToggle: _complete,
                              onAdd: () => showTodoQuickCreateSheet(
                                context,
                                dueDate: day,
                              ),
                              onShowAll: widget.onNavigateToUnplanned,
                              nextGap: _nextGap(model, now),
                            ),
                      ),
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

  Widget _mobile(
    BuildContext context,
    AppLocalizations l,
    ActionProjectionData data,
    _Model model,
    DateTime day,
    DateTime now,
  ) {
    final ds = context.ds;
    // An empty day still drew the whole 07:00-22:00 grid, which is most of a
    // phone screen spent saying "nothing here". The grid is decorative when
    // nothing sits on it: it cannot be dragged in and has no block to tap, so it
    // collapses to one line and the tasks take the room. The first event brings
    // the full-height grid back.
    final emptyDay = model.dayEvents.isEmpty && data.allocations.isEmpty;
    final sheet = Container(
      decoration: BoxDecoration(
        color: ds.surface,
        border: Border(top: BorderSide(color: ds.line)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: _MobileSheet(
        l: l,
        model: model,
        onTap: widget.onTodoTap,
        onToggle: _complete,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileHead(l: l, model: model, day: day, now: now),
        if (emptyDay)
          Container(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s2,
              AppSpacing.s4,
              AppSpacing.s3,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ds.surface2,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text(
              l.actionEmptyDay,
              style: AppTypography.small.copyWith(color: ds.ink3),
            ),
          )
        else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                0,
              ),
              child: CDayTimeline(
                day: day,
                now: now,
                events: model.dayEvents,
                allocations: data.allocations,
                onEventTap: widget.onEventTap,
                onAllocationTap: (item) => widget.onTodoTap?.call(item.todo),
              ),
            ),
          ),
        if (emptyDay) Expanded(child: sheet) else sheet,
      ],
    );
  }

  _GapInfo? _nextGap(_Model model, DateTime now) {
    final busy = <(DateTime, DateTime)>[
      for (final e in model.dayEvents)
        if (!e.isAllDay) (e.start, e.end),
      for (final a in model.dayAllocations)
        (a.allocation.startAt.toLocal(), a.allocation.endAt.toLocal()),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = now;
    for (final interval in busy) {
      if (interval.$2.isBefore(cursor)) continue;
      if (interval.$1.isAfter(cursor)) {
        final minutes = interval.$1.difference(cursor).inMinutes;
        if (minutes >= 30) {
          return _GapInfo(start: cursor, end: interval.$1);
        }
      }
      if (interval.$2.isAfter(cursor)) cursor = interval.$2;
    }
    return null;
  }

  Future<void> _complete(Todo todo, {String? occurrenceId}) async {
    try {
      await toggleTodoCompletion(
        context,
        ref,
        todo: todo,
        completed: todo.status != 'COMPLETED',
        occurrenceId: occurrenceId,
      );
    } on Object catch (error) {
      if (mounted) showCompletionError(context, error);
    }
  }
}

class _GapInfo {
  const _GapInfo({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  int get minutes => end.difference(start).inMinutes;
}

// ---------------------------------------------------------------- header

String _minutesSpan(AppLocalizations l, int totalMinutes) {
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return l.durationMinutes(m);
  if (m == 0) return l.durationHours(h);
  return l.durationHoursMinutes(h, m);
}

String _span(AppLocalizations l, DateTime start, DateTime end) {
  final minutes = end.difference(start).inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return l.durationMinutes(m);
  if (m == 0) return l.durationHours(h);
  return l.durationHoursMinutes(h, m);
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.l,
    required this.model,
    required this.day,
    required this.now,
  });

  final AppLocalizations l;
  final _Model model;
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The legend explains colours the blocks already show; in a narrow
        // window the totals earn the space instead.
        final showLegend = constraints.maxWidth >= 900;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                l.timelineTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(
                  color: ds.ink,
                  fontSize: 16,
                ),
              ),
            ),
            if (showLegend) ...[
              const SizedBox(width: AppSpacing.s4),
              _LegendDot(
                color: ds.doneInk,
                label: '${l.completedLabel} ${model.completedTotal}',
              ),
              const SizedBox(width: AppSpacing.s3),
              _LegendDot(
                color: ds.primary,
                label: '${l.inProgress} ${model.runningCount}',
              ),
              const SizedBox(width: AppSpacing.s3),
              _LegendDot(
                color: ds.work,
                label: '${l.upcoming} ${model.upcomingCount}',
              ),
            ],
            const Spacer(),
            Flexible(
              child: Text(
                '${l.scheduledLabel} ${_minutesSpan(l, model.plannedMinutes)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.small.copyWith(
                  color: ds.ink3,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Flexible(
              child: Text(
                '${l.freeLabel} ${_span(l, day, day.add(Duration(minutes: model.freeMinutes)))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.small.copyWith(
                  color: ds.ink2,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppTypography.small.copyWith(color: ds.ink3)),
      ],
    );
  }
}

class _MobileHead extends StatelessWidget {
  const _MobileHead({
    required this.l,
    required this.model,
    required this.day,
    required this.now,
  });

  final AppLocalizations l;
  final _Model model;
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.line)),
      ),
      child: Row(
        children: [
          Text(
            l.eventsAndFree(model.plannedCount),
            style: AppTypography.small.copyWith(color: ds.ink3),
          ),
          const Spacer(),
          Text(
            '${l.freeLabel} ${_minutesSpan(l, model.freeMinutes)}',
            style: AppTypography.small.copyWith(
              color: ds.ink2,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- panel

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({
    required this.l,
    required this.model,
    required this.onTodoTap,
    required this.onToggle,
    required this.onAdd,
    required this.onShowAll,
    required this.nextGap,
  });

  final AppLocalizations l;
  final _Model model;
  final void Function(Todo todo)? onTodoTap;
  final Future<void> Function(Todo todo, {String? occurrenceId}) onToggle;
  final VoidCallback onAdd;
  final VoidCallback? onShowAll;
  final _GapInfo? nextGap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final rows = model.panelRows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s6,
      ),
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                l.todayTasks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyStrong.copyWith(color: ds.ink),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Text(
              '${rows.length}',
              style: AppTypography.small.copyWith(
                color: ds.ink3,
                fontFeatures: AppTypography.tabular,
              ),
            ),
            const Spacer(),
            if (model.overdueCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: ds.dangerSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${l.overdue} ${model.overdueCount}',
                  style: AppTypography.small.copyWith(
                    color: ds.danger,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Text(
              l.actionNothingNow,
              style: AppTypography.small.copyWith(color: ds.ink3),
            ),
          )
        else
          for (final row in rows.take(9))
            _PanelRow(
              row: row,
              onTap: () => onTodoTap?.call(row.todo),
              onToggle: () =>
                  onToggle(row.todo, occurrenceId: row.occurrenceId),
            ),
        const SizedBox(height: AppSpacing.s3),
        _GhostButton(
          key: const ValueKey('workspace-create-todo'),
          label: l.quickAddTodo,
          onTap: onAdd,
        ),
        const SizedBox(height: AppSpacing.s5),
        Container(height: 1, color: ds.lineSoft),
        const SizedBox(height: AppSpacing.s3),
        if (nextGap != null) ...[
          Text(
            l.nextOpening,
            style: AppTypography.overline.copyWith(
              fontSize: 11,
              letterSpacing: 0,
              color: ds.ink3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${DateFormatters.formatTime(nextGap!.start)} – ${DateFormatters.formatTime(nextGap!.end)}',
                style: AppTypography.caption.copyWith(
                  color: ds.ink2,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                _span(l, nextGap!.start, nextGap!.end),
                style: AppTypography.small.copyWith(color: ds.ink3),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            Text(
              l.completedLabel,
              style: AppTypography.small.copyWith(color: ds.ink3),
            ),
            const Spacer(),
            Text(
              '${model.completedTotal} / ${model.completedTotal + rows.length}',
              style: AppTypography.small.copyWith(
                color: ds.ink2,
                fontFeatures: AppTypography.tabular,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.row,
    required this.onTap,
    required this.onToggle,
  });

  final _PanelRowData row;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final overdue = row.overdue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              _CheckTap(
                key: ValueKey('action-complete-${row.todo.id}'),
                label: row.todo.summary,
                onTap: onToggle,
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  row.todo.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: ds.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              if (overdue)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ds.dangerSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    row.overdueDays > 0
                        ? l.overdueDays(row.overdueDays)
                        : l.overdue,
                    style: AppTypography.small.copyWith(
                      color: ds.danger,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                )
              else
                Text(
                  row.dueLabel,
                  style: AppTypography.small.copyWith(
                    color: ds.ink3,
                    height: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckTap extends StatelessWidget {
  const _CheckTap({super.key, required this.onTap, this.label});

  final VoidCallback onTap;

  /// The task this box completes. A bare circle announces nothing to a screen
  /// reader, so the row's own title is what the control is labelled with.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Semantics(
      button: true,
      label: label,
      hint: AppLocalizations.of(context)?.markComplete,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // The circle is 15px; the box that catches the tap has to be a
          // finger, not a cursor — a 28px target is missed more often than hit.
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ds.faint, width: 1.5),
                  color: ds.surface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.add, size: 12, color: ds.ink2),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTypography.small.copyWith(
                  color: ds.ink2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSheet extends StatelessWidget {
  const _MobileSheet({
    required this.l,
    required this.model,
    required this.onTap,
    required this.onToggle,
  });

  final AppLocalizations l;
  final _Model model;
  final void Function(Todo todo)? onTap;
  final Future<void> Function(Todo todo, {String? occurrenceId}) onToggle;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final rows = model.panelRows;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ds.doneLine,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s2,
            AppSpacing.s4,
            AppSpacing.s2,
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  l.todayStillOpen(rows.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong.copyWith(color: ds.ink),
                ),
              ),
              if (model.overdueCount > 0) ...[
                const SizedBox(width: AppSpacing.s2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ds.dangerSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${l.overdue} ${model.overdueCount}',
                    style: AppTypography.small.copyWith(
                      color: ds.danger,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s2,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Text(
              l.actionNothingNow,
              style: AppTypography.small.copyWith(color: ds.ink3),
            ),
          ),
        // The header counts every open item, so the list has to be able to
        // show them: stopping at three told the reader "4 left" and then hid
        // the fourth with no way to reach it.
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap?.call(row.todo),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: ds.lineSoft)),
                  ),
                  child: Row(
                    children: [
                      _CheckTap(
                        key: ValueKey('action-complete-${row.todo.id}'),
                        label: row.todo.summary,
                        onTap: () => onToggle(
                          row.todo,
                          occurrenceId: row.occurrenceId,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s1),
                      Expanded(
                        child: Text(
                          row.todo.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: ds.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        row.overdue ? l.overdue : row.dueLabel,
                        style: AppTypography.small.copyWith(
                          color: row.overdue ? ds.danger : ds.ink3,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------- model

class _Model {
  _Model({
    required this.plannedCount,
    required this.plannedMinutes,
    required this.completedTotal,
    required this.runningCount,
    required this.upcomingCount,
    required this.overdueCount,
    required this.panelRows,
    required this.dayEvents,
    required this.dayAllocations,
  });

  final List<CalendaEventAdapter> dayEvents;
  final List<TaskAllocationCalendarItem> dayAllocations;

  final int plannedCount;
  final int plannedMinutes;
  final int completedTotal;
  final int runningCount;
  final int upcomingCount;
  final int overdueCount;
  final List<_PanelRowData> panelRows;

  int get freeMinutes => (15 * 60 - plannedMinutes).clamp(0, 15 * 60);

  static _Model build(
    ActionProjectionData data,
    DateTime day,
    DateTime now,
    AppLocalizations l,
  ) {
    // The projection carries a whole loaded range; this screen is about one
    // day, so every number and every block below counts only that day.
    final dayEvents = [
      for (final event in data.events)
        if (_sameDay(event.start, day) || _sameDay(event.end, day)) event,
    ];
    final dayAllocations = [
      for (final item in data.allocations)
        if (_sameDay(item.allocation.startAt.toLocal(), day) ||
            _sameDay(item.allocation.endAt.toLocal(), day))
          item,
    ];
    var plannedMinutes = 0;
    var plannedCount = 0;
    var running = 0;
    var upcoming = 0;
    for (final event in dayEvents) {
      if (event.isAllDay) continue;
      plannedCount++;
      plannedMinutes += event.end.difference(event.start).inMinutes;
      if (!event.start.isAfter(now) && event.end.isAfter(now)) running++;
      if (event.start.isAfter(now)) upcoming++;
    }
    for (final item in dayAllocations) {
      final start = item.allocation.startAt.toLocal();
      final end = item.allocation.endAt.toLocal();
      plannedCount++;
      plannedMinutes += end.difference(start).inMinutes;
      if (!start.isAfter(now) && end.isAfter(now)) running++;
      if (start.isAfter(now)) upcoming++;
    }

    final rows = <_PanelRowData>[];
    final today = DateTime(now.year, now.month, now.day);
    String dueLabelFor(Todo todo) {
      final due = todo.dueDate?.toLocal();
      if (due == null) return '';
      if (due.hour == 0 && due.minute == 0) {
        final days = DateTime(
          due.year,
          due.month,
          due.day,
        ).difference(today).inDays;
        if (days == 0) return l.today;
        if (days == 1) return l.tomorrow;
        return '${due.month}/${due.day}';
      }
      return DateFormatters.formatTime(due);
    }

    for (final todo in data.overdueTodos) {
      final due = todo.dueDate?.toLocal();
      final days = due == null
          ? 0
          : today.difference(DateTime(due.year, due.month, due.day)).inDays;
      rows.add(
        _PanelRowData(
          todo: todo,
          overdue: true,
          overdueDays: days,
          dueLabel: '',
        ),
      );
    }
    for (final todo in data.dueTodayTodos) {
      if (rows.any((r) => r.todo.id == todo.id)) continue;
      rows.add(
        _PanelRowData(todo: todo, overdue: false, dueLabel: dueLabelFor(todo)),
      );
    }
    for (final instance in data.todayTaskInstances) {
      if (rows.any(
        (r) =>
            r.todo.id == instance.todoId &&
            r.occurrenceId == instance.occurrenceId,
      )) {
        continue;
      }
      rows.add(
        _PanelRowData(
          todo: instance.todo,
          overdue: false,
          dueLabel: '',
          occurrenceId: instance.occurrenceId,
        ),
      );
    }

    return _Model(
      dayEvents: dayEvents,
      dayAllocations: dayAllocations,
      plannedCount: plannedCount,
      plannedMinutes: plannedMinutes,
      completedTotal:
          data.completedTodayTodos.length +
          data.completedTodayTaskInstances.length,
      runningCount: running,
      upcomingCount: upcoming,
      // The badge sits on the same line as the row count, so it has to count
      // the rows: it used to total every overdue todo and missed occurrence in
      // the loaded range and print "8" above a list of four.
      overdueCount: rows.where((row) => row.overdue).length,
      panelRows: rows,
    );
  }
}

class _PanelRowData {
  const _PanelRowData({
    required this.todo,
    required this.overdue,
    required this.dueLabel,
    this.overdueDays = 0,
    this.occurrenceId,
  });

  final Todo todo;
  final bool overdue;
  final int overdueDays;
  final String dueLabel;
  final String? occurrenceId;
}
