import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// The A″ composer: one sheet that writes exactly what the user expressed.
///
/// `dueDate` is only written from the 截止 row, a [TaskAllocation] only from a
/// chosen slot, and opening the sheet for a browsed day pre-fills neither — the
/// primary button says what will happen before the user taps it.
Future<void> showA2Composer(
  BuildContext context, {
  required DateTime contextDate,
  Todo? todo,
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Theme.of(context).extension<DsColors>()?.scrim,
    builder: (_) => A2ComposerSheet(
      contextDate: contextDate,
      todo: todo,
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

/// Everything the quick sheet has already taken from the user travels with it
/// into the full form. The route is the only channel between the two, so it
/// carries all of it.
String composerCreateRoute({
  DateTime? due,
  DateTime? start,
  DateTime? end,
  String? summary,
}) {
  final text = summary?.trim() ?? '';
  final query = <String, String>{
    if (due != null) 'due': '${due.millisecondsSinceEpoch}',
    if (start != null) 'start': '${start.millisecondsSinceEpoch}',
    if (end != null) 'end': '${end.millisecondsSinceEpoch}',
    if (text.isNotEmpty) 'summary': text,
  };
  if (query.isEmpty) return '/todo/new';
  return '/todo/new?${Uri(queryParameters: query).query}';
}

class A2ComposerSheet extends ConsumerStatefulWidget {
  const A2ComposerSheet({
    super.key,
    required this.contextDate,
    this.todo,
    this.initialStart,
    this.initialEnd,
  });

  final DateTime contextDate;
  final Todo? todo;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  ConsumerState<A2ComposerSheet> createState() => _A2ComposerSheetState();
}

class _A2ComposerSheetState extends ConsumerState<A2ComposerSheet> {
  late final TextEditingController _title;
  DateTime? _due;
  DateTime? _start;
  DateTime? _end;
  int? _calendarId;
  int _priority = 0;
  Duration? _reminderOffset;
  bool _planOpen = false;
  bool _saving = false;

  bool get _scheduling => widget.todo != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.todo?.summary ?? '');
    _due = widget.todo?.dueDate;
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _priority = widget.todo?.priority ?? 0;
    _calendarId = widget.todo?.calendarId;
    _planOpen = _start != null;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _md(DateTime d) => '${d.month}/${d.day}';

  String _mdhm(DateTime d) =>
      '${d.month}/${d.day} ${DateFormatters.formatTime(d)}';

  String _range(DateTime start, DateTime end) =>
      '${DateFormatters.formatTime(start)}–${DateFormatters.formatTime(end)}';

  Future<void> _pickDue() async {
    final l = AppLocalizations.of(context)!;
    final picked = await pickDeadline(
      context,
      initial: _due ?? widget.contextDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _due = picked);
    if (!mounted) return;
    final addTime = await showDsSheet<bool>(
      context: context,
      title: l.deadline,
      body: Column(
        children: [
          DsSettingRow(
            label: l.dateOnly,
            onTap: () => Navigator.of(context).pop(false),
          ),
          DsSettingRow(
            label: l.addTime,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (addTime != true || !mounted) return;
    final withTime = await pickDeadline(
      context,
      initial: DateTime(picked.year, picked.month, picked.day, 18),
      withTime: true,
    );
    if (withTime != null && mounted) setState(() => _due = withTime);
  }

  Future<void> _pickCustomSlot() async {
    final l = AppLocalizations.of(context)!;
    final start = await pickDateTime(
      context,
      initial: _start ?? DateTime(
        widget.contextDate.year,
        widget.contextDate.month,
        widget.contextDate.day,
        9,
      ),
    );
    if (start == null || !mounted) return;
    final length = await showDsSheet<Duration>(
      context: context,
      title: l.executionBlock,
      body: Column(
        children: [
          for (final option in kExecutionLengths)
            DsSettingRow(
              label: _durationLabel(option),
              onTap: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    );
    if (length == null || !mounted) return;
    setState(() {
      _start = start;
      _end = start.add(length);
      _planOpen = true;
    });
  }

  String _durationLabel(Duration d) {
    final l = AppLocalizations.of(context)!;
    if (d.inMinutes == 0) return l.durationMinutes(0);
    if (d.inMinutes % 60 == 0) return l.durationHours(d.inHours);
    return l.durationHoursMinutes(d.inHours, d.inMinutes % 60);
  }

  Future<void> _pickReminder() async {
    final l = AppLocalizations.of(context)!;
    final options = <(Duration?, String)>[
      (null, l.remindNone),
      (Duration.zero, l.remindOnTime),
      (const Duration(minutes: 5), l.remindMinutesBefore(5)),
      (const Duration(minutes: 10), l.remindMinutesBefore(10)),
      (const Duration(minutes: 30), l.remindMinutesBefore(30)),
      (const Duration(hours: 1), l.remindHoursBefore(1)),
      (const Duration(days: 1), l.remindDaysBefore(1)),
    ];
    final picked = await showDsSheet<Duration?>(
      context: context,
      title: l.reminder,
      body: Column(
        children: [
          for (final option in options)
            DsSettingRow(
              label: option.$2,
              selected: _reminderOffset == option.$1,
              trailing: _reminderOffset == option.$1
                  ? Icon(
                      CupertinoIcons.checkmark,
                      size: 17,
                      color: context.ds.primary,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(option.$1),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final anchor = _start ?? _due;
    if (anchor == null) {
      _toast(l.reminderNeedsAnchor);
      return;
    }
    setState(() => _reminderOffset = picked);
  }

  Future<void> _pickCalendar() async {
    final l = AppLocalizations.of(context)!;
    final calendars = await ref.read(calendarsProvider.future);
    if (!mounted) return;
    final picked = await showDsSheet<int>(
      context: context,
      title: l.calendarField,
      body: Column(
        children: [
          for (final calendar in calendars)
            DsSettingRow(
              label: calendar.name,
              selected: _calendarId == calendar.id,
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ColorUtils.parseHex(calendar.color),
                  shape: BoxShape.circle,
                ),
              ),
              onTap: () => Navigator.of(context).pop(calendar.id),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _calendarId = picked);
  }

  Future<void> _pickPriority() async {
    final l = AppLocalizations.of(context)!;
    final picked = await showDsSheet<int>(
      context: context,
      title: l.priority,
      body: Column(
        children: [
          for (final entry in [
            (0, l.priorityNone),
            (9, l.priorityLow),
            (5, l.priorityMedium),
            (1, l.priorityHigh),
          ])
            DsSettingRow(
              label: entry.$2,
              selected: _priority == entry.$1,
              onTap: () => Navigator.of(context).pop(entry.$1),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _priority = picked);
  }

  Future<void> _openFullForm() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.maybeOf(context);
    final title = _title.text.trim();
    navigator.pop();
    if (router == null) return;
    // In scheduling mode the sheet is a view of one existing todo. Its "…"
    // belongs to that todo; sending the sheet's copied fields to the create
    // route made a second todo with the same title and deadline.
    final existing = widget.todo;
    if (_scheduling && existing != null) {
      router.push('/todo/edit', extra: existing);
      return;
    }
    // Everything the sheet has already taken from the user travels with it:
    // dropping the picked block here made the full form silently forget a
    // slot the user had expressed.
    router.push(
      composerCreateRoute(
        due: _due,
        start: _start,
        end: _end,
        summary: title,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    final title = _title.text.trim();
    if (_saving) return;
    if (!_scheduling && title.isEmpty) return;
    if (_scheduling && _start == null) return;
    setState(() => _saving = true);
    try {
      if (_scheduling) {
        final todo = widget.todo!;
        // A recurring series has no single occurrence to plan: the writer
        // refuses an allocation without one, so ask which instance this slot
        // belongs to (the picker opens on the planned day).
        String? occurrenceId;
        if (todo.rrule != null && todo.rrule!.isNotEmpty) {
          final picked = await TodoOccurrencePickerSheet.show(
            context,
            ref: ref,
            todo: todo,
            anchorDate: _start,
          );
          if (picked == null) {
            if (mounted) setState(() => _saving = false);
            return;
          }
          occurrenceId = picked.occurrenceId;
        }
        if (!mounted) return;
        await ref.read(createTaskAllocationProvider)(
          todoId: todo.id,
          startAt: _start!,
          endAt: _end!,
          occurrenceId: occurrenceId,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        _toast(l.scheduledTodoSuccess(widget.todo!.summary));
        return;
      }
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        _toast(l.noCalendar);
        setState(() => _saving = false);
        return;
      }
      final calendarId = _calendarId ?? calendars.first.id;
      final todoId = await ref.read(createTodoProvider)(
        calendarId: calendarId,
        summary: title,
        priority: _priority,
        status: 'NEEDS-ACTION',
        dueDate: _due,
      );
      if (_start != null && _end != null) {
        await ref.read(createTaskAllocationProvider)(
          todoId: todoId,
          startAt: _start!,
          endAt: _end!,
        );
      }
      final anchor = _start ?? _due;
      if (_reminderOffset != null && anchor != null) {
        await ref.read(createReminderProvider)(
          parentType: 'todo',
          parentId: todoId,
          triggerTime: anchor.subtract(_reminderOffset!),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(l.todoCreated);
    } catch (error) {
      debugPrint('composer: save failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(l.actionFailedRetry);
    }
  }

  List<(DateTime, DateTime)> _recommendedSlots() {
    final day = widget.contextDate;
    DateTime at(int hour) =>
        DateTime(day.year, day.month, day.day, hour);
    return [
      (at(9), at(10)),
      (at(12), at(13)),
      (at(14), at(15)),
      (at(16), at(17)),
      (at(19), at(20)),
    ];
  }

  String _primaryLabel(AppLocalizations l) {
    if (_scheduling) {
      if (_start == null) return l.saveToUnplanned;
      return l.savePlannedTo(_md(_start!));
    }
    if (_due != null) {
      final hasTime = _due!.hour != 0 || _due!.minute != 0;
      return l.saveWithDueDate(
        hasTime ? _mdhm(_due!) : _md(_due!),
      );
    }
    if (_start != null) return l.savePlannedTo(_md(_start!));
    return l.saveToUnplanned;
  }

  bool get _canSave =>
      !_saving &&
      (_scheduling ? _start != null : _title.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final dateText = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).format(widget.contextDate);
    final weekday = DateFormat.E(
      Localizations.localeOf(context).toString(),
    ).format(widget.contextDate);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    String? calendarName;
    for (final calendar in calendars) {
      if (calendar.id == (_calendarId ?? calendars.first.id)) {
        calendarName = calendar.name;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: ds.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ds.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.planToDate('$dateText · $weekday'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: ds.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                  _SheetIcon(
                    icon: CupertinoIcons.xmark,
                    tooltip: l.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _titleField(ds, l),
                    const SizedBox(height: 10),
                    _fieldPair(ds, l),
                    if (_planOpen) ...[
                      const SizedBox(height: 8),
                      _slotChips(ds, l),
                    ],
                    const SizedBox(height: 6),
                    _hintLine(ds, l),
                    const SizedBox(height: 8),
                    _subRow(
                      ds,
                      l.reminder,
                      _reminderOffset == null
                          ? l.remindNone
                          : _reminderOffset == Duration.zero
                          ? l.remindOnTime
                          : l.remindMinutesBefore(_reminderOffset!.inMinutes),
                      onTap: _pickReminder,
                    ),
                    _subRow(
                      ds,
                      l.calendarField,
                      calendarName ?? (calendars.isEmpty ? '' : calendars.first.name),
                      strong: calendarName != null,
                      onTap: _pickCalendar,
                    ),
                    _subRow(
                      ds,
                      l.priority,
                      switch (_priority) {
                        1 => l.priorityHigh,
                        5 => l.priorityMedium,
                        9 => l.priorityLow,
                        _ => l.priorityNone,
                      },
                      onTap: _pickPriority,
                    ),
                    _subRow(ds, l.notes, l.composerOptional, last: true),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: ds.lineSoft)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: _openFullForm,
                        style: TextButton.styleFrom(
                          foregroundColor: ds.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Icon(
                          CupertinoIcons.ellipsis,
                          size: 17,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: _canSave ? _save : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: ds.primary,
                          disabledBackgroundColor: ds.surface3,
                          disabledForegroundColor: ds.faint,
                          foregroundColor: ds.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text(_primaryLabel(l)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleField(DsColors ds, AppLocalizations l) {
    final readOnly = _scheduling;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: ds.surface,
        border: Border.all(color: ds.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: readOnly
          ? Text(
              widget.todo!.summary,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: ds.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
            )
          : TextField(
              key: const ValueKey('a2-composer-title'),
              controller: _title,
              autofocus: true,
              maxLines: null,
              cursorColor: ds.primary,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: ds.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: l.composerPlaceholder,
                hintStyle: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: ds.ink3,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
    );
  }

  Widget _fieldPair(DsColors ds, AppLocalizations l) {
    final dueOn = _due != null;
    final allocOn = _start != null;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FieldRow(
          key: const ValueKey('a2-composer-due'),
          icon: CupertinoIcons.flag,
          label: l.deadline,
          value: dueOn
              ? (_due!.hour == 0 && _due!.minute == 0
                    ? _md(_due!)
                    : _mdhm(_due!))
              : l.composerUnset,
          tone: dueOn ? ds.warn : null,
          filled: dueOn,
          fillColor: ds.warnSoft,
          onTap: _scheduling ? null : _pickDue,
        ),
        _FieldRow(
          key: const ValueKey('a2-composer-plan'),
          icon: CupertinoIcons.clock,
          label: l.executionSchedule,
          value: allocOn ? _range(_start!, _end!) : l.composerNoSlot,
          tone: allocOn ? ds.primary : null,
          filled: allocOn,
          fillColor: ds.primarySoft,
          onTap: () => setState(() => _planOpen = !_planOpen),
        ),
      ],
    );
  }

  Widget _slotChips(DsColors ds, AppLocalizations l) {
    final slots = _recommendedSlots();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 3.4,
      children: [
        for (final slot in slots)
          _SlotChip(
            label: _range(slot.$1, slot.$2),
            selected: _start == slot.$1 && _end == slot.$2,
            onTap: () => setState(() {
              _start = slot.$1;
              _end = slot.$2;
            }),
          ),
        _SlotChip(
          label: l.composerCustomSlot,
          selected: _start != null &&
              !slots.any((s) => s.$1 == _start && s.$2 == _end),
          muted: true,
          onTap: _pickCustomSlot,
        ),
      ],
    );
  }

  Widget _hintLine(DsColors ds, AppLocalizations l) {
    final (text, color) = _start != null
        ? (l.composerHintAlloc, ds.primary)
        : _due != null
        ? (l.composerHintDue, ds.warn)
        : (l.composerHintNoSlot, ds.ink3);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.info_circle, size: 12, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: color,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ],
    );
  }

  Widget _subRow(
    DsColors ds,
    String label,
    String value, {
    VoidCallback? onTap,
    bool strong = false,
    bool last = false,
  }) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: ds.ink2,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: strong ? ds.ink : ds.ink3,
                fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 14, color: ds.ink3),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: ds.ink3),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
    this.filled = false,
    this.fillColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? tone;
  final bool filled;
  final Color? fillColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final color = tone ?? ds.ink3;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: filled ? fillColor ?? ds.surface2 : ds.surface,
        borderRadius: BorderRadius.circular(6),
        border: filled ? null : Border.all(color: ds.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: filled ? color : ds.ink2,
                fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ds.primarySoft : ds.surface,
            borderRadius: BorderRadius.circular(6),
            border: selected ? null : Border.all(color: ds.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? ds.primary
                  : muted
                  ? ds.ink3
                  : ds.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ),
    );
  }
}
