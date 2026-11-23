import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

class CalendarSlotSheet extends ConsumerStatefulWidget {
  final DateTimeRange range;
  final VoidCallback onCreateEvent;
  final Future<void> Function(Todo todo, String? occurrenceId) onScheduleTodo;
  final Future<List<Todo>> Function() loadSchedulableTodos;

  /// Starts a todo form that will create the todo and its scheduled block in
  /// one save. Null when the caller cannot offer it.
  final VoidCallback? onCreateTodoHere;

  /// True when the tapped range already carries an event. The head then states
  /// the span as a fact instead of labelling it an editable default.
  final bool isExistingBlock;

  const CalendarSlotSheet({
    super.key,
    required this.range,
    required this.onCreateEvent,
    required this.onScheduleTodo,
    required this.loadSchedulableTodos,
    this.onCreateTodoHere,
    this.isExistingBlock = false,
  });

  static Future<void> show({
    required BuildContext context,
    required DateTimeRange range,
    required VoidCallback onCreateEvent,
    required Future<void> Function(Todo todo, String? occurrenceId)
    onScheduleTodo,
    required Future<List<Todo>> Function() loadSchedulableTodos,
    VoidCallback? onCreateTodoHere,
    bool isExistingBlock = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.ds.scrim,
      elevation: 0,
      builder: (ctx) => CalendarSlotSheet(
        range: range,
        onCreateEvent: onCreateEvent,
        onScheduleTodo: onScheduleTodo,
        loadSchedulableTodos: loadSchedulableTodos,
        onCreateTodoHere: onCreateTodoHere,
        isExistingBlock: isExistingBlock,
      ),
    );
  }

  @override
  ConsumerState<CalendarSlotSheet> createState() => _CalendarSlotSheetState();
}

TextStyle _slotText(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
  bool tabular = false,
}) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    fontFeatures: tabular ? AppTypography.tabular : null,
  );
  if (AppTypography.fallback.isEmpty) return style;
  return style.copyWith(fontFamilyFallback: AppTypography.fallback);
}

enum _CandidatesState { loading, ready, failed }

class _CalendarSlotSheetState extends ConsumerState<CalendarSlotSheet> {
  bool _showingTodoPicker = false;
  _CandidatesState _candidatesState = _CandidatesState.loading;
  List<Todo> _candidates = const [];

  @override
  void initState() {
    super.initState();
    // The count badge on "Schedule Task" is part of the sheet itself, so the
    // candidate list is read once on open rather than only when that row is
    // tapped. A failure stays on that row; the other two actions never wait.
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final list = await widget.loadSchedulableTodos();
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _candidatesState = _CandidatesState.ready;
      });
    } catch (error) {
      debugPrint(
        'calendar slot sheet: loading schedulable todos failed: $error',
      );
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _candidatesState = _CandidatesState.failed;
      });
    }
  }

  void _retryCandidates() {
    setState(() => _candidatesState = _CandidatesState.loading);
    _loadCandidates();
  }

  void _openTodoPicker() {
    if (_candidatesState == _CandidatesState.failed) return;
    if (_candidatesState == _CandidatesState.ready && _candidates.isEmpty) {
      return;
    }
    setState(() => _showingTodoPicker = true);
  }

  String _dateLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final start = widget.range.start;
    final date = DateFormat.MMMMd(locale).format(start);
    final weekday = DateFormat.E(locale).format(start);
    return '$date · $weekday';
  }

  String _spanLabel() {
    final start = widget.range.start;
    final end = widget.range.end;
    return '${DateFormatters.formatTime(start)}–'
        '${DateFormatters.formatTime(end)}';
  }

  /// The head's second line: a resolved span plus what kind of span it is.
  /// An empty slot carries a chosen length the user can still change, so the
  /// line marks it as editable; an existing block states the span as a fact.
  /// Every action below writes the same `range`, so nothing can drift from it.
  String _rangeDetail(AppLocalizations l) {
    final span = _spanLabel();
    if (widget.isExistingBlock) return '$span · ${l.slotRangeExistingEvent}';
    final minutes = widget.range.end.difference(widget.range.start).inMinutes;
    final length = minutes % 60 == 0
        ? l.durationHours(minutes ~/ 60)
        : l.durationMinutes(minutes);
    return '$span · $length · ${l.slotRangeDefaultEditable}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(top: BorderSide(color: ds.line)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6B141410),
            offset: Offset(0, -10),
            blurRadius: 32,
            spreadRadius: -20,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSheetChrome(
              title: _showingTodoPicker
                  ? l.selectTodoToSchedule
                  : _dateLabel(context),
              headerAction: _showingTodoPicker
                  ? DsIconButton(
                      icon: CupertinoIcons.back,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () =>
                          setState(() => _showingTodoPicker = false),
                    )
                  : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _rangeDetail(l),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _slotText(
                          12,
                          FontWeight.w500,
                          ds.ink3,
                          height: 1.35,
                          tabular: true,
                        ),
                      ),
                    ),
                    if (!_showingTodoPicker) ..._actions(context, l),
                    if (_showingTodoPicker) ..._todoPicker(context, l),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return [
      _SolidActionRow(
        key: const ValueKey('slot-action-event'),
        icon: CupertinoIcons.calendar_badge_plus,
        title: l.createEventOption,
        subtitle: l.createEventDesc,
        onTap: () {
          Navigator.of(context).pop();
          widget.onCreateEvent();
        },
      ),
      if (widget.onCreateTodoHere != null) ...[
        const SizedBox(height: 8),
        _OutlinedActionRow(
          key: const ValueKey('slot-action-create-schedule'),
          icon: CupertinoIcons.add,
          title: l.createTodoAndSchedule,
          subtitle: l.createTodoAndScheduleDesc,
          onTap: () {
            Navigator.of(context).pop();
            widget.onCreateTodoHere!();
          },
        ),
      ],
      const SizedBox(height: 4),
      _ScheduleTodoRow(
        key: const ValueKey('slot-action-schedule-todo'),
        state: _candidatesState,
        count: _candidates.length,
        onTap: _openTodoPicker,
        onRetry: _retryCandidates,
      ),
      if (_candidatesState == _CandidatesState.ready &&
          _candidates.isEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(38, 0, 4, 0),
          child: Text(
            l.slotEmptyCreateHint,
            key: const ValueKey('slot-schedule-empty-hint'),
            maxLines: 2,
            style: _slotText(12, FontWeight.w400, ds.ink3, height: 1.4),
          ),
        ),
        if (widget.onCreateTodoHere != null)
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DsButton(
                key: const ValueKey('slot-empty-create-schedule'),
                label: l.createTodoAndSchedule,
                tone: DsButtonTone.ghost,
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onCreateTodoHere!();
                },
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _todoPicker(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return [
      Container(height: 1, color: ds.lineSoft),
      if (_candidatesState == _CandidatesState.loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_candidatesState == _CandidatesState.failed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.actionFailedRetry,
                textAlign: TextAlign.center,
                style: _slotText(15, FontWeight.w400, ds.ink2, height: 1.4),
              ),
              const SizedBox(height: 6),
              DsButton(
                label: l.retry,
                tone: DsButtonTone.ghost,
                onPressed: _retryCandidates,
              ),
            ],
          ),
        )
      else if (_candidates.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.noSchedulableTodos,
                textAlign: TextAlign.center,
                style: _slotText(15, FontWeight.w400, ds.ink2, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                l.slotEmptyCreateHint,
                textAlign: TextAlign.center,
                style: _slotText(12, FontWeight.w400, ds.ink3, height: 1.4),
              ),
              if (widget.onCreateTodoHere != null) ...[
                const SizedBox(height: 8),
                DsButton(
                  key: const ValueKey('slot-empty-create-schedule'),
                  label: l.createTodoAndSchedule,
                  tone: DsButtonTone.ghost,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onCreateTodoHere!();
                  },
                ),
              ],
            ],
          ),
        )
      else
        Column(
          children: [
            for (final todo in _candidates)
              _SlotRow(
                icon: todo.rrule != null && todo.rrule!.isNotEmpty
                    ? CupertinoIcons.repeat
                    : CupertinoIcons.circle,
                title: todo.summary,
                subtitle: todo.rrule != null && todo.rrule!.isNotEmpty
                    ? l.recurringTask
                    : (todo.dueDate != null
                          ? '${l.dueDate}: ${DateFormatters.formatShortDate(todo.dueDate!)}'
                          : l.noDueDate),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  if (todo.rrule != null && todo.rrule!.isNotEmpty) {
                    final selected = await TodoOccurrencePickerSheet.show(
                      context,
                      ref: ref,
                      todo: todo,
                      anchorDate: widget.range.start,
                    );
                    if (selected == null || !mounted) return;
                    navigator.pop();
                    await _invokeScheduleTodo(todo, selected.occurrenceId);
                  } else {
                    navigator.pop();
                    await _invokeScheduleTodo(todo);
                  }
                },
              ),
          ],
        ),
    ];
  }

  Future<void> _invokeScheduleTodo(Todo todo, [String? occurrenceId]) =>
      widget.onScheduleTodo(todo, occurrenceId);
}

/// The sheet's only filled action. Frequency, not importance, sets the order:
/// creating an event is the everyday path, so it reads as the primary button.
class _SolidActionRow extends StatelessWidget {
  const _SolidActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ds.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(child: Icon(icon, size: 18, color: ds.onPrimary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, ds.onPrimary),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(
                        12,
                        FontWeight.w400,
                        ds.onPrimary.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: ds.onPrimary.withValues(alpha: 0.72),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shortcut, not the main path: outlined on surface-2 so it reads as one
/// step quieter than the filled row above it.
class _OutlinedActionRow extends StatelessWidget {
  const _OutlinedActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ds.surface2,
            border: Border.all(color: ds.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(child: Icon(icon, size: 18, color: ds.ink2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, ds.ink),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(12, FontWeight.w400, ds.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_right, size: 14, color: ds.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The heaviest action sits last and reads as plain text: it opens a second
/// sheet and writes an allocation, so it must never compete with the primary
/// row. The count badge says how much work it leads to; at zero the row is
/// disabled and says why instead of opening an empty picker.
class _ScheduleTodoRow extends StatelessWidget {
  const _ScheduleTodoRow({
    super.key,
    required this.state,
    required this.count,
    required this.onTap,
    required this.onRetry,
  });

  final _CandidatesState state;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final failed = state == _CandidatesState.failed;
    final empty = state == _CandidatesState.ready && count == 0;
    final enabled = !failed && !empty;
    final titleColor = enabled ? ds.ink : ds.ink3;
    final subtitleColor = enabled ? ds.ink2 : ds.ink3;
    final subtitle = failed
        ? l.actionFailedRetry
        : empty
        ? l.noSchedulableTodos
        : l.scheduleTodoDesc;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              Container(
                key: const ValueKey('slot-schedule-count'),
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ds.surface3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state == _CandidatesState.loading ? '·' : '$count',
                  style: _slotText(
                    11,
                    FontWeight.w600,
                    enabled ? ds.ink2 : ds.ink3,
                    height: 1,
                    tabular: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.scheduleTodo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, titleColor),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(12, FontWeight.w400, subtitleColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (failed)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const ValueKey('slot-schedule-retry'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        l.retry,
                        style: _slotText(13, FontWeight.w600, ds.primary),
                      ),
                    ),
                  ),
                )
              else if (enabled)
                Icon(CupertinoIcons.chevron_right, size: 14, color: ds.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ds.lineSoft)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(child: Icon(icon, size: 20, color: ds.ink2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w600, ds.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _slotText(15, FontWeight.w400, ds.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_right, size: 14, color: ds.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
