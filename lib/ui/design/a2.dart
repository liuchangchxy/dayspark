import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/domain/utils/capture_parser.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

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

/// The width the ring occupies at the head of a row; text that has no ring
/// still starts one slot and one gap in, so the column holds.
const double kA2CheckSlot = 48;
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
    final countText = countLabel ?? (count != null ? '$count' : null);
    return FocusableTap(
      onTap: onTap,
      semanticsLabel: countText == null ? label : '$label $countText',
      borderRadius: BorderRadius.circular(4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
    // A completed row can carry four marks (plan, done-at, original due,
    // calendar). Fixed marks that refuse to shrink add up past the row and
    // overflow it, so the whole line also clips: the prose gives way first,
    // and anything still over is cut rather than painted outside the card.
    return SizedBox(
      height: 18,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final part in parts)
                if (shrinks(part))
                  Flexible(fit: FlexFit.loose, child: part)
                else
                  part,
            ],
          ),
        ),
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
            const SizedBox(width: kA2CheckSlot, height: kA2CheckSlot),
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
    return FocusableTap(
      onTap: onTap,
      semanticsLabel: title,
      borderRadius: BorderRadius.circular(4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
    this.controller,
    this.onFocusChange,
    this.fieldKey,
    this.initialDraft,
    this.onDraftChanged,
    this.isShifted,
    this.onExpand,
    this.onParsedSubmit,
    this.typeLabel,
    this.contextLabel,
    this.isEvent = false,
  });

  final String placeholder;
  final String hint;
  final Future<void> Function(String text) onSubmit;
  final TextEditingController? controller;
  final ValueChanged<bool>? onFocusChange;
  final Key? fieldKey;
  final String? initialDraft;
  final ValueChanged<String>? onDraftChanged;
  final bool? isShifted;
  final VoidCallback? onExpand;

  /// The type and date chips are facts, not decoration: a capture opened on
  /// a browsed day writes that day, and an event capture says so.
  final String? typeLabel;
  final String? contextLabel;
  final bool isEvent;

  /// A typed capture that already contains a time is only a suggestion: the
  /// bar must not write the raw sentence before the user has seen it. Returning
  /// true means the suggestion was saved, so the bar clears itself.
  final Future<bool> Function(String draft)? onParsedSubmit;

  @override
  State<A2CaptureBar> createState() => A2CaptureBarState();
}

class A2CaptureBarState extends State<A2CaptureBar> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController(text: widget.initialDraft);
    _controller.addListener(_onTextChanged);
    _focus.addListener(_onFocus);
  }

  void _onTextChanged() {
    widget.onDraftChanged?.call(_controller.text);
  }

  void _onFocus() {
    if (mounted) setState(() {});
    widget.onFocusChange?.call(_focus.hasFocus);
  }

  @override
  void didUpdateWidget(covariant A2CaptureBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        widget.initialDraft != null &&
        widget.initialDraft != oldWidget.initialDraft &&
        widget.initialDraft != _controller.text) {
      _controller.text = widget.initialDraft!;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _controller.removeListener(_onTextChanged);
    _focus.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (widget.onExpand != null) {
        widget.onExpand!();
      }
      return;
    }
    final parsed = parseCapture(text, DateTime.now());
    if (parsed.start != null) {
      final handler = widget.onParsedSubmit;
      if (handler != null) {
        try {
          final saved = await handler(text);
          if (!mounted) return;
          if (saved) {
            _clearDraft();
          } else {
            _focus.requestFocus();
            setState(() {});
          }
        } catch (_) {
          if (!mounted) return;
          _restoreDraft(text);
        }
        return;
      }
      // No surface to review the suggestion yet: reveal one instead of
      // writing the sentence as a bare title with the time still inside it.
      if (widget.onExpand != null) {
        widget.onExpand!();
        _focus.requestFocus();
        return;
      }
    }
    try {
      await widget.onSubmit(parsed.start != null ? parsed.title : text);
      if (!mounted) return;
      _clearDraft();
      _focus.requestFocus();
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _restoreDraft(text);
    }
  }

  void _clearDraft() {
    _controller.clear();
    widget.onDraftChanged?.call('');
  }

  void _restoreDraft(String text) {
    if (_controller.text != text) {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    }
    _focus.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = _focus.hasFocus;
    final l = AppLocalizations.of(context);
    final typeText =
        widget.typeLabel ??
        (widget.isEvent
            ? (l?.eventLabel ?? 'Event')
            : (l?.captureTypeTodo ?? 'Task'));
    final subText =
        widget.contextLabel ??
        (l?.captureDefaultDate ?? 'No date · Personal');
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;
        final hasScope = context.getElementForInheritedWidgetOfExactType<UncontrolledProviderScope>() != null;
        if (hasScope && widget.isShifted == null) {
          return Consumer(
            builder: (context, ref, _) {
              final sel = ref.watch(workspaceSelectionProvider);
              final shifted = sel != null && isMasterDetailLayout(context);
              return _buildBar(context, active, isNarrow, shifted, typeText, subText);
            },
          );
        }
        return _buildBar(context, active, isNarrow, widget.isShifted ?? false, typeText, subText);
      },
    );
  }

  Widget _buildBar(
    BuildContext context,
    bool active,
    bool isNarrow,
    bool shifted,
    String typeText,
    String subText,
  ) {
    final barHeight = isNarrow ? 48.0 : 54.0;
    final barRadius = isNarrow ? 24.0 : 27.0;
    final sendSize = isNarrow ? 32.0 : 34.0;
    final sendIconSize = isNarrow ? 14.0 : 15.0;

    final sendButton = Container(
      key: const ValueKey('capture-send-visual'),
      width: sendSize,
      height: sendSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: SpecTokens.ink,
      ),
      child: Icon(
        CupertinoIcons.plus,
        size: sendIconSize,
        color: Colors.white,
      ),
    );

    final row = Row(
      children: [
        Container(
          height: isNarrow ? 23 : 25,
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 7 : 8),
          decoration: BoxDecoration(
            color: SpecTokens.wash,
            borderRadius: BorderRadius.circular(isNarrow ? 4 : 5),
            border: Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isEvent
                    ? CupertinoIcons.calendar
                    : CupertinoIcons.checkmark,
                size: isNarrow ? 9 : 10,
                color: SpecTokens.muted,
              ),
              const SizedBox(width: 4),
              Text(
                typeText,
                style: TextStyle(
                  fontSize: isNarrow ? 9 : 10,
                  fontWeight: FontWeight.w500,
                  color: SpecTokens.ink2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            subText,
            style: TextStyle(
              fontSize: isNarrow ? 9 : 10,
              color: SpecTokens.faint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: widget.fieldKey,
            controller: _controller,
            focusNode: _focus,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            cursorColor: SpecTokens.ink,
            style: _t(
              isNarrow ? 12.5 : 13.5,
              FontWeight.w400,
              active ? SpecTokens.ink : SpecTokens.muted,
              height: 1.4,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: widget.placeholder,
              hintStyle: _t(
                isNarrow ? 12.5 : 13.5,
                FontWeight.w400,
                const Color(0xFF8E8E84),
                height: 1.4,
              ),
            ),
          ),
        ),
        if (widget.hint.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            widget.hint,
            style: _t(11, FontWeight.w400, SpecTokens.faint).copyWith(
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ] else if (!isNarrow) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF7),
              border: Border.all(color: SpecTokens.hair2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              '↵',
              style: TextStyle(
                fontSize: 9,
                color: SpecTokens.faint,
                height: 1.3,
              ),
            ),
          ),
        ],
        const SizedBox(width: 6),
        isNarrow
            ? sendButton
            : FocusableTap(
                key: const ValueKey('capture-send-target'),
                onTap: () => widget.onExpand?.call(),
                semanticsLabel: widget.placeholder,
                borderRadius: BorderRadius.circular(sendSize / 2),
                child: sendButton,
              ),
      ],
    );

    Widget bar = Container(
      height: barHeight,
      margin: isNarrow
          ? const EdgeInsets.fromLTRB(12, 4, 12, 8)
          : const EdgeInsets.fromLTRB(12, 0, 12, 18),
      decoration: BoxDecoration(
        color: SpecTokens.paper,
        border: Border.all(
          color: active ? const Color(0xFFBDBDB5) : const Color(0xFFE1E1D9),
        ),
        borderRadius: BorderRadius.circular(barRadius),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: Color(0x0A191918),
                  blurRadius: 3,
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: Color(0x14191918),
                  blurRadius: 28,
                  offset: Offset(0, 8),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x14191918),
                  blurRadius: 28,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: isNarrow
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 7, 0),
                  child: row,
                ),
                Positioned(
                  right: 0,
                  top: -1,
                  height: 48,
                  width: 48,
                  child: FocusableTap(
                    key: const ValueKey('capture-send-target'),
                    onTap: () => widget.onExpand?.call(),
                    semanticsLabel: widget.placeholder,
                    borderRadius: BorderRadius.circular(24),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
              child: row,
            ),
    );

    final desktopBar = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: bar,
      ),
    );

    if (shifted && !isNarrow) {
      return Transform.translate(
        offset: const Offset(-190, 0),
        child: desktopBar,
      );
    }
    return isNarrow ? bar : desktopBar;
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 76),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? CupertinoIcons.tray,
              size: 27,
              color: const Color(0xFFB5B5AB),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: _t(15, FontWeight.w600, ds.ink),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: _t(11.5, FontWeight.w400, ds.ink3, height: 1.4),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 13),
              action!,
            ],
          ],
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
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final part in meta)
                      if (A2MetaLine.shrinks(part))
                        Flexible(fit: FlexFit.loose, child: part)
                      else
                        part,
                  ],
                ),
              ),
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
    return FocusableTap(
      onTap: onTap,
      semanticsLabel: title,
      borderRadius: BorderRadius.circular(kA2BlockRadius),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
        if (timeColumn > 0)
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

/// A keyboard-accessible focusable wrapper that triggers [onTap] on Enter or Space.
class FocusableTap extends StatefulWidget {
  const FocusableTap({
    super.key,
    required this.child,
    this.onTap,
    this.semanticsLabel,
    this.focusNode,
    this.borderRadius,
    this.focusRing = const BorderSide(color: SpecTokens.ink, width: 2),
    this.pointerEnabled = true,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final FocusNode? focusNode;
  final BorderRadius? borderRadius;

  /// Drawn inside a two-pixel border while the control holds focus. Pass
  /// [BorderSide.none] where the cell already paints its own focus.
  final BorderSide focusRing;

  /// False leaves an ancestor's pointer recognizer in charge: the control
  /// only adds a tab stop, its focus ring, and Enter/Space activation.
  final bool pointerEnabled;

  /// Marks a toggle-style control as selected on its semantic node.
  final bool? selected;

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final content = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: enabled,
        skipTraversal: !enabled,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (!enabled) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          foregroundDecoration: _focused && widget.focusRing.width > 0
              ? BoxDecoration(
                  borderRadius:
                      widget.borderRadius ?? BorderRadius.circular(4),
                  border: Border.fromBorderSide(widget.focusRing),
                )
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.pointerEnabled ? widget.onTap : null,
            child: widget.child,
          ),
        ),
      ),
    );
    final label = widget.semanticsLabel;
    if (label == null) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        selected: widget.selected,
        child: content,
      );
    }
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      container: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: content,
    );
  }
}

class A2CaptureCalendarChoice {
  const A2CaptureCalendarChoice({
    required this.id,
    required this.name,
    required this.color,
  });

  final int id;
  final String name;
  final Color color;
}

/// The desktop capture panel's pending facts. Empty means the capture writes a
/// bare todo: no deadline, no plan, no reminder, the default calendar.
class A2CaptureDraft {
  const A2CaptureDraft({
    this.dueDate,
    this.calendarId,
    this.reminderOffset,
    this.planStart,
    this.planEnd,
    this.rrule,
  });

  final DateTime? dueDate;
  final int? calendarId;
  final Duration? reminderOffset;
  final DateTime? planStart;
  final DateTime? planEnd;

  /// Only the event capture path reads this; a todo's plan never carries a
  /// recurrence and the draft keeps the two facts apart.
  final String? rrule;

  bool get isEmpty =>
      dueDate == null &&
      calendarId == null &&
      reminderOffset == null &&
      planStart == null &&
      planEnd == null &&
      rrule == null;

  A2CaptureDraft withDueDate(DateTime? value) {
    return A2CaptureDraft(
      dueDate: value,
      calendarId: calendarId,
      reminderOffset: reminderOffset,
      planStart: planStart,
      planEnd: planEnd,
      rrule: rrule,
    );
  }

  A2CaptureDraft withCalendarId(int? value) {
    return A2CaptureDraft(
      dueDate: dueDate,
      calendarId: value,
      reminderOffset: reminderOffset,
      planStart: planStart,
      planEnd: planEnd,
      rrule: rrule,
    );
  }

  A2CaptureDraft withReminderOffset(Duration? value) {
    return A2CaptureDraft(
      dueDate: dueDate,
      calendarId: calendarId,
      reminderOffset: value,
      planStart: planStart,
      planEnd: planEnd,
      rrule: rrule,
    );
  }

  A2CaptureDraft withPlan(DateTime? start, DateTime? end) {
    return A2CaptureDraft(
      dueDate: dueDate,
      calendarId: calendarId,
      reminderOffset: reminderOffset,
      planStart: start,
      planEnd: end,
      rrule: rrule,
    );
  }

  A2CaptureDraft withRrule(String? value) {
    return A2CaptureDraft(
      dueDate: dueDate,
      calendarId: calendarId,
      reminderOffset: reminderOffset,
      planStart: planStart,
      planEnd: planEnd,
      rrule: value,
    );
  }
}

/// One block already on the plan date, reduced to what the capture panel's
/// "当天已有" line needs to print.
class A2CaptureDayBlock {
  const A2CaptureDayBlock({
    required this.start,
    required this.end,
    required this.title,
  });

  final DateTime start;
  final DateTime end;
  final String title;
}

DateTime _captureDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameCaptureDay(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _nextCaptureMonday(DateTime from) {
  final days = (DateTime.monday - from.weekday + 7) % 7;
  return from.add(Duration(days: days == 0 ? 7 : days));
}

String _captureClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// The 12 surface states of the A″ capture panel according to spec HTML 1878-2000 & 2308-2333.
enum A2CaptureState {
  compact,
  parsed,
  expanded,
  event,
  date,
  plan,
  calendar,
  reminder,
  validation,
  saveError,
  discard,
  keyboard,
}

/// A non-modal desktop panel (width: 620) anchored above [A2CaptureBar], or a mobile bottom sheet.
class A2CapturePanel extends StatelessWidget {
  const A2CapturePanel({
    super.key,
    required this.state,
    required this.titleController,
    this.onStateChanged,
    this.dueDate,
    this.planStart,
    this.planEnd,
    this.calendarName,
    this.calendarColor,
    this.reminderLabel,
    this.calendarChoices = const <A2CaptureCalendarChoice>[],
    this.planDayBlocks = const <A2CaptureDayBlock>[],
    this.suggestionLabel,
    this.selectedCalendarId,
    this.selectedReminderOffset,
    this.onChooseDueDate,
    this.onChooseCalendar,
    this.onChooseReminder,
    this.onPickCustomDate,
    this.onPickPlanDate,
    this.onPickPlanStart,
    this.onPickPlanEnd,
    this.onApplyChoice,
    this.onCancelChoice,
    this.priority = 0,
    this.isEvent = false,
    this.suggestionRemoved = false,
    this.onToggleSuggestion,
    this.onSubmit,
    this.onSubmitLater,
    this.onDiscard,
    this.onCancel,
    this.onPickDate,
    this.onPickPlan,
    this.onPickCalendar,
    this.onPickReminder,
    this.onCyclePriority,
    this.onSwitchToEvent,
    this.onSwitchToTodo,
    this.onCycleEventRepeat,
    this.eventRepeat,
  });

  final A2CaptureState state;
  final TextEditingController titleController;
  final ValueChanged<A2CaptureState>? onStateChanged;
  final DateTime? dueDate;
  final DateTime? planStart;
  final DateTime? planEnd;
  final String? calendarName;
  final Color? calendarColor;
  final String? reminderLabel;
  final List<A2CaptureCalendarChoice> calendarChoices;
  final List<A2CaptureDayBlock> planDayBlocks;
  final String? suggestionLabel;
  final int? selectedCalendarId;
  final Duration? selectedReminderOffset;
  final ValueChanged<DateTime?>? onChooseDueDate;
  final ValueChanged<int?>? onChooseCalendar;
  final ValueChanged<Duration?>? onChooseReminder;
  final VoidCallback? onPickCustomDate;
  final VoidCallback? onPickPlanDate;
  final VoidCallback? onPickPlanStart;
  final VoidCallback? onPickPlanEnd;
  final VoidCallback? onApplyChoice;
  final VoidCallback? onCancelChoice;
  final int priority;
  final bool isEvent;
  final bool suggestionRemoved;
  final VoidCallback? onToggleSuggestion;
  final VoidCallback? onSubmit;
  final VoidCallback? onSubmitLater;
  final VoidCallback? onDiscard;
  final VoidCallback? onCancel;
  final VoidCallback? onPickDate;
  final VoidCallback? onPickPlan;
  final VoidCallback? onPickCalendar;
  final VoidCallback? onPickReminder;
  final VoidCallback? onCyclePriority;
  final VoidCallback? onSwitchToEvent;
  final VoidCallback? onSwitchToTodo;
  final VoidCallback? onCycleEventRepeat;

  /// The event's current recurrence rule, so the read row and the cycle action
  /// cannot disagree about what is selected.
  final String? eventRepeat;

  @override
  Widget build(BuildContext context) {
    if (state == A2CaptureState.compact) {
      return const SizedBox.shrink();
    }
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (state == A2CaptureState.saveError) {
            onStateChanged?.call(A2CaptureState.discard);
          } else {
            onCancel?.call();
            onStateChanged?.call(A2CaptureState.compact);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: isDesktop ? 620 : double.infinity,
        margin: isDesktop
            ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
            : const EdgeInsets.fromLTRB(8, 0, 8, 4),
        decoration: BoxDecoration(
          color: SpecTokens.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SpecTokens.hair),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(24, 24, 22, 0.10),
              blurRadius: 40,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHead(context),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: _buildBody(context),
              ),
              _buildFoot(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHead(BuildContext context) {
    final l = AppLocalizations.of(context);
    String title;
    String sub;
    switch (state) {
      case A2CaptureState.parsed:
        title = titleController.text.isNotEmpty
            ? titleController.text
            : (l?.captureParsedDefaultTitle ?? 'Submit report at 3pm tomorrow');
        sub = l?.captureParsedDefaultSub ?? 'Task · No date · Personal (default)';
      case A2CaptureState.expanded:
        title = l?.captureTitle ?? 'Record a task';
        sub = l?.captureSubExpanded ?? 'Expand when needed; no date by default.';
      case A2CaptureState.event:
        title = l?.captureTitleEvent ?? 'New Event';
        sub = calendarName == null
            ? (l?.captureSubEvent ?? 'Event')
            : '${l?.eventLabel ?? 'Event'} · $calendarName';
      case A2CaptureState.date:
        title = l?.captureChoiceTitleDate ?? 'Select Date';
        sub = l?.captureSubDate ?? 'Task · Personal (default)';
      case A2CaptureState.plan:
        title = isEvent
            ? (l?.pickTimeTitle ?? 'Choose a time')
            : (l?.captureChoiceTitlePlan ?? 'Select Planned Execution');
        sub = isEvent
            ? (calendarName == null
                  ? (l?.eventLabel ?? 'Event')
                  : '${l?.eventLabel ?? 'Event'} · $calendarName')
            : (l?.captureSubPlan ?? 'Sets plan only, does not change deadline.');
      case A2CaptureState.calendar:
        title = l?.captureChoiceTitleCalendar ?? 'Select Calendar';
        sub = l?.captureHintCalendar ?? 'Default calendar comes from settings; no "uncategorized".';
      case A2CaptureState.reminder:
        title = l?.captureChoiceTitleReminder ?? 'Reminder';
        sub = l?.captureSubReminder ?? 'Reminder belongs to item, does not change deadline.';
      case A2CaptureState.validation:
        title = l?.captureTitle ?? 'Record a task';
        sub = l?.captureSubDate ?? 'Task · Personal (default)';
      case A2CaptureState.saveError:
        title = l?.captureSaveErrorTitle ?? 'Save Failed';
        sub = l?.captureSaveErrorSub ?? 'Draft preserved, will not be lost';
      case A2CaptureState.discard:
        title = l?.captureDiscardTitle ?? 'Discard this input?';
        sub = l?.captureDiscardSub(titleController.text.trim()) ??
            '"${titleController.text.trim()}" not saved';
      case A2CaptureState.keyboard:
        title = l?.captureKeyboardTitle ?? 'Keyboard navigation';
        sub = l?.captureKeyboardSub ?? 'Desktop: Tab fields · Enter save · Esc discard';
      case A2CaptureState.compact:
        title = '';
        sub = '';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpecTokens.hair)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SpecTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpecTokens.faint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.xmark, size: 13, color: SpecTokens.muted),
            tooltip: l?.closeTooltip ?? 'Close',
            onPressed: () {
              if (state == A2CaptureState.saveError) {
                onStateChanged?.call(A2CaptureState.discard);
              } else {
                onCancel?.call();
                onStateChanged?.call(A2CaptureState.compact);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l = AppLocalizations.of(context);
    switch (state) {
      case A2CaptureState.validation:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SpecTokens.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l?.captureFieldEventTitle ?? 'Title', style: const TextStyle(fontSize: 11, color: SpecTokens.muted)),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                      hintText: l?.titleRequired ?? 'Title required',
                    ),
                  ),
                  Text(
                    l?.captureValidationEmptyTitle ?? 'Title cannot be empty. Write an action you will understand tomorrow.',
                    style: const TextStyle(fontSize: 11, color: SpecTokens.red),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SpecTokens.redSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l?.captureValidationAlert ?? 'Fill title before saving; other fields are preserved.',
                style: const TextStyle(fontSize: 12, color: SpecTokens.red),
              ),
            ),
          ],
        );

      case A2CaptureState.saveError:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SpecTokens.redSoft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l?.captureSaveErrorServer ?? 'Could not connect to server.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SpecTokens.red),
              ),
              const SizedBox(height: 4),
              Text(
                l?.captureSaveErrorDraftHint(titleController.text.trim()) ??
                    '"${titleController.text.trim()}" is still in this draft; you can retry or keep it in Unplanned.',
                style: const TextStyle(fontSize: 12, color: SpecTokens.ink2),
              ),
            ],
          ),
        );

      case A2CaptureState.discard:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SpecTokens.wash,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l?.captureDiscardLineTitle ?? 'Draft will be lost on close',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SpecTokens.ink),
              ),
              const SizedBox(height: 4),
              Text(
                l?.captureDiscardLineSub ?? 'Keep editing will preserve title, date and reminders.',
                style: const TextStyle(fontSize: 12, color: SpecTokens.muted),
              ),
            ],
          ),
        );

      case A2CaptureState.parsed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.calendar, size: 14, color: SpecTokens.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l?.captureParsedTypeTodoTitle ?? 'Type remains Task', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(l?.captureParsedTypeTodoSub ?? 'Detected time is only a "Planned execution" suggestion, not an event or deadline.',
                          style: const TextStyle(fontSize: 11, color: SpecTokens.faint)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SpecTokens.wash,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.clock, size: 14, color: SpecTokens.work),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestionRemoved
                              ? (l?.captureParsedSuggestRemoved ?? 'Time suggestion removed')
                              : (suggestionLabel ??
                                    l?.captureParsedSuggestTitle ??
                                    'Suggested Plan'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          suggestionRemoved
                              ? (l?.captureParsedSuggestSubRemoved ?? 'Saves title only; no date, no plan, no deadline.')
                              : (l?.captureParsedSuggestSub ?? 'Preselected; saved as "Planned execution". Can be removed.'),
                          style: const TextStyle(fontSize: 11, color: SpecTokens.muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleSuggestion,
                    child: Text(
                      suggestionRemoved
                          ? (l?.captureActionRestore ?? 'Restore')
                          : (l?.captureActionRemove ?? 'Remove'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: onSwitchToEvent,
                    child: Text(l?.captureActionChangeToEvent ?? 'Change to Event', style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        );

      case A2CaptureState.event:
        final timeStr = planStart == null
            ? (l?.captureFieldNotFilled ?? 'Not filled')
            : '${planStart!.month}/${planStart!.day} ${_captureClock(planStart!)}'
                  '–${planEnd != null ? _captureClock(planEnd!) : ""}';
        return Column(
          children: [
            _fieldRow(l?.captureFieldEventTitle ?? 'Title', titleController.text.isNotEmpty ? titleController.text : (l?.captureFieldNotFilled ?? 'Not filled'), onTap: null),
            _fieldRow(l?.captureFieldEventTime ?? 'Time', timeStr, onTap: onPickPlan),
            _fieldRow(l?.captureFieldEventAllDay ?? 'All-day', l?.captureFieldNo ?? 'No', onTap: null),
            _fieldRow(l?.captureFieldCalendar ?? 'Calendar', calendarName ?? (l?.captureCalWork ?? 'Work'), dotColor: calendarColor ?? SpecTokens.work, onTap: onPickCalendar),
            _fieldRow(l?.captureFieldEventRepeat ?? 'Repeat', _repeatLabel(l), onTap: onCycleEventRepeat),
            _fieldRow(l?.captureFieldReminder ?? 'Reminder', reminderLabel ?? (l?.captureFieldNoReminder ?? 'No reminder'), onTap: onPickReminder),
          ],
        );

      case A2CaptureState.date:
        final today = _captureDay(DateTime.now());
        final tomorrow = today.add(const Duration(days: 1));
        final nextMonday = _nextCaptureMonday(today);
        final custom = dueDate == null ? null : _captureDay(dueDate!);
        final customSelected =
            custom != null &&
            !_sameCaptureDay(custom, today) &&
            !_sameCaptureDay(custom, tomorrow) &&
            !_sameCaptureDay(custom, nextMonday);
        return Column(
          children: [
            _choiceRow(
              l?.captureFieldDateToday ?? 'Today',
              '${today.month}/${today.day}',
              isSelected: _sameCaptureDay(custom, today),
              selectedLabel: l?.captureSelectedTag ?? 'Selected',
              onTap: () {
                onChooseDueDate?.call(today);
                onStateChanged?.call(A2CaptureState.expanded);
              },
            ),
            _choiceRow(
              l?.captureFieldDateTomorrow ?? 'Tomorrow',
              '${tomorrow.month}/${tomorrow.day}',
              isSelected: _sameCaptureDay(custom, tomorrow),
              selectedLabel: l?.captureSelectedTag ?? 'Selected',
              onTap: () {
                onChooseDueDate?.call(tomorrow);
                onStateChanged?.call(A2CaptureState.expanded);
              },
            ),
            _choiceRow(
              l?.captureFieldDateNextMonday ?? 'Next Monday',
              '${nextMonday.month}/${nextMonday.day}',
              isSelected: _sameCaptureDay(custom, nextMonday),
              selectedLabel: l?.captureSelectedTag ?? 'Selected',
              onTap: () {
                onChooseDueDate?.call(nextMonday);
                onStateChanged?.call(A2CaptureState.expanded);
              },
            ),
            _choiceRow(
              l?.captureFieldDateOther ?? 'Other date',
              customSelected
                  ? '${custom.month}/${custom.day}'
                  : (l?.captureFieldDateOpenCalendar ?? 'Open calendar'),
              isSelected: customSelected,
              selectedLabel: l?.captureSelectedTag ?? 'Selected',
              onTap: onPickCustomDate ??
                  () => onStateChanged?.call(A2CaptureState.expanded),
            ),
          ],
        );

      case A2CaptureState.plan:
        final startStr = planStart != null ? _captureClock(planStart!) : '15:15';
        final endStr = planEnd != null ? _captureClock(planEnd!) : '16:00';
        final duration = planStart != null && planEnd != null
            ? planEnd!.difference(planStart!).inMinutes
            : 45;
        return Column(
          children: [
            _fieldRow(
              l?.dueDate ?? 'Date',
              planStart != null
                  ? '${planStart!.month}/${planStart!.day}'
                  : (l?.captureFieldDateToday ?? 'Today'),
              onTap: onPickPlanDate,
            ),
            _fieldRow(l?.planStartTime ?? 'Start', startStr, onTap: onPickPlanStart),
            _fieldRow(l?.planEndTime ?? 'End', endStr, onTap: onPickPlanEnd),
            _fieldRow(
              l?.captureFieldDuration ?? 'Duration',
              l?.planDurationMinutes(duration) ?? '$duration minutes',
              onTap: null,
            ),
            _fieldRow(
              l?.captureFieldDayExisting ?? 'Schedule on day',
              _planDayLabel(l),
              onTap: null,
            ),
          ],
        );

      case A2CaptureState.calendar:
        return Column(
          children: [
            for (final choice in calendarChoices)
              _choiceRow(
                choice.name,
                '',
                dotColor: choice.color,
                isSelected: choice.id == selectedCalendarId,
                selectedLabel: l?.captureSelectedTag ?? 'Selected',
                onTap: () {
                  onChooseCalendar?.call(choice.id);
                  onStateChanged?.call(A2CaptureState.expanded);
                },
              ),
          ],
        );

      case A2CaptureState.reminder:
        const options = <Duration?>[
          null,
          Duration(minutes: 5),
          Duration(minutes: 15),
          Duration(hours: 1),
          Duration(days: 1),
        ];
        final labels = <String?>[
          l?.captureReminderNoReminder ?? 'No reminder',
          l?.captureReminder5mBefore ?? '5 minutes before',
          l?.captureReminder15mBefore ?? '15 minutes before',
          l?.captureReminder1hBefore ?? '1 hour before',
          l?.captureReminder1dBefore ?? '1 day before',
        ];
        return Column(
          children: [
            for (var index = 0; index < options.length; index++)
              _choiceRow(
                labels[index] ?? '',
                '',
                isSelected: selectedReminderOffset == options[index],
                selectedLabel: l?.captureSelectedTag ?? 'Selected',
                onTap: () {
                  onChooseReminder?.call(options[index]);
                  onStateChanged?.call(A2CaptureState.expanded);
                },
              ),
          ],
        );

      case A2CaptureState.keyboard:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SpecTokens.ink),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(25, 25, 24, 0.10),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l?.captureFieldEventTitle ?? 'Title', style: const TextStyle(fontSize: 11, color: SpecTokens.muted)),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                    ),
                  ),
                  Text(
                    l?.captureKeyboardHelp ?? 'Focus on title; Tab to deadline, plan, reminder.',
                    style: const TextStyle(fontSize: 11, color: SpecTokens.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _fieldRow(l?.captureFieldDeadline ?? 'Deadline', dueDate != null ? '${dueDate!.month}/${dueDate!.day}' : (l?.captureFieldNoDeadline ?? 'No deadline'), onTap: onPickDate),
            _fieldRow(l?.captureFieldPlanExecution ?? 'Planned execution', planStart != null ? '${_captureClock(planStart!)}${planEnd != null ? '–${_captureClock(planEnd!)}' : ''}' : (l?.captureFieldNotScheduled ?? 'Not scheduled'), onTap: onPickPlan),
          ],
        );

      case A2CaptureState.expanded:
      default:
        return Column(
          children: [
            _fieldRow(l?.captureFieldTaskTitle ?? 'Task Title', titleController.text.isNotEmpty ? titleController.text : (l?.captureFieldNotFilled ?? 'Not filled'), onTap: null),
            _fieldRow(
              l?.captureFieldDeadline ?? 'Deadline',
              dueDate != null ? '${dueDate!.month}/${dueDate!.day}' : (l?.captureFieldNoDeadline ?? 'No deadline'),
              isHighlight: dueDate != null,
              onTap: onPickDate,
            ),
            _fieldRow(
              l?.captureFieldPlanExecution ?? 'Planned execution',
              planStart != null
                  ? '${planStart!.month}/${planStart!.day} ${_captureClock(planStart!)}${planEnd != null ? '–${_captureClock(planEnd!)}' : ''}'
                  : (l?.captureFieldNotScheduled ?? 'Not scheduled'),
              isHighlight: planStart != null,
              onTap: onPickPlan,
            ),
            _fieldRow(l?.captureFieldReminder ?? 'Reminder', reminderLabel ?? (l?.captureFieldNoReminder ?? 'No reminder'), onTap: onPickReminder),
            _fieldRow(l?.captureFieldCalendar ?? 'Calendar', calendarName ?? (l?.captureCalPersonalDefault ?? 'Personal · Default'), dotColor: calendarColor ?? SpecTokens.scheduleBlue, onTap: onPickCalendar),
            _fieldRow(
              l?.captureFieldPriority ?? 'Priority',
              priority > 0
                  ? (priority <= 1 ? (l?.captureFieldHigh ?? 'High') : (l?.captureFieldMedium ?? 'Medium'))
                  : (l?.captureFieldNone ?? 'None'),
              onTap: onCyclePriority,
            ),
          ],
        );
    }
  }

  String _repeatLabel(AppLocalizations? l) {
    final value = eventRepeat;
    if (value == null || value.isEmpty) {
      return l?.captureFieldNoRepeat ?? 'Does not repeat';
    }
    if (value.startsWith('FREQ=DAILY')) return l?.repeatDaily ?? 'Every day';
    if (value.startsWith('FREQ=WEEKLY')) return l?.repeatWeekly ?? 'Every week';
    if (value.startsWith('FREQ=MONTHLY')) {
      return l?.repeatMonthly ?? 'Every month';
    }
    return value;
  }

  String _planDayLabel(AppLocalizations? l) {
    if (planDayBlocks.isEmpty) {
      return l?.capturePlanDayEmpty ?? 'Nothing scheduled that day';
    }
    final parts = planDayBlocks
        .take(3)
        .map((block) => '${_captureClock(block.start)} ${block.title}')
        .join(' · ');
    final start = planStart;
    final end = planEnd;
    if (start == null || end == null) return parts;
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    final overlaps = planDayBlocks.where((block) {
      final blockStart = block.start.hour * 60 + block.start.minute;
      final blockEnd = block.end.hour * 60 + block.end.minute;
      return blockStart < endMinute && blockEnd > startMinute;
    }).length;
    if (overlaps == 0) return parts;
    return '$parts · ${l?.capturePlanOverlapCount(overlaps) ?? '$overlaps overlapping'}';
  }

  Widget _choiceRow(String label, String value, {bool isSelected = false, String? selectedLabel, Color? dotColor, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null) ...[
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                ],
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SpecTokens.ink)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: const TextStyle(fontSize: 11, color: SpecTokens.faint)),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: SpecTokens.ink,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(selectedLabel ?? 'Selected', style: const TextStyle(fontSize: 9, color: Colors.white)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(String label, String value, {bool isHighlight = false, Color? dotColor, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: SpecTokens.muted)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null) ...[
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                ],
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w400,
                    color: isHighlight ? SpecTokens.work : SpecTokens.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoot(BuildContext context) {
    final l = AppLocalizations.of(context);
    String hintText;
    var actionButtons = <Widget>[];

    switch (state) {
      case A2CaptureState.event:
        hintText = l?.captureHintEvent ?? 'Only explicit switch to "Event" or entering from Calendar slot creates an event.';
        actionButtons = [
          TextButton(
            onPressed: onSwitchToTodo ?? () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.captureActionChangeToTodo ?? 'Change to Task'),
          ),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionCreateEvent ?? 'Create Event', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.date:
        hintText = l?.captureHintDate ?? 'Writes date only, not time; will not become an event.';
        actionButtons = [
          TextButton(
            onPressed: onCancelChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.cancelAction ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: onApplyChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionApply ?? 'Apply', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.plan:
        hintText = l?.captureHintPlan ?? 'Overlaps allowed; will not modify deadline.';
        actionButtons = [
          TextButton(
            onPressed: onCancelChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.cancelAction ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: onApplyChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionApply ?? 'Apply', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.calendar:
        hintText = l?.captureHintCalendar ?? 'Default calendar comes from settings; no "uncategorized".';
        actionButtons = [
          TextButton(
            onPressed: onCancelChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.cancelAction ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: onApplyChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionApply ?? 'Apply', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.reminder:
        hintText = l?.captureHintReminder ?? 'Reminder is the item\'s own fact, does not affect deadline.';
        actionButtons = [
          TextButton(
            onPressed: onCancelChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.cancelAction ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: onApplyChoice ??
                () => onStateChanged?.call(A2CaptureState.expanded),
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionApply ?? 'Apply', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.keyboard:
        hintText = l?.captureHintKeyboard ?? 'Focus visible; Esc triggers discard confirmation.';
        actionButtons = [
          TextButton(
            onPressed: () => onStateChanged?.call(A2CaptureState.discard),
            child: const Text('Esc'),
          ),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionEnterSave ?? 'Enter to save', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.validation:
        hintText = l?.captureHintValidation ?? 'Validation error stays on field, no global popup.';
        actionButtons = [
          TextButton(
            onPressed: () {
              onCancel?.call();
              onStateChanged?.call(A2CaptureState.compact);
            },
            child: Text(l?.cancelAction ?? 'Cancel', style: const TextStyle(color: SpecTokens.muted)),
          ),
          ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: SpecTokens.ink,
              disabledBackgroundColor: SpecTokens.hair2,
            ),
            child: Text(l?.captureSaveTodo ?? 'Record Task', style: const TextStyle(color: Colors.white70)),
          ),
        ];

      case A2CaptureState.saveError:
        hintText = l?.captureHintSaveError ?? 'Failure state does not close Capture or drop input.';
        actionButtons = [
          OutlinedButton(
            onPressed: onSubmitLater,
            child: Text(l?.captureActionSaveLater ?? 'Save to Unplanned first'),
          ),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureActionRetry ?? 'Retry', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.discard:
        hintText = l?.captureHintDiscard ?? 'Dangerous actions require confirmation.';
        actionButtons = [
          TextButton(
            onPressed: () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.captureActionKeepEditing ?? 'Keep editing'),
          ),
          TextButton(
            onPressed: () {
              onDiscard?.call();
              onStateChanged?.call(A2CaptureState.compact);
            },
            child: Text(l?.captureActionDiscard ?? 'Discard', style: const TextStyle(color: SpecTokens.red)),
          ),
        ];

      case A2CaptureState.parsed:
        hintText = l?.captureHintParsed ?? 'Default: Task · No date · Personal\nDeadline remains empty';
        actionButtons = [
          TextButton(
            onPressed: () => onStateChanged?.call(A2CaptureState.expanded),
            child: Text(l?.captureActionExpandFields ?? 'Expand fields'),
          ),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureSaveTodo ?? 'Record Task', style: const TextStyle(color: Colors.white)),
          ),
        ];

      case A2CaptureState.expanded:
      default:
        hintText = l?.captureHintExpanded ?? 'All facts visible before saving; untouched fields are not written.';
        actionButtons = [
          TextButton(
            onPressed: () {
              onCancel?.call();
              onStateChanged?.call(A2CaptureState.compact);
            },
            child: Text(l?.captureActionBackToCompact ?? 'Back to compact'),
          ),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(backgroundColor: SpecTokens.ink),
            child: Text(l?.captureSaveTodo ?? 'Record Task', style: const TextStyle(color: Colors.white)),
          ),
        ];
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SpecTokens.hair)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              hintText,
              style: const TextStyle(fontSize: 10, color: SpecTokens.faint),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: actionButtons),
        ],
      ),
    );
  }
}

