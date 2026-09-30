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
          subtitle: Text(
            ref.watch(defaultTabProvider) == AppTab.calendar
                ? l.calendarFirst
                : l.todosFirst,
          ),
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

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.theme),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.system);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.sun_max),
              title: Text(l.themeSystem),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.light);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.sun_max),
              title: Text(l.themeLight),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.moon),
              title: Text(l.themeDark),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
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
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurface,
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
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.language),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(null);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: Icon(
                current == null ? CupertinoIcons.checkmark : null,
                size: 20,
              ),
              title: Text(l.languageSystem),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(const Locale('zh'));
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: Icon(
                current?.languageCode == 'zh' ? CupertinoIcons.checkmark : null,
                size: 20,
              ),
              title: Text(l.languageZh),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(localeProvider.notifier).setLocale(const Locale('en'));
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: Icon(
                current?.languageCode == 'en' ? CupertinoIcons.checkmark : null,
                size: 20,
              ),
              title: Text(l.languageEn),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  void _showDefaultTabDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.defaultTab),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref
                  .read(defaultTabProvider.notifier)
                  .setDefaultTab(AppTab.calendar);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.calendar),
              title: Text(l.calendarFirst),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(defaultTabProvider.notifier).setDefaultTab(AppTab.todos);
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              leading: const Icon(CupertinoIcons.checkmark_rectangle),
              title: Text(l.todosFirst),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
