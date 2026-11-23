import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class TodosSection extends ConsumerWidget {
  const TodosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return SettingsRows(
      children: [
        SettingsRow(
          label: l.sixThings,
          subtitle: l.sixThingsDesc,
          trailing: Switch(
            value: ref.watch(sixThingsModeProvider),
            onChanged: (v) =>
                ref.read(sixThingsModeProvider.notifier).setEnabled(v),
          ),
        ),
        SettingsRow(
          label: l.hideCompleted,
          subtitle: l.hideCompletedDesc,
          trailing: Switch(
            value: ref.watch(hideCompletedProvider).valueOrNull ?? false,
            onChanged: (v) => ref.read(setHideCompletedProvider)(v),
          ),
        ),
      ],
    );
  }
}
