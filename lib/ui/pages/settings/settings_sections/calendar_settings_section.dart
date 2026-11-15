import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class CalendarSettingsSection extends ConsumerWidget {
  const CalendarSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];

    return SettingsRows(
      children: [
        SettingsRow(
          label: l.manageCalendars,
          value: l.categoryCount(calendars.length),
          chevron: SettingsChevron.right,
          onTap: () => context.push('/calendars'),
        ),
      ],
    );
  }
}
