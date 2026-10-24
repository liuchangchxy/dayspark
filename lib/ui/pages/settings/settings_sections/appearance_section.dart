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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(CupertinoIcons.paintbrush),
          title: Text(l.appearance),
          subtitle: Text(l.theme),
          onTap: () => _showThemeDialog(context, ref),
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.color_filter),
          title: Text(l.themeColor),
          subtitle: _themeColorPreview(context, ref),
          onTap: () => _showAccentDialog(context, ref),
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.globe),
          title: Text(l.language),
          subtitle: Text(
            ref.watch(localeProvider) == null
                ? l.languageSystem
                : ref.watch(localeProvider)?.languageCode == 'zh'
                ? l.languageZh
                : l.languageEn,
          ),
          onTap: () => _showLanguageDialog(context, ref),
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.square_split_2x1),
          title: Text(l.defaultTab),
          subtitle: Text(switch (ref.watch(defaultTabProvider)) {
            AppTab.action => l.today,
            AppTab.calendar => l.calendar,
            AppTab.todos => l.todos,
          }),
          onTap: () => _showDefaultTabDialog(context, ref),
        ),
      ],
    );
  }

  Widget _themeColorPreview(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(themeColorProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: accent.resolve(Theme.of(context).brightness),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(accent.nameFor(Localizations.localeOf(context))),
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

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    _showChoices<ThemeMode>(
      context: context,
      title: l.theme,
      current: ref.read(themeModeProvider),
      options: [
        (ThemeMode.system, l.themeSystem),
        (ThemeMode.light, l.themeLight),
        (ThemeMode.dark, l.themeDark),
      ],
      onSelected: (mode) =>
          ref.read(themeModeProvider.notifier).setThemeMode(mode),
    );
  }

  void _showAccentDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final current = ref.watch(themeColorProvider);
    final brightness = Theme.of(context).brightness;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.themeColor),
        content: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: AppAccent.values.map((accent) {
            final color = accent.resolve(brightness);
            final selected = current == accent;
            final label = accent.nameFor(locale);
            return Semantics(
              label: label,
              selected: selected,
              button: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: () {
                    ref.read(themeColorProvider.notifier).setAccent(accent);
                    Navigator.of(ctx).pop();
                  },
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(
                                    color: Theme.of(ctx).colorScheme.onSurface,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: selected
                              ? const Icon(
                                  CupertinoIcons.checkmark,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(label, style: AppTypography.overline),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
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
