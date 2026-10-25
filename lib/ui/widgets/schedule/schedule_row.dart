import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// One row of a form or a detail pane: a label on the left, its value on the
/// right, an affordance only when the row is actually actionable.
///
/// Rows carry no icons and no helper text — the label and the value are the
/// whole explanation, and that is what keeps a form scannable without the
/// reader having to parse a sentence per field.
class ScheduleRow extends StatelessWidget {
  const ScheduleRow({
    super.key,
    required this.label,
    required this.value,
    this.placeholder = false,
    this.onTap,
    this.onClear,
    this.clearTooltip,
    this.trailing,
    this.emptyValue,
  });

  final String label;

  /// Already-localized display value; never a raw model string.
  final String value;

  /// Renders [value] in the muted tone, for "not set" states.
  final bool placeholder;

  final VoidCallback? onTap;
  final VoidCallback? onClear;

  /// What the clear button removes — "Clear deadline", "Cancel scheduled
  /// time". A generic "Delete" reads as deleting the whole row.
  final String? clearTooltip;

  final Widget? trailing;

  /// Announced instead of [value] when the row is empty, so screen readers do
  /// not read a dash.
  final String? emptyValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interactive = onTap != null;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Semantics(
                label: label,
                value: placeholder ? (emptyValue ?? value) : value,
                button: interactive,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTypography.body.copyWith(
                      color: placeholder
                          ? context.semantic.textTertiary
                          : theme.colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            if (interactive && trailing == null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 12,
                color: context.semantic.textTertiary,
              ),
            ],
            if (onClear != null) ...[
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                icon: const Icon(CupertinoIcons.clear, size: 14),
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
                tooltip:
                    clearTooltip ??
                    MaterialLocalizations.of(context).deleteButtonTooltip,
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.xs),
              trailing!,
            ],
          ],
        ),
      ),
    );

    if (!interactive) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: row,
      ),
    );
  }
}

/// Heading that groups following rows inside a detail pane or form section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppTypography.overline.copyWith(
                color: context.semantic.textSecondary,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Hairline used between rows in a flat list, so rows read as one surface
/// rather than as separate cards.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.semantic.separatorSoft);
}
