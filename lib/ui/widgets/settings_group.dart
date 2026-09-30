import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';

/// iOS-style grouped list: a quiet label over a rounded surface card.
///
/// Settings read as flat text without it — a hairline divider on the page
/// ground is invisible in dark mode, so groups need a surface of their own
/// (DESIGN 分层).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    required this.child,
    this.trailing,
  });

  /// Omitted when the card's own first row already names the group.
  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: AppTypography.overline.copyWith(
                      color: context.semantic.textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          )
        else
          const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Card(clipBehavior: Clip.antiAlias, child: child),
        ),
      ],
    );
  }
}
