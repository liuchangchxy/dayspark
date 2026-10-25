import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/color_swatch_grid.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';

const _tagColors = [
  '#EF4444',
  '#F59E0B',
  '#10B981',
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
  '#6B7280',
  '#14B8A6',
  '#F97316',
  '#6366F1',
];

const int _maxTagNameLength = 50;

class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tagsAsync = ref.watch(tagsProvider);

    return WorkspacePage(
      title: l.manageTags,
      maxContentWidth: 720,
      actions: [
        IconButton(
          icon: const Icon(CupertinoIcons.add, size: 18),
          tooltip: l.createTag,
          onPressed: () => _editTag(context, ref, null),
        ),
      ],
      child: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          debugPrint('tags: load error: $error');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.actionFailedRetry, style: AppTypography.body),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => ref.invalidate(tagsProvider),
                  child: Text(l.retry),
                ),
              ],
            ),
          );
        },
        data: (tags) {
          if (tags.isEmpty) {
            return EmptyState(
              icon: CupertinoIcons.tag,
              title: l.noTags,
              hint: l.tagEmptyHint,
              action: FilledButton.icon(
                onPressed: () => _editTag(context, ref, null),
                icon: const Icon(CupertinoIcons.add, size: 18),
                label: Text(l.tagsEmptyAction),
              ),
            );
          }
          return ListView.builder(
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: ColorUtils.parseHex(tag.color),
                  radius: 14,
                ),
                title: Text(tag.name),
                onTap: () => _editTag(context, ref, tag),
                trailing: IconButton(
                  icon: const Icon(CupertinoIcons.delete, size: 20),
                  tooltip: l.deleteTag,
                  onPressed: () => _confirmDeleteTag(context, ref, tag),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteTag(
    BuildContext context,
    WidgetRef ref,
    Tag tag,
  ) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteTag),
        // A delete that says which tag, and what happens to the records, is
        // the difference between a mistake and a decision.
        content: Text(l.tagDeleteBody(tag.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(deleteTagProvider)(tag.id);
  }

  /// Create and edit are the same dialog: two different UIs for one field is
  /// how validation ended up only on one of them.
  Future<void> _editTag(BuildContext context, WidgetRef ref, Tag? tag) async {
    final l = AppLocalizations.of(context)!;
    final existing = ref.read(tagsProvider).valueOrNull ?? const <Tag>[];
    final nameController = TextEditingController(text: tag?.name ?? '');
    var selectedColor = tag?.color ?? '#6B7280';
    String? error;
    var saving = false;

    await showDialog<void>(
    animationStyle: AnimationStyle.noAnimation, context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tag == null ? l.createTag : l.editTag),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: tag == null,
                maxLength: _maxTagNameLength,
                decoration: InputDecoration(
                  labelText: l.tagName,
                  errorText: error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ColorSwatchGrid(
                colors: _tagColors,
                selected: selectedColor,
                onSelected: (hex) => setState(() => selectedColor = hex),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setState(() => error = l.tagNameRequired);
                        return;
                      }
                      if (name.length > _maxTagNameLength) {
                        setState(
                          () => error = l.tagNameTooLong(_maxTagNameLength),
                        );
                        return;
                      }
                      final clash = existing.any(
                        (other) =>
                            other.id != tag?.id &&
                            other.name.toLowerCase() == name.toLowerCase(),
                      );
                      if (clash) {
                        setState(() => error = l.tagDuplicate);
                        return;
                      }
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        if (tag == null) {
                          await ref.read(createTagProvider)(
                            name: name,
                            color: selectedColor,
                          );
                        } else {
                          await ref.read(updateTagProvider)(
                            id: tag.id,
                            name: name,
                            color: selectedColor,
                          );
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (failure) {
                        debugPrint('tags: save error: $failure');
                        if (ctx.mounted) {
                          setState(() {
                            saving = false;
                            error = l.actionFailedRetry;
                          });
                        }
                      }
                    },
              child: Text(tag == null ? l.create : l.save),
            ),
          ],
        ),
      ),
    );
  }
}
