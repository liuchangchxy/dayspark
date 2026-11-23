import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

/// Data owns user content: tags classify it, the trash holds what was deleted,
/// and import/export moves it. Calendar configuration stays in its own group.
class DataSection extends ConsumerWidget {
  const DataSection({super.key, this.onSelectSection});

  final ValueChanged<String>? onSelectSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tags = ref.watch(tagsProvider).valueOrNull ?? const [];
    final trashedTodos = ref.watch(deletedTodosProvider).valueOrNull ?? const [];
    final trashedEvents = ref.watch(deletedEventsProvider).valueOrNull ?? const [];
    final totalTrashed = trashedTodos.length + trashedEvents.length;

    return SettingsRows(
      children: [
        SettingsRow(
          label: l.tags,
          subtitle: l.tagManagementDesc,
          value: l.categoryCount(tags.length),
          chevron: SettingsChevron.right,
          onTap: () => onSelectSection?.call('tags'),
        ),
        SettingsRow(
          label: l.trash,
          subtitle: l.trashDesc,
          value: l.dayItemCount(totalTrashed),
          chevron: SettingsChevron.right,
          onTap: () => onSelectSection?.call('trash'),
        ),
        SettingsRow(
          label: l.importExport,
          subtitle: l.ioCardImportDesc,
          chevron: SettingsChevron.right,
          onTap: () => onSelectSection?.call('io'),
        ),
        SettingsRow(
          label: l.daysparkBackup,
          subtitle: l.ioSectionDesc,
          chevron: SettingsChevron.right,
          onTap: () => onSelectSection?.call('io'),
        ),
      ],
    );
  }
}
