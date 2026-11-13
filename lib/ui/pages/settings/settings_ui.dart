import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// Settings primitives: a 56px row with the control pinned right and a group
/// card that owns its hairlines, so no row has to draw its own box.
///
/// The desktop page stacks every group beside a 200px anchor list; the phone
/// stacks the same groups in one column. Both use the same rows — only the
/// card outline differs.

enum SettingsChevron { none, right, down }

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = SettingsChevron.none,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final SettingsChevron chevron;
  final bool danger;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final chevronIcon = switch (chevron) {
      SettingsChevron.none => null,
      SettingsChevron.right => CupertinoIcons.chevron_right,
      SettingsChevron.down => CupertinoIcons.chevron_down,
    };
    final body = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: padding,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: danger ? ds.danger : ds.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.small.copyWith(
                      fontSize: 12,
                      height: 1.35,
                      color: ds.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null)
            Expanded(
              flex: 2,
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.caption.copyWith(
                  fontSize: 13,
                  color: ds.ink3,
                ),
              ),
            ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (chevronIcon != null) ...[
            const SizedBox(width: 8),
            Icon(chevronIcon, size: 15, color: ds.ink3),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, hoverColor: ds.surface2, child: body),
      ),
    );
  }
}

/// Rows stacked with a hairline between them.
class SettingsRows extends StatelessWidget {
  const SettingsRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Container(height: 1, color: ds.lineSoft));
      rows.add(children[i]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// A group heading and its card. Desktop draws a bordered 8px card; the phone
/// draws full-bleed rows between two hairlines so the page keeps one rhythm.
class SettingsGroupBlock extends StatelessWidget {
  const SettingsGroupBlock({
    super.key,
    required this.title,
    required this.child,
    this.mobile = false,
  });

  final String title;
  final Widget child;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(mobile ? 16 : 0, 20, mobile ? 16 : 0, 8),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ds.ink2,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: mobile
              ? BoxDecoration(
                  color: ds.surface,
                  border: Border(
                    top: BorderSide(color: ds.lineSoft),
                    bottom: BorderSide(color: ds.lineSoft),
                  ),
                )
              : BoxDecoration(
                  color: ds.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ds.line),
                ),
          child: child,
        ),
      ],
    );
  }
}

Future<void> showSettingsChoice<T>({
  required BuildContext context,
  required String title,
  required T current,
  required List<(T, String)> options,
  required ValueChanged<T> onSelected,
}) async {
  final picked = await showDialog<T>(
    animationStyle: AnimationStyle.noAnimation,
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final option in options)
          SimpleDialogOption(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(ctx).pop(option.$1),
            child: ListTile(
              title: Text(option.$2),
              trailing: option.$1 == current
                  ? const Icon(CupertinoIcons.checkmark, size: 18)
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
      ],
    ),
  );
  if (picked != null) onSelected(picked);
}
