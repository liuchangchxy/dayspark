import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/l10n/app_localizations.dart';

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
    final enabled = onChanged != null;
    return Semantics(
      checked: checked,
      label: label,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!checked) : null,
          child: SizedBox(
            width: touchTargetSize,
            height: touchTargetSize,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? SpecTokens.ink : SpecTokens.paper,
                  border: Border.all(
                    color: checked ? SpecTokens.ink : const Color(0xFFCFCFC7),
                    width: 1.4,
                  ),
                ),
                child: checked
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        size: 9.5,
                        color: SpecTokens.paper,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    this.touchTargetSize,
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
  final double? touchTargetSize;

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

    final isDesktop = MediaQuery.maybeSizeOf(context)?.width != null &&
        MediaQuery.sizeOf(context).width >= 720;
    final targetSize = widget.touchTargetSize ?? (isDesktop ? 32.0 : 48.0);

    return FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
                    child: SpecCheck(
                      checked: widget.checked,
                      onChanged: enabled ? widget.onToggle : null,
                      label: widget.title,
                      touchTargetSize: targetSize,
                    ),
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: widget.meta,
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
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onSchedule,
                        child: Container(
                          width: 25,
                          height: 25,
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
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
  const SpecNowLine({super.key, this.time});

  /// Deprecated in frozen spec (line does not render time text).
  final String? time;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      margin: const EdgeInsets.only(left: 52, top: 3, bottom: 3),
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
