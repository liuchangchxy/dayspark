import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/l10n/app_localizations.dart';

String colorLabel(AppLocalizations l, String hex) =>
    switch (hex.toUpperCase()) {
      '#EF4444' || '#DC2626' => l.colorRed,
      '#F59E0B' || '#D97706' => l.colorAmber,
      '#10B981' || '#16A34A' => l.colorGreen,
      '#2563EB' || '#3B82F6' || '#2D4F7C' || '#4F6D8C' => l.colorBlue,
      '#8B5CF6' || '#7C3AED' || '#6F5D7E' => l.colorPurple,
      '#EC4899' || '#DB2777' || '#8F5A68' => l.colorPink,
      '#6B7280' || '#4B5563' => l.colorGray,
      '#14B8A6' || '#0D9488' || '#4F7368' => l.colorTeal,
      '#F97316' || '#EA580C' || '#9A6248' => l.colorOrange,
      '#6366F1' || '#4F46E5' => l.colorIndigo,
      _ => l.colorBlue,
    };

/// 6-column swatch grid with 48dp minimum touch targets.
/// Uses Wrap with fixed 6-item width calculation or standard Flow/Wrap
/// to support intrinsic dimensions in Dialogs.
class ColorSwatchGrid extends StatelessWidget {
  const ColorSwatchGrid({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final hex in colors)
          Semantics(
            button: true,
            selected: hex.toUpperCase() == selected.toUpperCase(),
            label: colorLabel(l, hex),
            child: InkWell(
              onTap: () => onSelected(hex),
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ColorUtils.parseHex(hex),
                      shape: BoxShape.circle,
                      border: hex.toUpperCase() == selected.toUpperCase()
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2.5,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
