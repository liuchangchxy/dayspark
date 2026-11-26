import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key, this.onOpenDefaultCalendar});

  final VoidCallback? onOpenDefaultCalendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final locale = ref.watch(localeProvider);
    final defaultTab = ref.watch(defaultTabProvider);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final defaultCalId = ref.watch(defaultCalendarIdProvider);
    final defaultCal = calendars.isEmpty
        ? null
        : calendars.firstWhere(
            (c) => c.id == defaultCalId,
            orElse: () => calendars.first,
          );

    return SettingsRows(
      children: [
        // Default Calendar row
        SettingsRow(
          label: l.defaultCalendar,
          subtitle: l.defaultCalendarSettingDesc,
          value: defaultCal?.name,
          trailing: const BadgeDefault(),
          chevron: SettingsChevron.right,
          onTap: () {
            if (onOpenDefaultCalendar != null) {
              onOpenDefaultCalendar!();
            } else {
              _showDefaultCalendarDialog(context, ref);
            }
          },
        ),
        // Startup view
        SettingsRow(
          label: l.defaultTab,
          subtitle: l.startupViewDesc,
          value: switch (defaultTab) {
            AppTab.action => l.today,
            AppTab.calendar => l.calendar,
            AppTab.todos => l.todos,
          },
          chevron: SettingsChevron.down,
          onTap: () => _showDefaultTabDialog(context, ref),
        ),
        // Theme: Frozen spec requires readonly "浅色" (Light), no switching
        SettingsRow(
          label: l.theme,
          subtitle: l.themeDesc,
          value: l.themeLight,
          chevron: SettingsChevron.none,
          onTap: null,
        ),
        // Accent: the frozen spec defines one value (暖灰). It only affects
        // selection and actions, so there is nothing to pick here.
        SettingsRow(
          label: l.themeColor,
          subtitle: l.accentColorDesc,
          value: l.accentWarmGray,
        ),
        // Language
        SettingsRow(
          label: l.language,
          subtitle: l.languageDesc,
          value: locale == null
              ? l.languageSystem
              : locale.languageCode == 'zh'
              ? l.languageZh
              : l.languageEn,
          chevron: SettingsChevron.down,
          onTap: () => _showLanguageDialog(context, ref),
        ),
      ],
    );
  }

  void _showDefaultCalendarDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    if (calendars.isEmpty) return;
    final currentDefault = ref.read(defaultCalendarIdProvider) ?? calendars.first.id;

    showSettingsChoice<int>(
      context: context,
      title: l.defaultCalendar,
      current: currentDefault,
      options: [
        for (final c in calendars) (c.id, c.name),
      ],
      onSelected: (id) =>
          ref.read(defaultCalendarIdProvider.notifier).setDefaultCalendarId(id),
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
    showSettingsChoice<String>(
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
    showSettingsChoice<AppTab>(
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
