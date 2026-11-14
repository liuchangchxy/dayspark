import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// Fast capture: title, then the three chips that change when a task happens.
///
/// Nothing is inherited silently — a context date arrives as a visible chip the
/// user can edit before saving — and nothing navigates away on success: the
/// sheet closes back onto the page it came from with a toast, which is what
/// "quick" means when the user is mid-scan.
Future<void> showTodoQuickCreateSheet(
  BuildContext context, {
  DateTime? contextDate,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final desktop = isWorkspaceLayout(context);
  final form = _QuickCreateForm(contextDate: contextDate);

  if (desktop) {
    return showDsSheet<void>(
      context: context,
      title: AppLocalizations.of(context)!.newTodo,
      body: form,
    ).then((_) {
      messenger.hideCurrentSnackBar();
    });
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.ds.scrim,
    builder: (ctx) {
      final ds = ctx.ds;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
          ),
          decoration: BoxDecoration(
            color: ds.surface,
            borderRadius: AppRadii.sheetTop,
            border: Border(top: BorderSide(color: ds.line)),
            boxShadow: AppShadows.sheet(ds.brightness),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: ds.surface3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    AppSpacing.s3,
                    AppSpacing.s2,
                    AppSpacing.s1,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(ctx)!.newTodo,
                          style: AppTypography.title.copyWith(color: ds.ink),
                        ),
                      ),
                      DsIconButton(
                        icon: CupertinoIcons.xmark,
                        tooltip: MaterialLocalizations.of(
                          ctx,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s1,
                      AppSpacing.s4,
                      AppSpacing.s3,
                    ),
                    child: form,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _QuickCreateForm extends ConsumerStatefulWidget {
  const _QuickCreateForm({this.contextDate});

  /// The browsed day a create started from. It only seeds the plan picker's
  /// opening date; nothing is written from it until the user picks a time.
  final DateTime? contextDate;

  @override
  ConsumerState<_QuickCreateForm> createState() => _QuickCreateFormState();
}

class _QuickCreateFormState extends ConsumerState<_QuickCreateForm> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _due;
  DateTime? _planStart;
  DateTime? _planEnd;
  Duration? _reminderOffset;
  int? _calendarId;
  int _priority = 0;
  final Set<int> _tagIds = {};
  bool _more = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime? get _reminderAnchor => _planStart ?? _due;

  Future<void> _pickDue() async {
    final l = AppLocalizations.of(context)!;
    final date = await pickDeadline(
      context,
      initial: _due ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final withTime = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.ds.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l.dateOnly),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            ListTile(
              title: Text(l.addTime),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (withTime == null || !mounted) return;
    if (!withTime) {
      setState(() => _due = date);
      return;
    }
    final picked = await pickDeadline(
      context,
      initial: date.add(const Duration(hours: 18)),
      withTime: true,
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _pickPlan() async {
    final start = await pickDateTime(
      context,
      initial:
          _planStart ??
          _due ??
          widget.contextDate?.add(const Duration(hours: 9)) ??
          DateTime.now(),
    );
    if (start == null || !mounted) return;
    final l = AppLocalizations.of(context)!;
    final length = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: context.ds.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in kExecutionLengths)
              ListTile(
                title: Text(formatExecutionLength(ctx, option)),
                onTap: () => Navigator.of(ctx).pop(option),
              ),
            if (_planStart != null)
              ListTile(
                title: Text(
                  l.remove,
                  style: TextStyle(color: ctx.ds.danger),
                ),
                onTap: () => Navigator.of(ctx).pop(Duration.zero),
              ),
          ],
        ),
      ),
    );
    if (length == null || !mounted) return;
    setState(() {
      if (length == Duration.zero) {
        _planStart = null;
        _planEnd = null;
      } else {
        _planStart = start;
        _planEnd = start.add(length);
      }
    });
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
    if (picked == null || !mounted) {
      setState(() => _reminderOffset = null);
      return;
    }
    if (_reminderAnchor == null) {
      _toast(l.reminderNeedsAnchor);
      return;
    }
    setState(() => _reminderOffset = picked);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
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
        description: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (_planStart != null && _planEnd != null) {
        await ref.read(createTaskAllocationProvider)(
          todoId: todoId,
          startAt: _planStart!,
          endAt: _planEnd!,
        );
      }
      final anchor = _reminderAnchor;
      if (_reminderOffset != null && anchor != null) {
        await ref.read(createReminderProvider)(
          parentType: 'todo',
          parentId: todoId,
          triggerTime: anchor.subtract(_reminderOffset!),
        );
      }
      for (final tagId in _tagIds) {
        await ref.read(addTagToTodoProvider)(todoId: todoId, tagId: tagId);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.todoCreated)));
    } on Object catch (error) {
      debugPrint('quick create: save failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(l.actionFailedRetry);
    }
  }

  String _landingLabel(AppLocalizations l) {
    final plan = _planStart;
    if (plan != null) {
      final end = _planEnd ?? plan;
      return '${DateFormatters.formatShortDate(plan)} · '
          '${l.plannedExecution} ${DateFormatters.formatTime(plan)}'
          '–${DateFormatters.formatTime(end)}';
    }
    final due = _due;
    if (due != null) return formatDeadline(context, due);
    return l.inbox;
  }

  void _openFullForm() {
    final due = _due;
    final plan = _planStart;
    final query = <String>[
      if (due != null) 'due=${due.millisecondsSinceEpoch}',
      if (plan != null) 'start=${plan.millisecondsSinceEpoch}',
      if (_planEnd != null) 'end=${_planEnd!.millisecondsSinceEpoch}',
    ].join('&');
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(query.isEmpty ? '/todo/new' : '/todo/new?$query');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? const [];
    final selectedCalendar = calendars.where((c) => c.id == _calendarId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DsField(
          label: l.title,
          child: DsTextField(
            key: const ValueKey('todo-quick-create-title'),
            controller: _title,
            hint: l.quickCreateHint,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
        ),
        Wrap(
          spacing: AppSpacing.s1 + 2,
          runSpacing: AppSpacing.s1 + 2,
          children: [
            DsChip(
              label: _due == null
                  ? l.setDeadline
                  : l.deadlinePrefix(formatDeadline(context, _due!)),
              leading: Icon(
                CupertinoIcons.flag,
                size: 13,
                color: _due == null ? ds.ink3 : ds.warn,
              ),
              warm: _due != null,
              onTap: _pickDue,
            ),
            DsChip(
              label: _planStart == null
                  ? l.plannedExecution
                  : '${DateFormatters.formatTime(_planStart!)}–${DateFormatters.formatTime(_planEnd!)}',
              leading: Icon(
                CupertinoIcons.clock,
                size: 13,
                color: _planStart == null ? ds.ink3 : ds.primary,
              ),
              selected: _planStart != null,
              onTap: _pickPlan,
            ),
            DsChip(
              label: _reminderOffset == null
                  ? l.reminder
                  : _reminderLabel(l, _reminderOffset!),
              leading: Icon(
                CupertinoIcons.bell,
                size: 13,
                color: _reminderOffset == null ? ds.ink3 : ds.primary,
              ),
              selected: _reminderOffset != null,
              onTap: _pickReminder,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: Text(
            l.savedAppearsIn(_landingLabel(l)),
            style: AppTypography.small.copyWith(color: ds.ink3),
          ),
        ),
        if (_more) ...[
          const SizedBox(height: AppSpacing.s4),
          DsField(
            label: l.calendar,
            child: Wrap(
              spacing: AppSpacing.s1 + 2,
              runSpacing: AppSpacing.s1 + 2,
              children: [
                for (final calendar in calendars)
                  DsChip(
                    label: calendar.name,
                    selected: (selectedCalendar?.id ?? calendars.first.id) ==
                        calendar.id,
                    leading: DsDot(color: ColorUtils.parseHex(calendar.color)),
                    onTap: () => setState(() => _calendarId = calendar.id),
                  ),
              ],
            ),
          ),
          DsField(
            label: l.priority,
            child: Wrap(
              spacing: AppSpacing.s1 + 2,
              children: [
                for (final (value, label) in [
                  (0, l.priorityNone),
                  (9, l.priorityLow),
                  (5, l.priorityMedium),
                  (1, l.priorityHigh),
                ])
                  DsChip(
                    label: label,
                    selected: _priority == value,
                    onTap: () => setState(() => _priority = value),
                  ),
              ],
            ),
          ),
          if (tags.isNotEmpty)
            DsField(
              label: l.tags,
              child: Wrap(
                spacing: AppSpacing.s1 + 2,
                runSpacing: AppSpacing.s1 + 2,
                children: [
                  for (final tag in tags)
                    DsChip(
                      label: tag.name,
                      selected: _tagIds.contains(tag.id),
                      leading: DsDot(color: ColorUtils.parseHex(tag.color)),
                      onTap: () => setState(() {
                        if (!_tagIds.add(tag.id)) _tagIds.remove(tag.id);
                      }),
                    ),
                ],
              ),
            ),
          DsField(
            label: l.notes,
            child: DsTextField(
              controller: _notes,
              hint: l.notesHint,
              maxLines: 3,
            ),
          ),
          DsSettingRow(
            label: l.openFullForm,
            onTap: _openFullForm,
          ),
        ],
        const SizedBox(height: AppSpacing.s2),
        Row(
          children: [
            DsButton(
              label: _more ? l.lessOptions : l.moreOptions,
              tone: DsButtonTone.ghost,
              onPressed: () => setState(() => _more = !_more),
            ),
            const Spacer(),
            DsButton(
              label: l.save,
              onPressed: _saving ? null : _save,
              loading: _saving,
            ),
          ],
        ),
      ],
    );
  }

  String _reminderLabel(AppLocalizations l, Duration offset) {
    if (offset == Duration.zero) return l.remindOnTime;
    if (offset.inDays >= 1) return l.remindDaysBefore(offset.inDays);
    if (offset.inHours >= 1) return l.remindHoursBefore(offset.inHours);
    return l.remindMinutesBefore(offset.inMinutes);
  }
}
