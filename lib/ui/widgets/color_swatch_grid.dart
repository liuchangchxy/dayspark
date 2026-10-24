import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// A row of colour choices.
///
/// Calendar and tag editors offer the same gesture, so the hit target, the
/// selected ring and — most importantly — what a screen reader hears are
/// defined once. A swatch announced as "#2563EB" is unusable; it says its
/// colour name instead.
String colorLabel(AppLocalizations l, String hex) =>
    switch (hex.toUpperCase()) {
      '#EF4444' || '#DC2626' => l.colorRed,
      '#F59E0B' || '#D97706' => l.colorAmber,
      '#10B981' || '#16A34A' => l.colorGreen,
      '#2563EB' || '#3B82F6' => l.colorBlue,
      '#8B5CF6' || '#7C3AED' => l.colorPurple,
      '#EC4899' || '#DB2777' => l.colorPink,
      '#6B7280' || '#4B5563' => l.colorGray,
      '#14B8A6' || '#0D9488' => l.colorTeal,
      '#F97316' || '#EA580C' => l.colorOrange,
      '#6366F1' || '#4F46E5' => l.colorIndigo,
      _ => l.colorBlue,
    };

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
            selected: hex == selected,
            label: colorLabel(l, hex),
            child: InkWell(
              onTap: () => onSelected(hex),
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: ColorUtils.parseHex(hex),
                      shape: BoxShape.circle,
                      border: hex == selected
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
