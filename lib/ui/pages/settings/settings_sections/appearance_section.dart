import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/theme_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import '../settings_ui.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final currentTheme = ref.watch(themeModeProvider);
    final currentAccent = ref.watch(themeColorProvider);
    final brightness = Theme.of(context).brightness;
    final ds = context.ds;
    final mobile = !isWorkspaceLayout(context);

    final swatches = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final accent in AppAccent.values)
          _Swatch(
            color: accent.resolve(brightness),
            label: accent.nameFor(Localizations.localeOf(context)),
            selected: currentAccent == accent,
            onTap: () => ref.read(themeColorProvider.notifier).setAccent(accent),
          ),
      ],
    );

    return SettingsRows(
      children: [
        SettingsRow(
          label: l.theme,
          trailing: SizedBox(
            width: 232,
            child: DsSegmented<ThemeMode>(
              expand: true,
              height: 32,
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
        ),
        // Seven 44px swatches are wider than the trailing half of a phone row,
        // which squeezed the "theme colour" label to zero and left seven
        // unlabelled dots. On the phone they sit under the label instead.
        if (mobile)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.themeColor,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: ds.ink,
                  ),
                ),
                const SizedBox(height: 2),
                swatches,
              ],
            ),
          )
        else
          SettingsRow(label: l.themeColor, trailing: swatches),
      ],
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
            height: 44,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: context.ds.ink, width: 1.5)
                      : null,
                ),
                child: selected
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        size: 11,
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
