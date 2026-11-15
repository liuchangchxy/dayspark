import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import '../settings_ui.dart';
import 'import_export_section.dart';

/// Data owns user content: tags classify it, the trash holds what was deleted,
/// and import/export moves it. Calendar configuration stays in its own group.
class DataSection extends ConsumerWidget {
  const DataSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tags = ref.watch(tagsProvider).valueOrNull ?? const [];
    final trashed = ref.watch(deletedTodosProvider).valueOrNull ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRows(
          children: [
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
        ),
        Container(height: 1, color: context.ds.lineSoft),
        const ImportExportSection(),
      ],
    );
  }
}
