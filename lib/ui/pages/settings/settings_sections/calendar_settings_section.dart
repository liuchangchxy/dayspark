import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class CalendarSettingsSection extends ConsumerWidget {
  const CalendarSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final defaultTab = ref.watch(defaultTabProvider);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? const [];
    final trashed = ref.watch(deletedTodosProvider).valueOrNull ?? const [];

    return SettingsRows(
      children: [
        SettingsRow(
          label: l.defaultTab,
          value: switch (defaultTab) {
            AppTab.action => l.today,
            AppTab.calendar => l.calendar,
            AppTab.todos => l.todos,
          },
          chevron: SettingsChevron.down,
          onTap: () => _showDefaultTabDialog(context, ref),
        ),
        SettingsRow(
          label: l.manageCalendars,
          value: l.categoryCount(calendars.length),
          chevron: SettingsChevron.right,
          onTap: () => context.push('/calendars'),
        ),
        SettingsRow(
          label: l.tags,
          value: l.categoryCount(tags.length),
          chevron: SettingsChevron.right,
          onTap: () => context.push('/tags'),
        ),
        SettingsRow(
          label: l.trash,
          value: l.dayItemCount(trashed.length),
          chevron: SettingsChevron.right,
          onTap: () => context.push('/trash'),
        ),
      ],
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
