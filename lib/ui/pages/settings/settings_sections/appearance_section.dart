import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final currentTheme = ref.watch(themeModeProvider);
    final currentAccent = ref.watch(themeColorProvider);
    final locale = ref.watch(localeProvider);
    final defaultTab = ref.watch(defaultTabProvider);
    final brightness = Theme.of(context).brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s2,
          ),
          child: Text(
            l.theme,
            style: AppTypography.small.copyWith(
              color: ds.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: DsSegmented<ThemeMode>(
            expand: true,
            selected: currentTheme,
            options: [
              DsSegmentOption(ThemeMode.system, l.themeSystem),
              DsSegmentOption(ThemeMode.light, l.themeLight),
              DsSegmentOption(ThemeMode.dark, l.themeDark),
            ],
            onSelected: (mode) =>
                ref.read(themeModeProvider.notifier).setThemeMode(mode),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Text(
            l.themeColor,
            style: AppTypography.small.copyWith(
              color: ds.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: 6,
            ),
            children: [
              for (final accent in AppAccent.values)
                _Swatch(
                  color: accent.resolve(brightness),
                  label: accent.nameFor(Localizations.localeOf(context)),
                  selected: currentAccent == accent,
                  onTap: () => ref
                      .read(themeColorProvider.notifier)
                      .setAccent(accent),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        DsHairline(color: ds.lineSoft),
        DsSettingRow(
          label: l.language,
          value: locale == null
              ? l.languageSystem
              : locale.languageCode == 'zh'
              ? l.languageZh
              : l.languageEn,
          onTap: () => _showLanguageDialog(context, ref),
        ),
        DsSettingRow(
          label: l.defaultTab,
          value: switch (defaultTab) {
            AppTab.action => l.today,
            AppTab.calendar => l.calendar,
            AppTab.todos => l.todos,
          },
          onTap: () => _showDefaultTabDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showChoices<T>({
    required BuildContext context,
    required String title,
    required T current,
    required List<(T value, String label)> options,
    required ValueChanged<T> onSelected,
  }) async {
    final picked = await showDialog<T>(
      animationStyle: AnimationStyle.noAnimation,
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
                  horizontal: AppSpacing.s4,
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

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 34,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: context.ds.ink,
                          width: 1.5,
                        )
                      : null,
                ),
                child: selected
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        size: 12,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
