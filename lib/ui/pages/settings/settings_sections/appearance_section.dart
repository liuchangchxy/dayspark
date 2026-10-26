import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final currentTheme = ref.watch(themeModeProvider);
    final currentAccent = ref.watch(themeColorProvider);
    final locale = ref.watch(localeProvider);
    final defaultTab = ref.watch(defaultTabProvider);
    final brightness = Theme.of(context).brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Theme mode inline selector
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
                      label: Text(l.themeSystem),
                      icon: const Icon(CupertinoIcons.device_phone_portrait, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l.themeLight),
                      icon: const Icon(CupertinoIcons.sun_max, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l.themeDark),
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

        // 2. Theme accent color inline swatches
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
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
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
                      child: GestureDetector(
                        onTap: () => ref.read(themeColorProvider.notifier).setAccent(accent),
                        child: Container(
                          width: 28,
                          height: 28,
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
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

        // 3. Language & Default Startup View
        ListTile(
          leading: const Icon(CupertinoIcons.globe),
          title: Text(l.language),
          trailing: Text(
            locale == null
                ? l.languageSystem
                : locale.languageCode == 'zh'
                ? l.languageZh
                : l.languageEn,
            style: AppTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => _showLanguageDialog(context, ref),
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.square_split_2x1),
          title: Text(l.defaultTab),
          trailing: Text(
            switch (defaultTab) {
              AppTab.action => l.today,
              AppTab.calendar => l.calendar,
              AppTab.todos => l.todos,
            },
            style: AppTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => _showDefaultTabDialog(context, ref),
        ),
      ],
    );
  }

  /// One selector for every setting on this page. A checkmark that is always
  /// in the same place is what makes "which one is selected" readable across
  /// four different dialogs.
  Future<void> _showChoices<T>({
    required BuildContext context,
    required String title,
    required T current,
    required List<(T value, String label)> options,
    required ValueChanged<T> onSelected,
  }) async {
    final picked = await showDialog<T>(
    animationStyle: AnimationStyle.noAnimation, context: context,
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked != null) onSelected(picked);
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final current = ref.read(localeProvider);
    final currentTag = current == null
        ? 'system'
        : current.languageCode == 'zh'
        ? 'zh'
        : 'en';
    _showChoices<String>(
      context: context,
      title: l.language,
      current: currentTag,
      options: [
        ('system', l.languageSystem),
        ('zh', l.languageZh),
        ('en', l.languageEn),
      ],
      onSelected: (tag) => ref
          .read(localeProvider.notifier)
          .setLocale(tag == 'system' ? null : Locale(tag)),
    );
  }

  void _showDefaultTabDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    _showChoices<AppTab>(
      context: context,
      title: l.defaultTab,
      current: ref.read(defaultTabProvider),
      options: [
        (AppTab.action, l.today),
        (AppTab.calendar, l.calendar),
        (AppTab.todos, l.todos),
      ],
      onSelected: (tab) =>
          ref.read(defaultTabProvider.notifier).setDefaultTab(tab),
    );
  }
}
