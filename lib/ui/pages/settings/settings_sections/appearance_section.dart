import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final currentTheme = ref.watch(themeModeProvider);
    final currentAccent = ref.watch(themeColorProvider);
    final brightness = Theme.of(context).brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Theme mode inline selector (equal width 3 columns, no wrapping)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.paintbrush, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    l.theme,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l.themeSystem, maxLines: 1),
                      icon: const Icon(CupertinoIcons.device_phone_portrait, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l.themeLight, maxLines: 1),
                      icon: const Icon(CupertinoIcons.sun_max, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l.themeDark, maxLines: 1),
                      icon: const Icon(CupertinoIcons.moon, size: 16),
                    ),
                  ],
                  selected: {currentTheme},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) {
                      ref.read(themeModeProvider.notifier).setThemeMode(set.first);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

        // 2. Theme accent color 6 swatches (48dp touch targets, 24dp visual circle)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.color_filter, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    l.themeColor,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    currentAccent.nameFor(Localizations.localeOf(context)),
                    style: AppTypography.caption.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: AppAccent.values.map((accent) {
                      final color = accent.resolve(brightness);
                      final selected = currentAccent == accent;
                      final label = accent.nameFor(Localizations.localeOf(context));
                      return Semantics(
                        label: label,
                        selected: selected,
                        button: true,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: InkWell(
                            onTap: () => ref.read(themeColorProvider.notifier).setAccent(accent),
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: selected
                                        ? Border.all(
                                            color: Theme.of(context).colorScheme.onSurface,
                                            width: 2.5,
                                          )
                                        : null,
                                  ),
                                  child: selected
                                      ? const Center(
                                          child: Icon(
                                            CupertinoIcons.checkmark,
                                            size: 13,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
