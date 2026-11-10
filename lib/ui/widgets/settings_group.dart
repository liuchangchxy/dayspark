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

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s1,
              AppSpacing.s4,
              AppSpacing.s1,
              AppSpacing.s2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: AppTypography.overline.copyWith(color: ds.ink3),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          )
        else
          const SizedBox(height: AppSpacing.s3),
        Container(
          decoration: BoxDecoration(
            color: ds.surface,
            borderRadius: AppRadii.control,
            border: Border.all(color: ds.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}
