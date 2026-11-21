import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// Provider for the default calendar ID.
/// Stored in SharedPreferences under 'default_calendar_id'.
/// When null, the first calendar is used by convention.
final defaultCalendarIdProvider =
    StateNotifierProvider<DefaultCalendarNotifier, int?>((ref) {
  return DefaultCalendarNotifier();
});

class DefaultCalendarNotifier extends StateNotifier<int?> {
  DefaultCalendarNotifier() : super(null) {
    _load();
  }

  static const _key = 'default_calendar_id';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_key);
    if (id != null) {
      state = id;
    }
  }

  Future<void> setDefaultCalendarId(int id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, id);
  }
}

enum SettingsChevron { none, right, down }

/// Frozen spec settings row:
/// min-height 55px, border-top hairline, label 12px ink, subtitle 10px faint,
/// value 10.5px ink2, chevron 11px faint.
/// Zero horizontal padding on desktop to align with page head; 16px on mobile.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = SettingsChevron.none,
    this.danger = false,
    this.padding,
  });

  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final SettingsChevron chevron;
  final bool danger;
  final EdgeInsetsGeometry? padding;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final chevronIcon = switch (widget.chevron) {
      SettingsChevron.none => null,
      SettingsChevron.right => CupertinoIcons.chevron_right,
      SettingsChevron.down => CupertinoIcons.chevron_down,
    };

    final desktop = isWorkspaceLayout(context);
    final effectivePadding = widget.padding ??
        (desktop
            ? const EdgeInsets.symmetric(vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 8));

    final body = Container(
      constraints: const BoxConstraints(minHeight: 55),
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: _hovered && widget.onTap != null
            ? SpecTokens.wash
            : Colors.transparent,
      ),
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
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.danger ? SpecTokens.red : SpecTokens.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.45,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.value != null)
            Expanded(
              flex: 2,
              child: Text(
                widget.value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: SpecTokens.ink2,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
            ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 8),
            widget.trailing!,
          ],
          if (chevronIcon != null) ...[
            const SizedBox(width: 6),
            Icon(chevronIcon, size: 11, color: SpecTokens.faint),
          ],
        ],
      ),
    );

    if (widget.onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: body,
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
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          const Divider(
            height: 1,
            thickness: 1,
            color: SpecTokens.hair,
          ),
        );
      }
      rows.add(children[i]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// A group heading and its card.
class SettingsGroupBlock extends StatelessWidget {
  const SettingsGroupBlock({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.mobile = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 0,
            mobile ? 16 : 2,
            mobile ? 16 : 0,
            subtitle == null ? 8 : 4,
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 0,
              0,
              mobile ? 16 : 0,
              12,
            ),
            child: Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                height: 1.55,
                color: SpecTokens.faint,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: SpecTokens.paper,
            border: Border(
              top: BorderSide(color: SpecTokens.hair, width: 1),
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Frozen spec inline alert (.inline-alert):
/// 2px amber (or 3px red) left border, soft background, 10.5px text.
class InlineAlert extends StatelessWidget {
  const InlineAlert({
    super.key,
    required this.message,
    this.title,
    this.isRed = false,
    this.action,
  });

  final String message;
  final String? title;
  final bool isRed;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final borderColor = isRed ? SpecTokens.red : SpecTokens.amber;
    final bgColor = isRed ? const Color(0xFFFDF0ED) : SpecTokens.amberSoft;
    final textColor = isRed ? const Color(0xFF7C231B) : const Color(0xFF6B4B12);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: isRed ? BorderRadius.circular(4) : null,
        border: Border(
          left: BorderSide(
            color: borderColor,
            width: isRed ? 3.0 : 2.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            message,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.55,
              color: textColor,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Frozen spec default badge (.badge-default):
/// height 18px, padding 0 5px, radius 3px, wash background, 8.5px muted text.
class BadgeDefault extends StatelessWidget {
  const BadgeDefault({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? AppLocalizations.of(context)?.badgeDefault ?? 'Default';
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: SpecTokens.wash,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8.5,
          letterSpacing: 0.04,
          fontWeight: FontWeight.w500,
          color: SpecTokens.muted,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
    );
  }
}

/// Frozen spec IO card (.io-card):
/// border 1px hair2, radius 8px, padding 14px, bg #FBFBF8.
class IoCard extends StatelessWidget {
  const IoCard({
    super.key,
    required this.title,
    this.description,
    this.child,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? description;
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(SpecTokens.r8),
        border: Border.all(color: SpecTokens.hair2, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.55,
                color: SpecTokens.muted,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ],
          if (child != null) ...[
            const SizedBox(height: 10),
            child!,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
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
      backgroundColor: SpecTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpecTokens.r12),
        side: const BorderSide(color: SpecTokens.hair),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: SpecTokens.ink,
          fontFamilyFallback: AppTypography.fallback,
        ),
      ),
      children: [
        for (final option in options)
          SimpleDialogOption(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(ctx).pop(option.$1),
            child: ListTile(
              title: Text(
                option.$2,
                style: const TextStyle(
                  fontSize: 13,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              trailing: option.$1 == current
                  ? const Icon(
                      CupertinoIcons.checkmark,
                      size: 16,
                      color: SpecTokens.ink,
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
      ],
    ),
  );
  if (picked != null) onSelected(picked);
}
