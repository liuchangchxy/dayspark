import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
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
        // 1. Theme mode 3-column equal selector
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
              Container(
                decoration: BoxDecoration(
                  color: context.semanticColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    _ThemeModeTab(
                      label: l.themeSystem,
                      icon: CupertinoIcons.device_phone_portrait,
                      selected: currentTheme == ThemeMode.system,
                      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system),
                    ),
                    _ThemeModeTab(
                      label: l.themeLight,
                      icon: CupertinoIcons.sun_max,
                      selected: currentTheme == ThemeMode.light,
                      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light),
                    ),
                    _ThemeModeTab(
                      label: l.themeDark,
                      icon: CupertinoIcons.moon,
                      selected: currentTheme == ThemeMode.dark,
                      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg, color: context.semanticColors.separatorSoft),

        // 2. Theme accent color inline 6 swatches
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
                                  width: 26,
                                  height: 26,
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
                                            size: 14,
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

class _ThemeModeTab extends StatelessWidget {
  const _ThemeModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? theme.colorScheme.onSurface : context.semanticColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? theme.colorScheme.onSurface : context.semanticColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
