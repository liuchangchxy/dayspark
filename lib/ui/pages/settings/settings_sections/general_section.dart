import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/general_settings_provider.dart';
import 'package:dayspark/domain/providers/locale_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

class GeneralSettingsSection extends ConsumerWidget {
  const GeneralSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final locale = ref.watch(localeProvider);
    final defaultTab = ref.watch(defaultTabProvider);
    final firstDay = ref.watch(firstDayOfWeekProvider);
    final is24Hour = ref.watch(use24HourFormatProvider);
    final isWorkspace = isWorkspaceLayout(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Language
        ListTile(
          leading: const Icon(CupertinoIcons.globe, size: 20),
          title: Text(l.language, style: AppTypography.body),
          trailing: Text(
            locale == null
                ? l.languageSystem
                : (locale.languageCode == 'zh' ? l.languageZh : l.languageEn),
            style: AppTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onTap: () => _pickLanguage(context, ref, locale, isWorkspace),
        ),
        const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

        // 2. Open on Startup
        ListTile(
          leading: const Icon(CupertinoIcons.square_arrow_right, size: 20),
          title: Text(l.startupTab, style: AppTypography.body),
          trailing: Text(
            switch (defaultTab) {
              AppTab.action => l.startupTabAction,
              AppTab.calendar => l.startupTabCalendar,
              AppTab.todos => l.startupTabTodos,
            },
            style: AppTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onTap: () => _pickStartupTab(context, ref, defaultTab, isWorkspace),
        ),
        const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

        // 3. Week starts on
        ListTile(
          leading: const Icon(CupertinoIcons.calendar_today, size: 20),
          title: Text(l.weekStartsOn, style: AppTypography.body),
          trailing: Text(
            firstDay == 1 ? l.weekStartsMonday : l.weekStartsSunday,
            style: AppTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onTap: () => _pickFirstDay(context, ref, firstDay, isWorkspace),
        ),
        const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),

        // 4. Time format
        ListTile(
          leading: const Icon(CupertinoIcons.time, size: 20),
          title: Text(l.timeFormat, style: AppTypography.body),
          trailing: Text(
            is24Hour ? l.timeFormat24 : l.timeFormat12,
            style: AppTypography.caption.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onTap: () => _pickTimeFormat(context, ref, is24Hour, isWorkspace),
        ),
      ],
    );
  }

  void _showChoicePicker({
    required BuildContext context,
    required String title,
    required List<Widget> items,
    required bool isWorkspace,
  }) {
    if (isWorkspace) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: AppTypography.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: items,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
          ],
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(title, style: AppTypography.title),
              ),
              ...items,
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      );
    }
  }

  void _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    Locale? current,
    bool isWorkspace,
  ) {
    final l = AppLocalizations.of(context)!;
    _showChoicePicker(
      context: context,
      title: l.language,
      isWorkspace: isWorkspace,
      items: [
        _buildItem(
          label: l.languageSystem,
          isSelected: current == null,
          onTap: () {
            ref.read(localeProvider.notifier).setLocale(null);
            Navigator.of(context).pop();
          },
        ),
        _buildItem(
          label: l.languageZh,
          isSelected: current?.languageCode == 'zh',
          onTap: () {
            ref.read(localeProvider.notifier).setLocale(const Locale('zh'));
            Navigator.of(context).pop();
          },
        ),
        _buildItem(
          label: l.languageEn,
          isSelected: current?.languageCode == 'en',
          onTap: () {
            ref.read(localeProvider.notifier).setLocale(const Locale('en'));
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _pickStartupTab(
    BuildContext context,
    WidgetRef ref,
    AppTab current,
    bool isWorkspace,
  ) {
    final l = AppLocalizations.of(context)!;
    _showChoicePicker(
      context: context,
      title: l.startupTab,
      isWorkspace: isWorkspace,
      items: [
        _buildItem(
          label: l.startupTabAction,
          isSelected: current == AppTab.action,
          onTap: () {
            ref.read(defaultTabProvider.notifier).setDefaultTab(AppTab.action);
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.startupTabChangedNotice)),
            );
          },
        ),
        _buildItem(
          label: l.startupTabCalendar,
          isSelected: current == AppTab.calendar,
          onTap: () {
            ref.read(defaultTabProvider.notifier).setDefaultTab(AppTab.calendar);
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.startupTabChangedNotice)),
            );
          },
        ),
        _buildItem(
          label: l.startupTabTodos,
          isSelected: current == AppTab.todos,
          onTap: () {
            ref.read(defaultTabProvider.notifier).setDefaultTab(AppTab.todos);
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.startupTabChangedNotice)),
            );
          },
        ),
      ],
    );
  }

  void _pickFirstDay(
    BuildContext context,
    WidgetRef ref,
    int current,
    bool isWorkspace,
  ) {
    final l = AppLocalizations.of(context)!;
    _showChoicePicker(
      context: context,
      title: l.weekStartsOn,
      isWorkspace: isWorkspace,
      items: [
        _buildItem(
          label: l.weekStartsMonday,
          isSelected: current == 1,
          onTap: () {
            ref.read(firstDayOfWeekProvider.notifier).setFirstDay(1);
            Navigator.of(context).pop();
          },
        ),
        _buildItem(
          label: l.weekStartsSunday,
          isSelected: current == 7,
          onTap: () {
            ref.read(firstDayOfWeekProvider.notifier).setFirstDay(7);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _pickTimeFormat(
    BuildContext context,
    WidgetRef ref,
    bool current,
    bool isWorkspace,
  ) {
    final l = AppLocalizations.of(context)!;
    _showChoicePicker(
      context: context,
      title: l.timeFormat,
      isWorkspace: isWorkspace,
      items: [
        _buildItem(
          label: l.timeFormat24,
          isSelected: current == true,
          onTap: () {
            ref.read(use24HourFormatProvider.notifier).set24Hour(true);
            Navigator.of(context).pop();
          },
        ),
        _buildItem(
          label: l.timeFormat12,
          isSelected: current == false,
          onTap: () {
            ref.read(use24HourFormatProvider.notifier).set24Hour(false);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(label, style: AppTypography.body),
      trailing: isSelected
          ? const Icon(CupertinoIcons.checkmark, size: 18)
          : null,
      onTap: onTap,
    );
  }
}
