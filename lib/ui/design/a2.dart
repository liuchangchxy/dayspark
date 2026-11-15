import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';

/// A″ primitives: the shapes the accepted final design defines once and every
/// page reuses. Geometry is copied from
/// `design/opendesign/a2-visual-rebase-2026-11-15/shared.css`; colours and type
/// come from the Direction C token set, so nothing here invents a value.
///
/// Do not fold these back into [DsRow]/[DsGroupHead]: the A″ row pads
/// 12/8/16/8 and the A″ group head is 30 high with a hairline, which is not
/// what those widgets draw.

const double kA2TopBarHeight = 54;
const double kA2GroupHeadHeight = 30;
const double kA2RowMinHeight = 52;
const double kA2CaptureHeight = 48;
const double kA2DockHeight = 56;
const double kA2TimeColumn = 52;
const double kA2BlockRadius = 6;

TextStyle _t(double size, FontWeight weight, Color color, {double? height}) {
  return AppTypography.fallback.isEmpty
      ? TextStyle(fontSize: size, fontWeight: weight, color: color)
      : TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          fontFamilyFallback: AppTypography.fallback,
        );
}

class A2Clock extends StatelessWidget {
  const A2Clock({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: ds.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: _t(
            12,
            FontWeight.w600,
            ds.primary,
            height: 1,
          ).copyWith(fontFeatures: AppTypography.tabular),
        ),
      ],
    );
  }
}

/// The 54-high page header: one 20/600 title, an optional 11px context line,
/// the clock, then icon actions. It never carries a date picker — browsing
/// lives on the strip below it.
class A2DayHead extends StatelessWidget {
  const A2DayHead({
    super.key,
    required this.title,
    this.subtitle,
    this.clock,
    this.actions = const <Widget>[],
    this.padding = const EdgeInsets.only(left: 16, right: 4),
  });

  final String title;
  final String? subtitle;
  final String? clock;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final sub = subtitle;
    return Container(
      height: kA2TopBarHeight,
      padding: padding,
      color: ds.bg,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(20, FontWeight.w600, ds.ink, height: 1.3).copyWith(
                    letterSpacing: 0.1,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(11, FontWeight.w400, ds.ink3, height: 1.5),
                  ),
              ],
            ),
          ),
          if (clock != null) A2Clock(label: clock!),
          ...actions,
        ],
      ),
    );
  }
}

/// 48x48 hit area, 19px glyph, tertiary ink. `boxed` draws the 30px framed
/// square the desktop design uses for a create action.
class A2IconAction extends StatelessWidget {
  const A2IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.boxed = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onPressed,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: boxed
                    ? Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: ds.surface,
                          border: Border.all(color: ds.line),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, size: 15, color: ds.ink2),
                      )
                    : Icon(icon, size: 19, color: ds.ink3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 30-high section head: 5px dot, 11/600 tracked label, 11 faint count, then an
/// optional trailing control. A hairline sits on top, as in the design.
class A2GroupHead extends StatelessWidget {
  const A2GroupHead({
    super.key,
    required this.label,
    this.count,
    this.countLabel,
    this.danger = false,
    this.tone,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.topBorder = true,
  });

  final String label;
  final int? count;

  /// Rendered instead of the bare number when the design spells the unit out
  /// ("8 项").
  final String? countLabel;
  final bool danger;

  /// Overrides the label colour (the 今天截止 head is `warn`, not `ink3`).
  final Color? tone;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final color = tone ?? (danger ? ds.danger : ds.ink3);
    final row = Container(
      height: kA2GroupHeadHeight,
      padding: padding,
      decoration: BoxDecoration(
        color: ds.bg,
        border: topBorder
            ? Border(top: BorderSide(color: ds.lineSoft))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: danger ? ds.danger : ds.faint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          // The label takes the slack so the count and the trailing control
          // sit on the right edge. A Flexible label beside a Spacer split the
          // free width in half and parked the count mid-row.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(11, FontWeight.w600, color, height: 1.2).copyWith(
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (countLabel != null)
            Text(
              countLabel!,
              style: _t(11, FontWeight.w400, ds.faint, height: 1.2).copyWith(
                fontFeatures: AppTypography.tabular,
              ),
            )
          else if (count != null)
            Text(
              '$count',
              style: _t(11, FontWeight.w400, ds.faint, height: 1.2).copyWith(
                fontFeatures: AppTypography.tabular,
              ),
            ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
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

/// One line of 12px metadata, centred, each part allowed to shrink so a long
/// deadline never pushes the row wider than the screen.
class A2MetaLine extends StatelessWidget {
  const A2MetaLine({super.key, required this.parts});

  final List<Widget> parts;

  /// Only prose gives way. A separator, a spacer or a chip is a fixed mark:
  /// letting flex hand every part an equal share truncated the due time to
  /// "Due today 1…" while the dot beside it kept its full width.
  static bool shrinks(Widget part) => part is A2MetaText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          for (final part in parts)
            if (shrinks(part))
              Flexible(fit: FlexFit.loose, child: part)
            else
              part,
        ],
      ),
    );
  }
}

class A2MetaText extends StatelessWidget {
  const A2MetaText(
    this.text, {
    super.key,
    this.color,
    this.weight = FontWeight.w400,
  });

  final String text;
  final Color? color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: _t(12, weight, color ?? ds.ink3, height: 1.5).copyWith(
        fontFeatures: AppTypography.tabular,
      ),
    );
  }
}

class A2Sep extends StatelessWidget {
  const A2Sep({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: _t(12, FontWeight.w400, context.ds.ink3)),
    );
  }
}

/// The Direction C due capsule: `surface-2` with a 5px primary dot, and a
/// danger fill once the item is overdue. Overdue is only ever judged on the
/// Today page, so every other surface passes `overdue: false`.
class A2DueCapsule extends StatelessWidget {
  const A2DueCapsule({
    super.key,
    required this.label,
    this.overdue = false,
  });

  final String label;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: overdue ? ds.dangerSoft : ds.surface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: overdue ? ds.danger : ds.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _t(
                11,
                FontWeight.w500,
                overdue ? ds.danger : ds.ink2,
                height: 14 / 11,
              ).copyWith(fontFeatures: AppTypography.tabular),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 4-radius inline chip used inside a block's meta line ("去安排").
class A2InlineChip extends StatelessWidget {
  const A2InlineChip({
    super.key,
    required this.label,
    this.color,
    this.background,
    this.onTap,
  });

  final String label;
  final Color? color;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? ds.surface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: _t(11, FontWeight.w500, color ?? ds.ink2, height: 1),
      ),
    );
    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

/// The list row: 12/8/16/8 padding, a 48px check target, a 15/400 title that
/// may take two lines, and one metadata line. 52 is the floor; with the check
/// box a single-line row measures 64, which is what the design renders.
class A2Row extends StatelessWidget {
  const A2Row({
    super.key,
    required this.title,
    this.meta = const <Widget>[],
    this.checked = false,
    this.onToggle,
    this.onTap,
    this.trailing,
    this.showCheck = true,
    this.titleMaxLines = 2,
    this.selected = false,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 16, 8),
    this.titleColor,
    this.background,
  });

  final String title;
  final List<Widget> meta;
  final bool checked;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showCheck;
  final int titleMaxLines;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final Color? titleColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final row = Container(
      constraints: const BoxConstraints(minHeight: kA2RowMinHeight),
      padding: padding,
      decoration: selected
          ? BoxDecoration(color: ds.primarySoft)
          : background == null
          ? null
          : BoxDecoration(color: background),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showCheck)
            DsCheck(
              checked: checked,
              onChanged: onToggle,
              label: title,
            )
          else
            const SizedBox(width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                      15,
                      FontWeight.w400,
                      titleColor ??
                          (checked ? ds.doneInk : ds.ink),
                      height: 1.45,
                    ).copyWith(
                      decoration: checked ? TextDecoration.lineThrough : null,
                      decorationColor: ds.doneInk,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    A2MetaLine(parts: meta),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: trailing,
            ),
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

/// The bottom capture row: a 16px tertiary plus, a 15px placeholder, and the
/// 11px key hint. There is no filled button here — the one filled primary on
/// a screen belongs to the composer and the calendar FAB.
class A2CaptureBar extends StatefulWidget {
  const A2CaptureBar({
    super.key,
    required this.placeholder,
    required this.hint,
    required this.onSubmit,
    this.onFocusChange,
    this.fieldKey,
  });

  final String placeholder;
  final String hint;
  final Future<void> Function(String text) onSubmit;
  final ValueChanged<bool>? onFocusChange;
  final Key? fieldKey;

  @override
  State<A2CaptureBar> createState() => A2CaptureBarState();
}

class A2CaptureBarState extends State<A2CaptureBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
    widget.onFocusChange?.call(_focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.onSubmit(text);
    if (!mounted) return;
    _focus.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final active = _focus.hasFocus;
    return Container(
      height: kA2CaptureHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(top: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.plus, size: 16, color: ds.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
                key: widget.fieldKey,
                controller: _controller,
                focusNode: _focus,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                cursorColor: ds.primary,
                style: _t(
                  15,
                  FontWeight.w400,
                  active ? ds.ink : ds.ink3,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.placeholder,
                  hintStyle: _t(
                    15,
                    FontWeight.w400,
                    ds.ink3,
                    height: 1.45,
                  ),
                ),
              ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.hint,
            style: _t(11, FontWeight.w400, ds.faint).copyWith(
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「安排到这一天」: the only create entry on a browsed date. A 44-high filled
/// button with its one-line context label above it.
class A2PlanBar extends StatelessWidget {
  const A2PlanBar({
    super.key,
    required this.label,
    required this.actionLabel,
    required this.onPressed,
    this.caption,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onPressed;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(top: BorderSide(color: ds.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(12, FontWeight.w400, ds.ink3, height: 1.4),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: ds.primary,
                foregroundColor: ds.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.plus, size: 16, color: ds.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    actionLabel,
                    style: _t(15, FontWeight.w600, ds.onPrimary),
                  ),
                ],
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              textAlign: TextAlign.center,
              style: _t(11, FontWeight.w400, ds.faint),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Direction C empty state: a surface-2 box, 13/500 title, 12px hint.
class A2Empty extends StatelessWidget {
  const A2Empty({
    super.key,
    required this.title,
    this.hint,
    this.action,
    this.icon,
  });

  final String title;
  final String? hint;
  final Widget? action;

  /// The mark above the text. The design gives the empty box a clock, so the
  /// page reads as "nothing on the clock" rather than as a failure.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ds.surface2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: ds.ink3),
                const SizedBox(height: 10),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: _t(13, FontWeight.w500, ds.ink2),
              ),
              if (hint != null) ...[
                const SizedBox(height: 6),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: _t(12, FontWeight.w400, ds.ink3, height: 1.5),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 12),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum A2BlockKind { event, allocation, due }

/// A timeline block. Events carry their calendar tint and are not checkable;
/// an allocation carries the work tint and a checkbox; a bare deadline is a
/// white card with a warn edge (danger once overdue).
class A2Block extends StatelessWidget {
  const A2Block({
    super.key,
    required this.kind,
    required this.title,
    this.accent,
    this.fill,
    this.meta = const <Widget>[],
    this.checked = false,
    this.onToggle,
    this.onTap,
    this.trailing,
    this.done = false,
  });

  final A2BlockKind kind;
  final String title;
  final Color? accent;
  final Color? fill;
  final List<Widget> meta;
  final bool checked;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final edge = accent ??
        switch (kind) {
          A2BlockKind.event => ds.ink3,
          A2BlockKind.allocation => ds.work,
          A2BlockKind.due => ds.warn,
        };
    final background = fill ??
        switch (kind) {
          A2BlockKind.event => ds.surface,
          A2BlockKind.allocation => ds.workBg,
          A2BlockKind.due => ds.surface,
        };
    final titleStyle = _t(
      12,
      FontWeight.w600,
      done ? ds.doneInk : ds.ink,
      height: 1.25,
    ).copyWith(
      decoration: done ? TextDecoration.lineThrough : null,
      decorationColor: ds.doneInk,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          SizedBox(
            height: 16,
            child: Row(
              children: [
                for (final part in meta)
                  if (A2MetaLine.shrinks(part))
                    Flexible(fit: FlexFit.loose, child: part)
                  else
                    part,
              ],
            ),
          ),
        ],
      ],
    );
    final inner = kind == A2BlockKind.event
        ? Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: body),
                if (trailing != null) trailing!,
              ],
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DsCheck(checked: checked, onChanged: onToggle, label: title),
              const SizedBox(width: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: body),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              ),
            ],
          );
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(kA2BlockRadius),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: ds.line),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: edge),
              Expanded(child: inner),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// A timeline row: a 52px time gutter and the block beside it.
class A2TimelineItem extends StatelessWidget {
  const A2TimelineItem({
    super.key,
    required this.timeLabel,
    this.durationLabel,
    this.timeColor,
    required this.child,
    this.timeColumn = kA2TimeColumn,
  });

  final String timeLabel;
  final String? durationLabel;
  final Color? timeColor;
  final Widget child;
  final double timeColumn;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: timeColumn,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeLabel,
                  maxLines: 1,
                  softWrap: false,
                  style: _t(
                    12,
                    FontWeight.w400,
                    timeColor ?? ds.ink3,
                    height: 1,
                  ).copyWith(fontFeatures: AppTypography.tabular),
                ),
                if (durationLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    durationLabel!,
                    maxLines: 1,
                    softWrap: false,
                    style: _t(11, FontWeight.w400, ds.faint, height: 1),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The calendar create key: 48 square, 8 radius, filled, bottom-right.
class A2Fab extends StatelessWidget {
  const A2Fab({super.key, required this.onPressed, required this.tooltip});

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Positioned(
      right: 16,
      bottom: 72,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: ds.primary,
          borderRadius: BorderRadius.circular(8),
          elevation: 0,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(CupertinoIcons.plus, size: 20, color: ds.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
