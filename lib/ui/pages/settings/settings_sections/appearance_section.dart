import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          subtitle: _themeColorPreview(ref),
          onTap: () => _showColorPicker(context, ref),
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

  Widget _themeColorPreview(WidgetRef ref) {
    final color = ref.watch(themeColorProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color ?? const Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
        ),
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

  static const _presetColors = [
    Color(0xFF2563EB), // Blue (default)
    Color(0xFF7C3AED), // Purple
    Color(0xFFDB2777), // Pink
    Color(0xFFDC2626), // Red
    Color(0xFFEA580C), // Orange
    Color(0xFFCA8A04), // Yellow
    Color(0xFF16A34A), // Green
    Color(0xFF0891B2), // Cyan
    Color(0xFF4F46E5), // Indigo
    Color(0xFF64748B), // Slate
  ];

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final current = ref.read(themeColorProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.themeColor),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _presetColors.asMap().entries.map((entry) {
            final i = entry.key;
            final color = entry.value;
            final selected = (current ?? const Color(0xFF2563EB)) == color;
            return Semantics(
              label: 'Color ${i + 1}',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                onTap: () {
                  ref.read(themeColorProvider.notifier).setColor(color);
                  Navigator.of(ctx).pop();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            width: 3,
                          )
                        : null,
                  ),
                  child: selected
                      ? Icon(
                          CupertinoIcons.checkmark,
                          color: ThemeData.estimateBrightnessForColor(color) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          size: 20,
                        )
                      : null,
                ),
              ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(themeColorProvider.notifier).setColor(null);
              Navigator.of(ctx).pop();
            },
            child: Text(l.resetColor),
          ),
        ],
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
