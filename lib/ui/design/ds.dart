import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// v030 presentation primitives.
///
/// Every page is assembled from these, not from Material defaults: the design
/// is a quiet paper surface with hairlines, 8px controls and one accent. Keeping
/// the shapes here is what stops the next page from drifting back to cards,
/// rounded pills and coloured status dots.

// ---------------------------------------------------------------- top bar

/// Mobile top bar: 54px, optional back, 26/600 title, quiet actions.
class DsTopBar extends StatelessWidget implements PreferredSizeWidget {
  const DsTopBar({
    super.key,
    this.title = '',
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool showDivider;

  @override
  Size get preferredSize => const Size.fromHeight(54);

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    // Scaffold already reserves [preferredSize] plus the status bar for the
    // app bar slot, so the bar has to fill that slot rather than sit at its
    // top: a fixed 54 drew the title under the clock on a real phone.
    final inset = MediaQuery.paddingOf(context).top;
    return Container(
      height: 54 + inset,
      padding: EdgeInsets.only(
        top: inset,
        left: leading == null ? AppSpacing.s4 : AppSpacing.s1,
        right: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: ds.bg,
        border: showDivider
            ? Border(bottom: BorderSide(color: ds.lineSoft))
            : null,
      ),
      child: Row(
        children: [
          if (leading != null) leading!,
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.display.copyWith(
                      color: ds.ink,
                      height: 1.05,
                    ),
                  ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: ds.ink3,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Desktop main bar: 54px on the page ground, 18/600 title, context text.
class DsMainBar extends StatelessWidget {
  const DsMainBar({
    super.key,
    required this.title,
    this.contextLabel,
    this.actions = const [],
  });

  final String title;
  final String? contextLabel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(bottom: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.title.copyWith(color: ds.ink),
          ),
          if (contextLabel != null && contextLabel!.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.s2 + 2),
            Expanded(
              child: Text(
                contextLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.small.copyWith(color: ds.ink3),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: AppSpacing.s2),
          ...actions,
        ],
      ),
    );
  }
}

class DsIconButton extends StatelessWidget {
  const DsIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 20,
    this.selected = false,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool selected;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final side = compact ? 36.0 : 44.0;
    return Tooltip(
      message: tooltip ?? '',
      child: MouseRegion(
        cursor: onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: selected ? ds.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.sm + 1),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppRadii.sm + 1),
              child: SizedBox(
                width: side,
                height: side,
                child: Icon(
                  icon,
                  size: size,
                  color:
                      color ??
                      (selected ? ds.primary : ds.ink2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- buttons

enum DsButtonTone { primary, secondary, ghost, danger }

class DsButton extends StatelessWidget {
  const DsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = DsButtonTone.primary,
    this.icon,
    this.small = false,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final DsButtonTone tone;
  final IconData? icon;
  final bool small;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final (bg, fg, border) = switch (tone) {
      DsButtonTone.primary => (ds.primary, ds.onPrimary, Colors.transparent),
      DsButtonTone.secondary => (
        ds.surface,
        ds.ink,
        ds.line,
      ),
      DsButtonTone.ghost => (Colors.transparent, ds.primary, Colors.transparent),
      DsButtonTone.danger => (Colors.transparent, ds.danger, Colors.transparent),
    };
    final enabled = onPressed != null && !loading;
    final height = small ? 34.0 : 44.0;
    final radius = small ? AppRadii.sm : AppRadii.md;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: small ? 15 : 17, color: fg),
        if (icon != null || loading) const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (small ? AppTypography.caption : AppTypography.body)
                .copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(radius),
              child: Container(
                height: height,
                width: expand ? double.infinity : null,
                padding: EdgeInsets.symmetric(
                  horizontal: small ? AppSpacing.s3 : AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: border == Colors.transparent
                      ? null
                      : Border.all(color: border),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top-bar create action: accent text, no filled block.
class DsCreateAction extends StatelessWidget {
  const DsCreateAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.add, size: 17, color: ds.primary),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: AppTypography.bodyStrong.copyWith(
                      color: ds.primary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- chips

class DsChip extends StatelessWidget {
  const DsChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
    this.warm = false,
    this.danger = false,
    this.solid = false,
    this.leading,
    this.trailing,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool warm;
  final bool danger;
  final bool solid;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final bg = selected
        ? ds.primarySoft
        : warm
        ? ds.warnSoft
        : danger
        ? ds.dangerSoft
        : solid
        ? ds.surface2
        : ds.surface;
    final fg = selected
        ? ds.primary
        : warm
        ? ds.warn
        : danger
        ? ds.danger
        : ds.ink2;
    final border = selected || warm || danger || solid
        ? null
        : Border.all(color: ds.line);
    final body = Container(
      constraints: BoxConstraints(minHeight: compact ? 28 : 32),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 0,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.chip,
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: fg,
                fontSize: compact ? 12 : 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.chip,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.chip,
          child: body,
        ),
      ),
    );
  }
}

class DsDot extends StatelessWidget {
  const DsDot({super.key, required this.color, this.size = 6});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ---------------------------------------------------------------- segmented

class DsSegmentOption<T> {
  const DsSegmentOption(this.value, this.label);
  final T value;
  final String label;
}

class DsSegmented<T> extends StatelessWidget {
  const DsSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.expand = false,
    this.height = 32,
  });

  final List<DsSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final children = [
      for (final option in options)
        // A segment sizes to its label unless the caller asks it to split the
        // width evenly; a flex child would otherwise share the row's space and
        // clip short labels like "未安排" mid-word.
        if (expand)
          Expanded(child: _segment(context, ds, option))
        else
          _segment(context, ds, option),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ds.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _segment(BuildContext context, DsColors ds, DsSegmentOption<T> option) {
    final on = option.value == selected;
    return Semantics(
      button: true,
      selected: on,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(option.value),
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 12),
            decoration: BoxDecoration(
              color: on ? ds.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              boxShadow: on ? AppShadows.one : null,
            ),
            child: Text(
              option.label,
              maxLines: 1,
              style: AppTypography.caption.copyWith(
                color: on ? ds.ink : ds.ink2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- text

class DsSectionLabel extends StatelessWidget {
  const DsSectionLabel(
    this.label, {
    super.key,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s4,
      AppSpacing.s5 + 2,
      AppSpacing.s4,
      AppSpacing.s2,
    ),
  });

  final String label;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        label,
        style: AppTypography.overline.copyWith(
          color: color ?? context.ds.ink3,
        ),
      ),
    );
  }
}

/// A list group's band: a dot, the group name, and its count at the far edge.
///
/// Sits flush against the rows it introduces, so scanning a long backlog reads
/// as a few named stretches rather than one undifferentiated column.
class DsGroupHead extends StatelessWidget {
  const DsGroupHead(this.label, {super.key, this.count, this.danger = false});

  final String label;
  final int? count;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4 + 2),
      decoration: BoxDecoration(
        color: ds.bg,
        border: Border(top: BorderSide(color: ds.lineSoft)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger ? ds.danger : ds.faint,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppTypography.small.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: danger ? ds.danger : ds.ink3,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          if (count != null)
            Text(
              '$count',
              style: AppTypography.small.copyWith(
                fontSize: 11,
                color: ds.faint,
                fontFeatures: AppTypography.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- rows

class DsMeta extends StatelessWidget {
  const DsMeta({super.key, required this.parts, this.style});
  final List<DsMetaPart> parts;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Wrap(
      spacing: 0,
      runSpacing: 2,
      children: [
        for (var i = 0; i < parts.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: (style ?? AppTypography.small).copyWith(
                      color: ds.ink3,
                    ),
                  ),
                ),
              Flexible(
                child: Text(
                  parts[i].text,
                  style: (style ?? AppTypography.small).copyWith(
                    color: parts[i].color ?? ds.ink3,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class DsMetaPart {
  const DsMetaPart(this.text, {this.color});
  final String text;
  final Color? color;
}

/// A list row: optional leading, title + meta, optional trailing.
class DsRow extends StatelessWidget {
  const DsRow({
    super.key,
    required this.title,
    this.meta,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.done = false,
    this.dense = false,
    this.padding,
    this.titleStyle,
    this.background,
  });

  final String title;
  final Widget? meta;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool done;
  final bool dense;
  final EdgeInsetsGeometry? padding;
  final TextStyle? titleStyle;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final body = Container(
      constraints: BoxConstraints(minHeight: dense ? 40 : 52),
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: dense ? 7 : 10,
          ),
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.s3)],
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: dense ? 0 : 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (titleStyle ?? AppTypography.body).copyWith(
                      color: done ? ds.ink3 : ds.ink,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 2),
                    meta!,
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s2),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: trailing,
            ),
          ],
        ],
      ),
    );
    if (onTap == null && onLongPress == null) {
      return ColoredBox(color: selected ? ds.primarySoft : Colors.transparent, child: body);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: selected ? ds.primarySoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          hoverColor: selected ? ds.primarySoft : ds.surface2,
          child: body,
        ),
      ),
    );
  }
}

/// 48px hit area around a 20–22px circle. The row itself is still the tap
/// target for opening the item; this is the completion affordance.
class DsCheck extends StatelessWidget {
  const DsCheck({
    super.key,
    required this.checked,
    required this.onChanged,
    this.label,
    this.size = 20,
    this.compact = false,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final target = compact ? 36.0 : 48.0;
    return Semantics(
      checked: checked,
      label: label,
      child: MouseRegion(
        cursor: onChanged == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!checked),
          child: SizedBox(
            width: target,
            height: target,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? ds.primary : Colors.transparent,
                  border: Border.all(
                    color: checked ? ds.primary : ds.ink3,
                    width: 1.5,
                  ),
                ),
                child: checked
                    ? Icon(
                        CupertinoIcons.checkmark,
                        size: size * 0.62,
                        color: ds.onPrimary,
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

class DsDivider extends StatelessWidget {
  const DsDivider({super.key, this.inset = AppSpacing.s4});
  final double inset;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: EdgeInsets.symmetric(horizontal: inset),
    color: context.ds.lineSoft,
  );
}

// ---------------------------------------------------------------- empty

class DsEmpty extends StatelessWidget {
  const DsEmpty({
    super.key,
    this.title,
    required this.message,
    this.icon,
    this.action,
  });

  final String? title;
  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s7,
          vertical: AppSpacing.s7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 28, color: ds.ink3),
              const SizedBox(height: AppSpacing.s2),
            ],
            if (title != null)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyStrong.copyWith(color: ds.ink2),
              ),
            if (title != null) const SizedBox(height: AppSpacing.s1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: ds.ink3,
                  height: 1.5,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s3),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- settings

class DsGroupLabel extends StatelessWidget {
  const DsGroupLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s5,
      AppSpacing.s5 + 2,
      AppSpacing.s5,
      AppSpacing.s2,
    ),
    child: Text(
      label,
      style: AppTypography.overline.copyWith(color: context.ds.ink3),
    ),
  );
}

class DsGroup extends StatelessWidget {
  const DsGroup({super.key, required this.children, this.margin});
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Container(height: 1, color: ds.lineSoft));
      }
      rows.add(children[i]);
    }
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: ds.lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class DsSettingRow extends StatelessWidget {
  const DsSettingRow({
    super.key,
    required this.label,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.selected = false,
  });

  final String label;
  final String? value;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      color: selected ? ds.surface2 : Colors.transparent,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s3),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: danger ? ds.danger : ds.ink,
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: AppSpacing.s2),
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.caption.copyWith(color: ds.ink3),
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s1),
            trailing!,
          ] else if (onTap != null) ...[
            const SizedBox(width: AppSpacing.s1),
            Icon(CupertinoIcons.chevron_right, size: 15, color: ds.ink3),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: ds.surface2,
          child: body,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- fields

class DsField extends StatelessWidget {
  const DsField({
    super.key,
    required this.label,
    required this.child,
    this.help,
  });

  final String label;
  final Widget child;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.small.copyWith(
              color: ds.ink2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          child,
          if (help != null) ...[
            const SizedBox(height: AppSpacing.s1),
            Text(help!, style: AppTypography.small.copyWith(color: ds.ink3)),
          ],
        ],
      ),
    );
  }
}

class DsTextField extends StatelessWidget {
  const DsTextField({
    super.key,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.keyboardType,
    this.focusNode,
    this.enabled = true,
    this.obscureText = false,
    this.style,
  });

  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final bool enabled;
  final bool obscureText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: maxLines,
      enabled: enabled,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      style: (style ?? AppTypography.body).copyWith(color: ds.ink),
      cursorColor: ds.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.body.copyWith(color: ds.ink3),
        filled: true,
        fillColor: ds.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: ds.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: ds.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: ds.primary),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- overlays

/// Mobile sheet, desktop modal dialog. One overlay API so a page does not
/// grow two different editing surfaces.
Future<T?> showDsSheet<T>({
  required BuildContext context,
  required String title,
  required Widget body,
  List<Widget> actions = const [],
  bool fullHeight = false,
  bool useRootNavigator = true,
}) {
  final desktop = MediaQuery.sizeOf(context).width >= 1000;
  if (desktop) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierColor: context.ds.scrim,
      builder: (ctx) => DsDialog(title: title, actions: actions, child: body),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.ds.scrim,
    builder: (ctx) {
      final ds = ctx.ds;
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.88;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
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
                    AppSpacing.s2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.title.copyWith(color: ds.ink),
                        ),
                      ),
                      DsIconButton(
                        icon: CupertinoIcons.xmark,
                        tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                        onPressed: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      0,
                      AppSpacing.s4,
                      AppSpacing.s3,
                    ),
                    child: body,
                  ),
                ),
                if (actions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s2,
                      AppSpacing.s4,
                      AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: ds.lineSoft)),
                    ),
                    child: Row(children: actions),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Full-height mobile sheet used by detail pages: starts at the safe top and
/// pins its actions to the bottom.
Future<T?> showDsFullSheet<T>({
  required BuildContext context,
  required String title,
  required Widget body,
  List<Widget> actions = const [],
  Widget? headerAction,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: context.ds.scrim,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      final ds = ctx.ds;
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: ds.surface,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    alignment: Alignment.center,
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
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s1,
                      AppSpacing.s2,
                      AppSpacing.s2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.title.copyWith(color: ds.ink),
                          ),
                        ),
                        if (headerAction != null) headerAction,
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
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s4,
                        0,
                        AppSpacing.s4,
                        AppSpacing.s4,
                      ),
                      child: body,
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s4,
                        AppSpacing.s2,
                        AppSpacing.s4,
                        AppSpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        color: ds.surface,
                        border: Border(top: BorderSide(color: ds.lineSoft)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(children: actions),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class DsDialog extends StatelessWidget {
  const DsDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 560,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.s6),
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: AppRadii.dialog,
          border: Border.all(color: ds.line),
          boxShadow: AppShadows.two(ds.brightness),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s5,
                AppSpacing.s4,
                AppSpacing.s2,
                AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.title.copyWith(color: ds.ink),
                    ),
                  ),
                  DsIconButton(
                    icon: CupertinoIcons.xmark,
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s5,
                  AppSpacing.s1,
                  AppSpacing.s5,
                  AppSpacing.s3,
                ),
                child: child,
              ),
            ),
            if (actions.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s5,
                  AppSpacing.s3,
                  AppSpacing.s5,
                  AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: ds.lineSoft)),
                ),
                child: Row(children: actions),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- misc

class DsKeyCap extends StatelessWidget {
  const DsKeyCap(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: ds.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: AppTypography.small.copyWith(
          fontSize: 11,
          color: ds.ink3,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Copy affordance used by detail panes for long values.
Future<void> dsCopy(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
}

/// A hairline between stacked sections, spanning the content origin.
class DsHairline extends StatelessWidget {
  const DsHairline({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: color ?? context.ds.lineSoft);
}
