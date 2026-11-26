import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart' show FocusableTap;
import 'package:dayspark/ui/widgets/schedule/repeat_editor.dart';
import 'ds.dart';
import 'spec_pickers.dart';

/// Pure civil date comparison for overdue determination:
/// True if due date is strictly before today's civil date (now).
/// Today is never overdue, regardless of time.
bool isOverdueByDate(DateTime? due, DateTime now) {
  if (due == null) return false;
  final dueDay = DateTime(due.year, due.month, due.day);
  final today = DateTime(now.year, now.month, now.day);
  return dueDay.isBefore(today);
}

/// Formats a due date label according to spec:
/// today / tomorrow / yesterday / M/d, appending HH:mm only if time is non-zero.
String formatDueLabel(AppLocalizations l, DateTime? dueDate, DateTime now) {
  if (dueDate == null) return '';
  final local = dueDate.toLocal();
  final dueDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final yesterday = today.subtract(const Duration(days: 1));

  final String datePart;
  if (dueDay == today) {
    datePart = l.today;
  } else if (dueDay == tomorrow) {
    datePart = l.tomorrow;
  } else if (dueDay == yesterday) {
    datePart = l.yesterday;
  } else {
    datePart = '${local.month}/${local.day}';
  }

  if (local.hour != 0 || local.minute != 0) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$datePart $hh:$mm';
  }
  return datePart;
}

/// Frozen spec checkbox: 16x16 circle, 1.4px border.
/// When checked: SpecTokens.ink fill and white checkmark icon.
class SpecCheck extends StatelessWidget {
  const SpecCheck({
    super.key,
    required this.checked,
    this.onChanged,
    this.label,
    this.touchTargetSize = 48.0,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final double touchTargetSize;

  @override
  Widget build(BuildContext context) {
    return DsCheck(
      checked: checked,
      onChanged: onChanged,
      label: label,
      size: 16,
      compact: touchTargetSize < 40,
    );
  }
}

/// Shared metadata row builder: cal-dot + calendarName, real repeat description,
/// missed count, and plan clock.
///
/// Only renders cal-dot and calendarName if a valid calendar is present.
List<Widget> buildSharedRowMeta(
  BuildContext context, {
  String? calendarName,
  Color? calendarColor,
  String? rrule,
  int? missedCount,
  String? planLabel,
}) {
  final l = AppLocalizations.of(context)!;
  final parts = <Widget>[];

  // cal-dot + calendarName - only if real calendar is present!
  if (calendarName != null && calendarName.isNotEmpty && calendarColor != null) {
    parts.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: calendarColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            calendarName,
            style: const TextStyle(fontSize: 11, color: SpecTokens.muted),
          ),
        ],
      ),
    );
  }

  // Real repeat description
  if (rrule != null && rrule.isNotEmpty) {
    parts.add(const SizedBox(width: 4));
    parts.add(
      Text(
        '· ${describeRepeat(context, rrule)}',
        style: const TextStyle(fontSize: 11, color: SpecTokens.muted),
      ),
    );
  }

  // Missed count
  if (missedCount != null && missedCount > 0) {
    parts.add(const SizedBox(width: 4));
    parts.add(
      Text(
        '· ${l.missed} $missedCount',
        style: const TextStyle(fontSize: 11, color: SpecTokens.red),
      ),
    );
  }

  // Plan clock
  if (planLabel != null && planLabel.isNotEmpty) {
    parts.add(const SizedBox(width: 4));
    parts.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('· ', style: TextStyle(fontSize: 11, color: SpecTokens.muted)),
          const Icon(CupertinoIcons.clock, size: 10, color: SpecTokens.work),
          const SizedBox(width: 2),
          Text(planLabel, style: const TextStyle(fontSize: 11, color: SpecTokens.work)),
        ],
      ),
    );
  }

  return parts;
}

/// Frozen spec task row.
/// check · 标题 · meta · 截止.
class SpecTaskRow extends StatefulWidget {
  const SpecTaskRow({
    super.key,
    required this.title,
    this.meta = const <Widget>[],
    this.checked = false,
    this.onToggle,
    this.onTap,
    this.trailing,
    this.dueLabel,
    this.isOverdue = false,
    this.disabled = false,
    this.selected = false,
    this.onSchedule,
    this.scheduleTooltip,
    this.scheduleKey,
    this.touchTargetSize,
    this.showCheck = true,
    this.mobileFidelity = false,
  });

  final String title;
  final List<Widget> meta;
  final bool checked;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? dueLabel;
  final bool isOverdue;
  final bool disabled;
  final bool selected;
  final VoidCallback? onSchedule;
  final String? scheduleTooltip;
  final Key? scheduleKey;
  final double? touchTargetSize;
  final bool showCheck;
  final bool mobileFidelity;

  @override
  State<SpecTaskRow> createState() => _SpecTaskRowState();
}

class _SpecTaskRowState extends State<SpecTaskRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.disabled;
    final bg = widget.selected
        ? SpecTokens.hair
        : _hovered
            ? SpecTokens.wash
            : Colors.transparent;

    if (widget.mobileFidelity) {
      final isDone = widget.checked;
      final l = AppLocalizations.of(context);
      final scheduleKey = widget.scheduleKey ??
          (widget.onSchedule != null ? const ValueKey('spec-task-schedule') : null);

      final visualRow = Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFF3F3EE), width: 1.0),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 22),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: isDone ? SpecTokens.faint : SpecTokens.ink,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                      height: 1.35,
                    ),
                  ),
                  if (widget.meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: SpecTokens.faint,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                      child: SizedBox(
                        height: 16,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            maxWidth: double.infinity,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: widget.meta,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.dueLabel != null && widget.dueLabel!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: widget.isOverdue
                      ? Colors.transparent
                      : SpecTokens.wash,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  widget.dueLabel!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: widget.isOverdue ? SpecTokens.red : SpecTokens.muted,
                    fontFeatures: AppTypography.tabular,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ],
            if (widget.trailing != null) ...[
              const SizedBox(width: 6),
              widget.trailing!,
            ] else if (widget.onSchedule != null) ...[
              const SizedBox(width: 4),
              const SizedBox(
                width: 32,
                height: 36,
                child: Center(
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 13.5,
                    color: SpecTokens.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

      return Stack(
        children: [
          FocusableTap(
            onTap: enabled ? widget.onTap : null,
            child: visualRow,
          ),
          if (widget.showCheck)
            Positioned(
              left: 3,
              top: 0,
              bottom: 0,
              width: 48,
              child: Center(
                child: DsCheck(
                  checked: isDone,
                  onChanged: enabled ? widget.onToggle : null,
                  label: l?.markComplete ?? widget.title,
                  size: 15,
                  compact: false,
                ),
              ),
            ),
          if (widget.trailing == null && widget.onSchedule != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 54,
              child: Tooltip(
                message: widget.scheduleTooltip ?? '',
                child: FocusableTap(
                  key: scheduleKey,
                  onTap: enabled ? widget.onSchedule : null,
                  semanticsLabel: widget.scheduleTooltip ??
                      AppLocalizations.of(context)?.scheduleAction ??
                      '',
                  borderRadius: BorderRadius.circular(4),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      );
    }

    final isDesktop = MediaQuery.maybeSizeOf(context)?.width != null &&
        MediaQuery.sizeOf(context).width >= 720;
    final targetSize = widget.touchTargetSize ?? (isDesktop ? 32.0 : 48.0);

    return FocusableActionDetector(
      enabled: enabled,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap?.call(),
        ),
      },
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Semantics(
        label: widget.title,
        button: true,
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onTap : null,
          child: Opacity(
            opacity: widget.disabled ? 0.45 : 1.0,
            child: Container(
            constraints: const BoxConstraints(minHeight: 55),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(5),
              border: _focused
                  ? Border.all(color: SpecTokens.ink, width: 1.5)
                  : const Border(
                      bottom: BorderSide(color: Color(0xFFF3F3EE), width: 1.0),
                    ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: isDesktop ? 24 : targetSize,
                  child: Center(
                    child: widget.showCheck
                        ? SpecCheck(
                            checked: widget.checked,
                            onChanged: enabled ? widget.onToggle : null,
                            label: widget.title,
                            touchTargetSize: targetSize,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: widget.checked ? SpecTokens.faint : SpecTokens.ink,
                          decoration: widget.checked ? TextDecoration.lineThrough : null,
                          decorationColor: SpecTokens.faint,
                          fontFamilyFallback: AppTypography.fallback,
                          height: 1.35,
                        ),
                      ),
                      if (widget.meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle(
                          style: const TextStyle(
                            fontSize: 10,
                            color: SpecTokens.faint,
                            fontFeatures: AppTypography.tabular,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                          child: SizedBox(
                            height: 18,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                maxWidth: double.infinity,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: widget.meta,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.dueLabel != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isOverdue
                          ? Colors.transparent
                          : SpecTokens.amberSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.dueLabel!,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: widget.isOverdue
                            ? SpecTokens.red
                            : SpecTokens.amber,
                        fontFeatures: AppTypography.tabular,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                ],
                if (widget.onSchedule != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: widget.scheduleTooltip ?? 'Schedule',
                    child: FocusableTap(
                      key: widget.scheduleKey,
                      onTap: widget.onSchedule,
                      semanticsLabel: widget.scheduleTooltip ??
                          AppLocalizations.of(context)?.scheduleAction ??
                          '',
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          CupertinoIcons.calendar,
                          size: 13.5,
                          color: SpecTokens.faint,
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: 4),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Frozen spec chip kinds: todo/unplanned, plan, due.
enum SpecChipTone { neutral, plan, due, overdue }

class SpecChip extends StatelessWidget {
  const SpecChip({
    super.key,
    required this.label,
    this.tone = SpecChipTone.neutral,
    this.selected = false,
    this.onTap,
    this.leading,
  });

  final String label;
  final SpecChipTone tone;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? SpecTokens.ink
        : switch (tone) {
            SpecChipTone.neutral => SpecTokens.wash,
            SpecChipTone.plan => SpecTokens.workSoft,
            SpecChipTone.due => SpecTokens.amberSoft,
            SpecChipTone.overdue => SpecTokens.redSoft,
          };

    final fg = selected
        ? SpecTokens.paper
        : switch (tone) {
            SpecChipTone.neutral => SpecTokens.muted,
            SpecChipTone.plan => SpecTokens.work,
            SpecChipTone.due => SpecTokens.amber,
            SpecChipTone.overdue => SpecTokens.red,
          };

    final chip = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: fg,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

/// Frozen spec time block: event (light bg + 3px color bar) vs plan (neutral bg + 2px color bar).
enum SpecTimeBlockKind { event, plan }

class SpecTimeBlock extends StatelessWidget {
  const SpecTimeBlock({
    super.key,
    required this.kind,
    required this.title,
    this.meta,
    this.barColor,
    this.bgColor,
    this.onTap,
    this.checked = false,
    this.onToggle,
    this.done = false,
    this.planLabel,
    this.trailing,
  });

  final SpecTimeBlockKind kind;
  final String title;
  final String? meta;
  final Color? barColor;
  final Color? bgColor;
  final VoidCallback? onTap;
  final bool checked;
  final ValueChanged<bool>? onToggle;
  final bool done;
  final String? planLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bar = barColor ??
        (kind == SpecTimeBlockKind.event
            ? SpecTokens.scheduleBlue
            : SpecTokens.work);
    final bg = bgColor ??
        (kind == SpecTimeBlockKind.event
            ? SpecTokens.scheduleBlueSoft
            : const Color(0xFFF1F0EA));
    final barWidth = kind == SpecTimeBlockKind.event ? 3.0 : 2.0;

    final block = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: bar, width: barWidth)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (kind == SpecTimeBlockKind.plan && onToggle != null) ...[
                SpecCheck(
                  checked: checked,
                  onChanged: onToggle,
                  label: title,
                  touchTargetSize: 22,
                ),
                const SizedBox(width: 4),
              ],
              if (kind == SpecTimeBlockKind.plan) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6E9EB),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    planLabel ?? AppLocalizations.of(context)?.planTagLabel ?? 'Plan',
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.05,
                      color: SpecTokens.work,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: done ? SpecTokens.faint : SpecTokens.ink,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: SpecTokens.faint,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
          if (meta != null && meta!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              meta!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: SpecTokens.muted,
                fontFeatures: AppTypography.tabular,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return block;
    return FocusableTap(
      onTap: onTap,
      semanticsLabel: title,
      borderRadius: BorderRadius.circular(6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: block,
      ),
    );
  }
}

/// Frozen spec segmented control (.view-switch).
class SpecSegmented<T> extends StatelessWidget {
  const SpecSegmented({
    super.key,
    required this.current,
    required this.options,
    required this.onChanged,
  });

  final T current;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: SpecTokens.wash,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: value == current ? SpecTokens.paper : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: value == current
                        ? const [
                            BoxShadow(
                              color: Color.fromRGBO(25, 25, 24, 0.06),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: value == current ? FontWeight.w600 : FontWeight.w400,
                      color: value == current ? SpecTokens.ink : SpecTokens.muted,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Frozen spec empty state.
class SpecEmpty extends StatelessWidget {
  const SpecEmpty({
    super.key,
    required this.title,
    this.hint,
    this.icon = CupertinoIcons.time,
    this.action,
  });

  final String title;
  final String? hint;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: SpecTokens.wash,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: SpecTokens.faint),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: SpecTokens.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SpecTokens.faint,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Frozen spec error state.
class SpecErrorState extends StatelessWidget {
  const SpecErrorState({
    super.key,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 26,
              color: SpecTokens.red,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: SpecTokens.ink2,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            const SizedBox(height: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: SpecTokens.wash,
                    border: Border.all(color: SpecTokens.hair2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    retryLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: SpecTokens.ink,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frozen spec delete confirmation dialog ("先确认，再进回收站").
class SpecDeleteConfirmDialog extends StatelessWidget {
  const SpecDeleteConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    required String cancelLabel,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => SpecDeleteConfirmDialog(
        title: title,
        message: message,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SpecTokens.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SpecTokens.hair),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(24, 24, 22, 0.10),
              blurRadius: 50,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SpecTokens.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: SpecTokens.wash,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cancelLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpecTokens.ink2,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: SpecTokens.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: SpecTokens.paper,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Frozen spec now line (.now-line): 5px red circle + 1.5px red line, left margin 52 aligning with rail.
class SpecNowLine extends StatelessWidget {
  const SpecNowLine({super.key, this.time, this.marginLeft = 52.0});

  /// Deprecated in frozen spec (line does not render time text).
  final String? time;
  final double marginLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      margin: EdgeInsets.only(left: marginLeft, top: 3, bottom: 3),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: SpecTokens.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(
              color: SpecTokens.red,
              thickness: 1.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Frozen spec timeline row: 52 time column + 12 rail (hair line + 5px dot + 3px white halo) + 10 gap + content.
class SpecTimelineRow extends StatelessWidget {
  const SpecTimelineRow({
    super.key,
    required this.timeLabel,
    required this.child,
    this.showRail = true,
    this.dotColor,
  });

  final String timeLabel;
  final Widget child;
  final bool showRail;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Text(
                timeLabel,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  color: SpecTokens.faint,
                  fontFeatures: AppTypography.tabular,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 12,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (showRail)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1,
                      color: SpecTokens.hair,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor ?? SpecTokens.faint,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.white,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class SpecAlldayItem {
  const SpecAlldayItem({
    required this.title,
    this.bgColor,
    this.textColor,
    this.barColor,
    this.onTap,
  });

  final String title;
  final Color? bgColor;
  final Color? textColor;
  final Color? barColor;
  final VoidCallback? onTap;
}

/// Frozen spec all-day strip (.allday-strip).
class SpecAlldayStrip extends StatelessWidget {
  const SpecAlldayStrip({
    super.key,
    required this.items,
    this.label,
  });

  final List<SpecAlldayItem> items;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(0, 7, 0, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1.0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label ?? AppLocalizations.of(context)?.allDayLabel ?? 'All Day',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 9.5,
                color: SpecTokens.faint,
                letterSpacing: 0.04,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final item in items)
                  _SpecAlldayChip(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecAlldayChip extends StatelessWidget {
  const _SpecAlldayChip({required this.item});

  final SpecAlldayItem item;

  @override
  Widget build(BuildContext context) {
    final bar = item.barColor ?? SpecTokens.scheduleBlue;
    final bg = item.bgColor ?? SpecTokens.scheduleBlueSoft;
    final ink = item.textColor ?? SpecTokens.ink;

    final chip = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: bar, width: 2.0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );

    if (item.onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        child: chip,
      ),
    );
  }
}

/// Frozen spec mobile top bar: 50px tall, 15px title, one 30px round action.
class SpecMobileTopBar extends StatelessWidget {
  const SpecMobileTopBar({
    super.key,
    required this.title,
    required this.searchTooltip,
    required this.onSearch,
  });

  final String title;
  final String searchTooltip;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: SpecTokens.paper,
        border: Border(bottom: BorderSide(color: SpecTokens.hair, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
                color: SpecTokens.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
          Semantics(
            label: searchTooltip,
            button: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('mobile-top-search'),
                behavior: HitTestBehavior.opaque,
                onTap: onSearch,
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.search,
                      size: 15,
                      color: SpecTokens.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frozen spec plan picker (.plan-card): 430px wide, 10px radius, 0 26px 80px shadow.
class SpecPlanPicker extends StatelessWidget {
  const SpecPlanPicker({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.subLabel,
    required this.startLabel,
    required this.endLabel,
    required this.durationLabel,
    this.contextText,
    this.contextIsOverlap = false,
    this.cancelLabel,
    this.submitLabel,
    this.startTitle,
    this.endTitle,
    this.durationTitle,
    this.onCancel,
    this.onSubmit,
    this.onTapDate,
    this.onTapStart,
    this.onTapEnd,
    this.isEditing = false,
  });

  final String title;
  final String dateLabel;
  final String subLabel;
  final String startLabel;
  final String endLabel;
  final String durationLabel;
  final String? contextText;
  final bool contextIsOverlap;
  final String? cancelLabel;
  final String? submitLabel;
  final String? startTitle;
  final String? endTitle;
  final String? durationTitle;
  final VoidCallback? onCancel;
  final VoidCallback? onSubmit;
  final VoidCallback? onTapDate;
  final VoidCallback? onTapStart;
  final VoidCallback? onTapEnd;
  final bool isEditing;

  static Future<void> show(
    BuildContext context, {
    required Widget child,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color.fromRGBO(25, 25, 24, 0.26),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final effectiveCancel = cancelLabel ?? l.cancel;
    final effectiveSubmit = submitLabel ??
        (isEditing ? l.planSaveTimeAction : l.planSubmitAction);
    final effectiveStart = startTitle ?? l.planStartTime;
    final effectiveEnd = endTitle ?? l.planEndTime;
    final effectiveDuration = durationTitle ?? l.planDuration;

    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: SpecTokens.paper,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(20, 20, 18, 0.26),
            blurRadius: 80,
            offset: Offset(0, 26),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Head
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: SpecTokens.hair)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SpecTokens.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onCancel ?? () => Navigator.of(context).maybePop(),
                      child: const Icon(CupertinoIcons.xmark, size: 12, color: SpecTokens.muted),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onTapDate,
                    child: Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: SpecTokens.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                  const SizedBox(height: 13),
                  // Time boxes
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onTapStart,
                          child: _timeBox(
                            isEditing ? '$effectiveStart · ${l.edit}' : effectiveStart,
                            startLabel,
                            isEditing,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: onTapEnd,
                          child: _timeBox(
                            isEditing ? '$effectiveEnd · ${l.edit}' : effectiveEnd,
                            endLabel,
                            isEditing,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _timeBox(effectiveDuration, durationLabel, false),
                      ),
                    ],
                  ),
                  if (contextText != null && contextText!.isNotEmpty) ...[
                    const SizedBox(height: 13),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: contextIsOverlap
                            ? SpecTokens.amberSoft
                            : const Color(0xFFFBFBF8),
                        border: Border.all(color: SpecTokens.hair),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        contextText!,
                        style: TextStyle(
                          fontSize: 10,
                          color: contextIsOverlap
                              ? SpecTokens.amber
                              : SpecTokens.muted,
                          height: 1.55,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Foot
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFBFBF8),
                border: Border(top: BorderSide(color: SpecTokens.hair)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onCancel ?? () => Navigator.of(context).maybePop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: SpecTokens.hair2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          effectiveCancel,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: SpecTokens.ink,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onSubmit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: SpecTokens.ink,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          effectiveSubmit,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            fontFamilyFallback: AppTypography.fallback,
                          ),
                        ),
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

  Widget _timeBox(String label, String value, bool editing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: editing ? SpecTokens.ink : SpecTokens.hair2,
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: editing
            ? const [
                BoxShadow(
                  color: Color.fromRGBO(25, 25, 24, 0.10),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 8.5,
              color: SpecTokens.faint,
              letterSpacing: 0.04,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: SpecTokens.ink,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
    );
  }
}

/// A block already on the plan date, reduced to what the picker needs to say
/// whether the chosen span overlaps it.
class SpecPlanBlock {
  const SpecPlanBlock({
    required this.start,
    required this.end,
    required this.title,
  });

  final DateTime start;
  final DateTime end;
  final String title;
}

/// Dialog surface wrapping [SpecPlanPicker] for custom slot selection.
class SpecPlanPickerDialog extends StatefulWidget {
  const SpecPlanPickerDialog({
    super.key,
    required this.title,
    required this.initialStart,
    required this.initialEnd,
    this.contextText,
    this.existingBlocks,
    this.isEditing = false,
  });

  final String title;
  final DateTime initialStart;
  final DateTime initialEnd;
  final String? contextText;
  final Future<List<SpecPlanBlock>> Function(DateTime day)? existingBlocks;
  final bool isEditing;

  static Future<(DateTime, DateTime)?> show(
    BuildContext context, {
    required String title,
    required DateTime initialStart,
    required DateTime initialEnd,
    String? contextText,
    Future<List<SpecPlanBlock>> Function(DateTime day)? existingBlocks,
    bool isEditing = false,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (!isDesktop) {
      return showModalBottomSheet<(DateTime, DateTime)>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: SpecPlanPickerDialog(
              title: title,
              initialStart: initialStart,
              initialEnd: initialEnd,
              contextText: contextText,
              existingBlocks: existingBlocks,
              isEditing: isEditing,
            ),
          ),
        ),
      );
    }
    return showDialog<(DateTime, DateTime)>(
      context: context,
      barrierColor: const Color.fromRGBO(25, 25, 24, 0.26),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: SpecPlanPickerDialog(
          title: title,
          initialStart: initialStart,
          initialEnd: initialEnd,
          contextText: contextText,
          existingBlocks: existingBlocks,
          isEditing: isEditing,
        ),
      ),
    );
  }

  @override
  State<SpecPlanPickerDialog> createState() => _SpecPlanPickerDialogState();
}

class _SpecPlanPickerDialogState extends State<SpecPlanPickerDialog> {
  late DateTime _start;
  late DateTime _end;
  List<SpecPlanBlock> _blocks = const [];
  int _blockRequest = 0;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _reloadBlocks();
  }

  Future<void> _reloadBlocks() async {
    final loader = widget.existingBlocks;
    if (loader == null) return;
    final request = ++_blockRequest;
    try {
      final blocks = await loader(_start);
      if (!mounted || request != _blockRequest) return;
      setState(() => _blocks = blocks);
    } on Object catch (error) {
      debugPrint('plan picker: block lookup failed: $error');
    }
  }

  int _minuteOf(DateTime value) => value.hour * 60 + value.minute;

  List<SpecPlanBlock> get _overlaps {
    final start = _minuteOf(_start);
    final end = _minuteOf(_end);
    return [
      for (final block in _blocks)
        if (_minuteOf(block.start) < end && _minuteOf(block.end) > start)
          block,
    ];
  }

  String _contextText(AppLocalizations l, List<SpecPlanBlock> overlaps) {
    final note = l.planOverlapNote;
    if (overlaps.isNotEmpty) {
      final range =
          '${DateFormatters.formatTime(_start)}–${DateFormatters.formatTime(_end)}';
      final titles = overlaps
          .map((block) =>
              '${DateFormatters.formatTime(block.start)} ${block.title}')
          .join(' · ');
      return '${l.planOverlapBlocks(range, overlaps.length)}\n'
          '$titles\n$note';
    }
    if (_blocks.isEmpty) return '${l.planDayEmpty}\n$note';
    final titles = _blocks
        .take(3)
        .map((block) =>
            '${DateFormatters.formatTime(block.start)} ${block.title}')
        .join(' · ');
    return '${l.planDayExisting}\n$titles\n$note';
  }

  String _durationLabel(AppLocalizations l, Duration d) {
    if (d.inMinutes == 0) return l.durationMinutes(0);
    if (d.inMinutes % 60 == 0) return l.durationHours(d.inHours);
    return l.durationHoursMinutes(d.inHours, d.inMinutes % 60);
  }

  String _dayLabel(BuildContext context, DateTime day) {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(day.year, day.month, day.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return '${day.month}/${day.day} · ${l.today}';
    if (diff == 1) return '${day.month}/${day.day} · ${l.tomorrow}';
    return '${day.month}/${day.day}';
  }

  Future<void> _pickDate() async {
    final picked = await showSpecDatePicker(
      context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final duration = _end.difference(_start);
    setState(() {
      _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
      _end = _start.add(duration);
    });
    _reloadBlocks();
  }

  Future<void> _pickStartTime() async {
    final picked = await showSpecTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (picked == null || !mounted) return;
    final duration = _end.difference(_start);
    setState(() {
      _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
      _end = _start.add(duration);
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showSpecTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(_end),
    );
    if (picked == null || !mounted) return;
    final candidate = DateTime(_end.year, _end.month, _end.day, picked.hour, picked.minute);
    if (candidate.isAfter(_start)) {
      setState(() => _end = candidate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final title = widget.title.isNotEmpty
        ? l.planTodoModalTitle(widget.title)
        : l.planSubmitAction;
    final overlaps = _overlaps;
    return SpecPlanPicker(
      title: title,
      dateLabel: _dayLabel(context, _start),
      subLabel: widget.isEditing ? l.planEditSub : l.planTodoSub,
      startLabel: DateFormatters.formatTime(_start),
      endLabel: DateFormatters.formatTime(_end),
      durationLabel: _durationLabel(l, _end.difference(_start)),
      contextText: widget.contextText ?? _contextText(l, overlaps),
      contextIsOverlap: overlaps.isNotEmpty,
      isEditing: widget.isEditing,
      onTapDate: _pickDate,
      onTapStart: _pickStartTime,
      onTapEnd: _pickEndTime,
      onCancel: () => Navigator.of(context).pop(),
      onSubmit: () => Navigator.of(context).pop((_start, _end)),
    );
  }
}

/// The one discard confirmation for a capture draft: a compact panel whose
/// buttons share the row instead of a desktop dialog's action strip, so it
/// fits a phone without overflowing.
Future<bool> confirmCaptureDiscard(
  BuildContext context, {
  required String title,
  required String body,
  required String keepLabel,
  required String discardLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: SpecTokens.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SpecTokens.hair2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x21191918),
              blurRadius: 55,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SpecTokens.ink,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: SpecTokens.ink2,
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: const BorderSide(color: SpecTokens.hair2),
                      ),
                    ),
                    child: Text(
                      keepLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: SpecTokens.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      discardLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result == true;
}
