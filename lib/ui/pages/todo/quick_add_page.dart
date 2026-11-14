import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

class QuickAddPage extends ConsumerStatefulWidget {
  const QuickAddPage({super.key, this.contextDate});

  /// The day the user was looking at when the widget opened this page. It is
  /// context only: nothing is written from it, because a browsed date is not a
  /// deadline.
  final DateTime? contextDate;

  @override
  ConsumerState<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends ConsumerState<QuickAddPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;
  String? _error;
  int? _calendarId;
  int? _reminderMinutes = 10;
  DateTime? _pickedStart;
  Duration? _pickedDuration;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  _QuickAddDraft _draft() => _parseQuickAdd(_controller.text, DateTime.now());

  Calendar? _calendarFor(List<Calendar> calendars, _QuickAddDraft draft) {
    if (calendars.isEmpty) return null;
    final chosen = _calendarId;
    if (chosen != null) {
      for (final calendar in calendars) {
        if (calendar.id == chosen) return calendar;
      }
    }
    final text = _controller.text;
    for (final calendar in calendars) {
      if (calendar.name.isNotEmpty && text.contains(calendar.name)) {
        return calendar;
      }
    }
    return calendars.first;
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _save() async {
    final draft = _draft();
    if (_controller.text.trim().isEmpty || _saving) return;
    if ((_pickedStart ?? draft.start) != null) {
      await _saveEvent(draft);
      return;
    }
    await _saveTodo(draft);
  }

  Future<void> _saveTodo(_QuickAddDraft draft) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final calendars = await ref.read(calendarsProvider.future);
      final calendar = _calendarFor(calendars, draft);
      if (calendar == null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = l.widgetSaveFailed;
        });
        return;
      }
      final start = _pickedStart ?? draft.start;
      final dueDate =
          start == null
          ? draft.date
          : DateTime(start.year, start.month, start.day);
      final summary = draft.title.isEmpty ? text : draft.title;
      final id = await ref.read(createTodoProvider)(
        calendarId: calendar.id,
        summary: summary,
        priority: 0,
        status: 'NEEDS-ACTION',
        dueDate: dueDate,
      );
      final reminder = _reminderMinutes;
      if (start != null && reminder != null && reminder >= 0) {
        await ref.read(createReminderProvider)(
          parentType: 'todo',
          parentId: id,
          triggerTime: start.subtract(Duration(minutes: reminder)),
        );
      }
      if (!mounted) return;
      _close();
    } on Object catch (error) {
      debugPrint('quick_add: create todo failed: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l.widgetSaveFailed;
      });
    }
  }

  Future<void> _saveEvent(_QuickAddDraft draft) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final calendars = await ref.read(calendarsProvider.future);
      final calendar = _calendarFor(calendars, draft);
      if (calendar == null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = l.widgetSaveFailed;
        });
        return;
      }
      final start = _pickedStart ?? draft.start!;
      final duration = _pickedDuration ?? draft.duration;
      final summary = draft.title.isEmpty ? text : draft.title;
      final id = await ref.read(createEventProvider)(
        calendarId: calendar.id,
        summary: summary,
        startDt: start,
        endDt: start.add(duration),
        isAllDay: false,
      );
      final reminder = _reminderMinutes;
      if (reminder != null && reminder >= 0) {
        await ref.read(createReminderProvider)(
          parentType: 'event',
          parentId: id,
          triggerTime: start.subtract(Duration(minutes: reminder)),
        );
      }
      if (!mounted) return;
      _close();
    } on Object catch (error) {
      debugPrint('quick_add: create event failed: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l.widgetSaveFailed;
      });
    }
  }

  Future<void> _pickTime(_QuickAddDraft draft) async {
    final initial =
        _pickedStart ??
        draft.start ??
        DateTime.now().add(const Duration(hours: 1));
    final picked = await pickDateTime(context, initial: initial);
    if (picked == null || !mounted) return;
    setState(() {
      _pickedStart = picked;
      _pickedDuration = _pickedDuration ?? draft.duration;
    });
  }

  Future<void> _pickCalendar(List<Calendar> calendars) async {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final current = _calendarId;
    final picked = await showDsSheet<int>(
      context: context,
      title: l.calendar,
      body: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (calendars.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: Text(
                  l.noCalendar,
                  style: AppTypography.body.copyWith(color: ds.ink3),
                ),
              ),
            for (final calendar in calendars)
              DsSettingRow(
                label: calendar.name,
                leading: DsDot(
                  color: ColorUtils.parseHex(calendar.color),
                  size: 8,
                ),
                selected: calendar.id == current,
                trailing: calendar.id == current
                    ? Icon(
                        CupertinoIcons.checkmark,
                        size: 15,
                        color: ds.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(calendar.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _calendarId = picked);
  }

  Future<void> _pickReminder() async {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final current = _reminderMinutes ?? -1;
    final options = <(int, String)>[
      (-1, l.remindNone),
      (0, l.remindOnTime),
      (5, l.remindMinutesBefore(5)),
      (10, l.remindMinutesBefore(10)),
      (15, l.remindMinutesBefore(15)),
      (30, l.remindMinutesBefore(30)),
      (60, l.remindHoursBefore(1)),
    ];
    final picked = await showDsSheet<int>(
      context: context,
      title: l.reminder,
      body: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (minutes, label) in options)
              DsSettingRow(
                label: label,
                selected: minutes == current,
                trailing: minutes == current
                    ? Icon(
                        CupertinoIcons.checkmark,
                        size: 15,
                        color: ds.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(minutes),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _reminderMinutes = picked < 0 ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final desktop = isWorkspaceLayout(context);
    final draft = _draft();
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final calendar = _calendarFor(calendars, draft);
    final start = _pickedStart ?? draft.start;
    final duration = _pickedDuration ?? draft.duration;
    final hasText = _controller.text.trim().isNotEmpty;
    // The sheet only has something to float over when it was pushed from a
    // page. A cold start from the widget deep link arrives with an empty
    // stack, and a transparent route over nothing renders the window black.
    final overPage = ModalRoute.of(context)?.canPop ?? false;
    final backdrop = overPage ? Colors.transparent : ds.bg;

    if (desktop) {
      return Scaffold(
        backgroundColor: backdrop,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _close,
          },
          child: Focus(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The page under this route is still painted, so the backdrop
                // is a scrim over it rather than a surface of its own; tapping
                // it dismisses the sheet the way a modal is expected to.
                Semantics(
                  button: true,
                  label: l.cancel,
                  onTap: _close,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: ColoredBox(color: ds.scrim),
                  ),
                ),
                Center(
                  child: Container(
                    width: 560,
                    decoration: BoxDecoration(
                      color: ds.surface,
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                      border: Border.all(color: ds.line),
                      boxShadow: AppShadows.two(Theme.of(context).brightness),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _header(context, l),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                          child: _input(context, l, 18),
                        ),
                        if (_error != null) _errorText(l),
                        if (hasText)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                            child: _card(
                              context,
                              l,
                              draft,
                              start,
                              duration,
                              calendar,
                              desktop: true,
                            ),
                          )
                        else
                          const SizedBox(height: 18),
                        _footer(context, l),
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

    return Scaffold(
      backgroundColor: backdrop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: l.cancel,
            onTap: _close,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: ColoredBox(color: ds.scrim.withValues(alpha: 0.30)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                color: ds.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.xl),
                ),
                border: Border.all(color: ds.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 14,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: ds.surface3,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      _mobileHeader(context, l),
                      _input(context, l, 15),
                      if (_error != null) _errorText(l),
                      if (hasText)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _card(
                            context,
                            l,
                            draft,
                            start,
                            duration,
                            calendar,
                            desktop: false,
                          ),
                        ),
                      const Spacer(),
                      // Both destinations stay on the phone: without the
                      // todo button the same sentence could only be saved as
                      // an event, which is a different object entirely.
                      Row(
                        children: [
                          Expanded(
                            child: DsButton(
                              label: l.save,
                              icon: CupertinoIcons.checkmark,
                              expand: true,
                              loading: _saving,
                              onPressed: _saving ? null : _save,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DsButton(
                              label: l.addTodoShort,
                              tone: DsButtonTone.secondary,
                              expand: true,
                              onPressed: _saving
                                  ? null
                                  : () => _saveTodo(_draft()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              border: Border.all(color: ds.primary),
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Icon(CupertinoIcons.add, size: 12, color: ds.primary),
          ),
          const SizedBox(width: 8),
          Text(
            l.quickAdd,
            style: AppTypography.caption.copyWith(
              color: ds.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileHeader(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Text(
            l.quickAdd,
            style: AppTypography.bodyStrong.copyWith(
              color: ds.ink,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 44,
            child: InkWell(
              onTap: _close,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    l.cancel,
                    style: AppTypography.small.copyWith(color: ds.ink3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(BuildContext context, AppLocalizations l, double size) {
    final ds = context.ds;
    final desktop = isWorkspaceLayout(context);
    final field = TextField(
      key: const ValueKey('quick-add-input'),
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      style: AppTypography.body.copyWith(
        color: ds.ink,
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      cursorColor: ds.primary,
      cursorWidth: 2,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      onChanged: (_) => setState(() {
        _pickedStart = null;
        _pickedDuration = null;
      }),
      decoration: InputDecoration(
        hintText: l.quickCreateHint,
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintStyle: AppTypography.body.copyWith(
          color: ds.faint,
          fontSize: size,
        ),
      ),
    );
    if (desktop) return field;
    return Container(
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: ds.line),
      ),
      child: field,
    );
  }

  Widget _errorText(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.s2, 20, 0),
      child: Text(
        _error ?? l.widgetSaveFailed,
        style: TextStyle(fontSize: 12, color: context.ds.danger),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l,
    _QuickAddDraft draft,
    DateTime? start,
    Duration duration,
    Calendar? calendar, {
    required bool desktop,
  }) {
    final ds = context.ds;
    final accent = calendar == null
        ? ds.work
        : ColorUtils.parseHex(calendar.color);
    final event = start != null;
    final day = event
        ? DateTime(start.year, start.month, start.day)
        : draft.date;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              event ? l.events : l.todos,
              style: AppTypography.small.copyWith(
                color: ds.ink3,
                fontSize: 11,
              ),
            ),
            if (event) ...[
              Text(
                ' · ',
                style: AppTypography.small.copyWith(
                  color: ds.ink3,
                  fontSize: 11,
                ),
              ),
              Flexible(
                child: Text(
                  _cardDate(context, l, day, draft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.small.copyWith(
                    color: ds.ink2,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (event)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${DateFormatters.formatTime(start)} – '
                      '${DateFormatters.formatTime(start.add(duration))}',
                ),
                TextSpan(
                  text: '  · ${_durationLabel(l, duration)}',
                  style: TextStyle(
                    fontSize: desktop ? 12 : 11,
                    fontWeight: FontWeight.w400,
                    color: ds.ink3,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyStrong.copyWith(
              color: ds.ink,
              fontSize: desktop ? 18 : 17,
              height: 1.3,
            ),
          )
        else
          Text(
            _cardDate(context, l, day, draft),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyStrong.copyWith(
              color: ds.ink,
              fontSize: desktop ? 18 : 17,
              height: 1.3,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (calendar != null)
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: ds.tint(accent),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    calendar.name,
                    style: AppTypography.small.copyWith(
                      color: ds.eventAccent(accent),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            for (final name in draft.participants)
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: ds.surface,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  border: Border.all(color: ds.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ds.surface3,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        name.substring(0, 1),
                        style: AppTypography.small.copyWith(
                          color: ds.ink2,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      name,
                      style: AppTypography.small.copyWith(
                        color: ds.ink2,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (!desktop) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: ds.lineSoft),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _mobileField(
                  context,
                  l.executionWhen,
                  event ? DateFormatters.formatTime(start) : l.notSet,
                  () => _pickTime(draft),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _mobileField(
                  context,
                  l.calendar,
                  calendar?.name ?? l.noCalendar,
                  () => _pickCalendar(ref.read(calendarsProvider).valueOrNull ?? const []),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _mobileField(
                  context,
                  l.reminder,
                  _reminderLabel(l),
                  _pickReminder,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    final body = desktop
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: main,
                  ),
                ),
                Container(width: 1, color: ds.lineSoft),
                SizedBox(
                  width: 196,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _field(
                          context,
                          l.executionWhen,
                          event ? DateFormatters.formatTime(start) : l.notSet,
                          () => _pickTime(draft),
                          focused: true,
                        ),
                        const SizedBox(height: 6),
                        _field(
                          context,
                          l.calendar,
                          calendar?.name ?? l.noCalendar,
                          () => _pickCalendar(
                            ref.read(calendarsProvider).valueOrNull ?? const [],
                          ),
                        ),
                        const SizedBox(height: 6),
                        _field(
                          context,
                          l.reminder,
                          _reminderLabel(l),
                          _pickReminder,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(12),
            child: main,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        decoration: BoxDecoration(
          color: ds.surface,
          border: Border.all(color: ds.line),
        ),
        child: body,
      ),
    );
  }

  Widget _mobileField(
    BuildContext context,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    final ds = context.ds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: ds.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.small.copyWith(
                color: ds.ink3,
                fontSize: 11,
                height: 1.2,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.small.copyWith(
                color: ds.ink2,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    String value,
    VoidCallback onTap, {
    bool focused = false,
  }) {
    final ds = context.ds;
    final fg = focused ? ds.primary : ds.ink3;
    final vg = focused ? ds.primaryHover : ds.ink2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: focused ? ds.primaryTint : ds.surface,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: focused ? ds.primary : ds.line),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: AppTypography.small.copyWith(
                color: fg,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.small.copyWith(
                  color: vg,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l,
  ) {
    final ds = context.ds;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ds.line)),
      ),
      child: Row(
        children: [
          DsButton(
            label: l.save,
            icon: CupertinoIcons.checkmark,
            small: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(width: 10),
          DsButton(
            label: l.addTodoShort,
            tone: DsButtonTone.secondary,
            small: true,
            onPressed: _saving ? null : () => _saveTodo(_draft()),
          ),
          const Spacer(),
          const DsKeyCap('esc'),
          const SizedBox(width: 6),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            small: true,
            onPressed: _saving ? null : _close,
          ),
        ],
      ),
    );
  }

  String _cardDate(
    BuildContext context,
    AppLocalizations l,
    DateTime? day,
    _QuickAddDraft draft,
  ) {
    if (day == null) return l.noDueDate;
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.MMMd(locale).format(day)} '
        '${DateFormat.E(locale).format(day)}';
  }

  String _durationLabel(AppLocalizations l, Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return l.minutesShort(minutes);
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return l.hoursShort(hours);
    return '${l.hoursShort(hours)} ${l.minutesShort(rest)}';
  }

  String _reminderLabel(AppLocalizations l) {
    final minutes = _reminderMinutes;
    if (minutes == null) return l.remindNone;
    if (minutes == 0) return l.remindOnTime;
    if (minutes % 60 == 0) return l.remindHoursBefore(minutes ~/ 60);
    return l.remindMinutesBefore(minutes);
  }
}

class _QuickAddDraft {
  const _QuickAddDraft({
    required this.title,
    required this.date,
    required this.start,
    required this.duration,
    required this.participants,
  });

  final String title;
  final DateTime? date;
  final DateTime? start;
  final Duration duration;
  final List<String> participants;
}

_QuickAddDraft _parseQuickAdd(String raw, DateTime now) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const _QuickAddDraft(
      title: '',
      date: null,
      start: null,
      duration: Duration(hours: 1),
      participants: [],
    );
  }

  var work = text;
  var duration = const Duration(hours: 1);

  final halfHour = RegExp('半个?小时').firstMatch(work);
  if (halfHour != null) {
    duration = const Duration(minutes: 30);
    work = work.replaceFirst(halfHour.group(0)!, ' ');
  } else {
    final hours = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:个)?\s*小时',
    ).firstMatch(work);
    if (hours != null) {
      final value = double.tryParse(hours.group(1) ?? '');
      if (value != null && value > 0) {
        duration = Duration(minutes: (value * 60).round());
      }
      work = work.replaceFirst(hours.group(0)!, ' ');
    } else {
      final minutes = RegExp(r'(\d+)\s*分钟').firstMatch(work);
      if (minutes != null) {
        final value = int.tryParse(minutes.group(1) ?? '');
        if (value != null && value > 0) {
          duration = Duration(minutes: value);
        }
        work = work.replaceFirst(minutes.group(0)!, ' ');
      }
    }
  }

  var date = DateTime(now.year, now.month, now.day);
  var hasDate = false;
  final explicitDate = RegExp(
    r'(\d{4})-(\d{1,2})-(\d{1,2})',
  ).firstMatch(work);
  if (explicitDate != null) {
    date = DateTime(
      int.parse(explicitDate.group(1)!),
      int.parse(explicitDate.group(2)!),
      int.parse(explicitDate.group(3)!),
    );
    hasDate = true;
    work = work.replaceFirst(explicitDate.group(0)!, ' ');
  } else {
    final monthDay = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(work);
    if (monthDay != null) {
      date = DateTime(
        now.year,
        int.parse(monthDay.group(1)!),
        int.parse(monthDay.group(2)!),
      );
      hasDate = true;
      work = work.replaceFirst(monthDay.group(0)!, ' ');
    } else if (work.contains('大后天')) {
      date = date.add(const Duration(days: 3));
      hasDate = true;
      work = work.replaceFirst('大后天', ' ');
    } else if (work.contains('后天')) {
      date = date.add(const Duration(days: 2));
      hasDate = true;
      work = work.replaceFirst('后天', ' ');
    } else if (work.contains('明天') || work.contains('明日')) {
      date = date.add(const Duration(days: 1));
      hasDate = true;
      work = work.replaceAll(RegExp('明天|明日'), ' ');
    } else if (work.contains('今天') || work.contains('今日')) {
      hasDate = true;
      work = work.replaceAll(RegExp('今天|今日'), ' ');
    } else {
      final weekday = RegExp(
        r'(下)?(?:周|星期)([一二三四五六日天])',
      ).firstMatch(work);
      if (weekday != null) {
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final target = names.indexOf(
              weekday.group(2) == '天' ? '日' : weekday.group(2)!,
            ) +
            1;
        var delta = (target - date.weekday + 7) % 7;
        if (weekday.group(1) != null) {
          delta = delta == 0 ? 7 : delta;
        }
        date = date.add(Duration(days: delta));
        hasDate = true;
        work = work.replaceFirst(weekday.group(0)!, ' ');
      }
    }
  }

  final period = RegExp('凌晨|早上|上午|中午|下午|傍晚|晚上').firstMatch(work);
  var hour = 0;
  var minute = 0;
  var hasTime = false;
  final colon = RegExp(r'(\d{1,2})[:：](\d{2})').firstMatch(work);
  if (colon != null) {
    hour = int.parse(colon.group(1)!);
    minute = int.parse(colon.group(2)!);
    hasTime = true;
    work = work.replaceFirst(colon.group(0)!, ' ');
  } else {
    final clock = RegExp(
      r'([零一二两三四五六七八九十\d]{1,3})(?:点|时)(半|[零一二三四五六七八九十\d]{1,3}分?)?',
    ).firstMatch(work);
    if (clock != null) {
      hour = _number(clock.group(1)!) ?? 0;
      final rest = clock.group(2);
      if (rest == '半') {
        minute = 30;
      } else if (rest != null && rest.isNotEmpty) {
        minute =
            _number(rest.replaceAll('分', '')) ?? 0;
      }
      hasTime = true;
      work = work.replaceFirst(clock.group(0)!, ' ');
    }
  }

  if (hasTime && period != null) {
    final label = period.group(0)!;
    if (label == '下午' || label == '傍晚' || label == '晚上') {
      if (hour < 12) hour += 12;
    } else if (label == '中午' && hour < 11) {
      hour += 12;
    } else if (label == '凌晨' && hour == 12) {
      hour = 0;
    }
    work = work.replaceFirst(label, ' ');
  }

  final participants = <String>[];
  for (final match in RegExp(
    r'(?:和|跟|与)([一-龥]{1,6})',
  ).allMatches(work)) {
    final rawName = match.group(1) ?? '';
    final name = rawName.replaceFirst(
      RegExp('(开会|吃饭|讨论|见面|电话|聊天|碰面|午餐|晚餐|散步|运动|出差)\$'),
      '',
    );
    if (name.isEmpty || name.length > 4) continue;
    if (RegExp('[点天日月号]').hasMatch(name)) continue;
    if (!participants.contains(name)) participants.add(name);
    final connector = match.group(0)!.substring(0, 1);
    work = work.replaceFirst('$connector$name', ' ');
  }

  if (hasTime) {
    time:
    for (final minuteValue in [minute]) {
      if (minuteValue >= 60) break time;
    }
    minute = minute.clamp(0, 59);
    hour = hour.clamp(0, 23);
    date = DateTime(date.year, date.month, date.day, hour, minute);
  }

  if (hasTime) {
    minute = minute.clamp(0, 59);
    hour = hour.clamp(0, 23);
    date = DateTime(date.year, date.month, date.day, hour, minute);
  }

  var title = work
      .replaceAll(RegExp('提前\\s*\\d+\\s*(?:分钟|小时)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  title = title.replaceAll(RegExp(r'^[，,、。\s]+|[，,、。\s]+$'), '');
  if (title.isEmpty) title = text;

  return _QuickAddDraft(
    title: title,
    date: hasDate ? DateTime(date.year, date.month, date.day) : null,
    start: hasTime ? date : null,
    duration: duration,
    participants: participants,
  );
}

int? _number(String input) {
  final direct = int.tryParse(input);
  if (direct != null) return direct;
  const digits = {
    '零': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (input == '十') return 10;
  if (input.startsWith('十')) {
    return 10 + (digits[input.substring(1)] ?? 0);
  }
  final tenAt = input.indexOf('十');
  if (tenAt > 0) {
    final tens = digits[input.substring(0, tenAt)] ?? 0;
    final rest = input.substring(tenAt + 1);
    return tens * 10 + (rest.isEmpty ? 0 : digits[rest] ?? 0);
  }
  return digits[input];
}
