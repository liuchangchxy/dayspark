import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
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
    final ds = context.ds;
    final tagsAsync = ref.watch(tagsProvider);

    return WorkspacePage(
      title: l.manageTags,
      maxContentWidth: 720,
      child: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          debugPrint('tags: load error: $error');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.actionFailedRetry,
                  style: AppTypography.body.copyWith(color: ds.ink2),
                ),
                const SizedBox(height: AppSpacing.s2),
                DsButton(
                  label: l.retry,
                  tone: DsButtonTone.ghost,
                  small: true,
                  onPressed: () => ref.invalidate(tagsProvider),
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
              action: DsButton(
                label: l.tagsEmptyAction,
                icon: CupertinoIcons.add,
                onPressed: () => _editTag(context, ref, null),
              ),
            );
          }
          return ListView(
            key: const ValueKey('tags-list'),
            padding: const EdgeInsets.only(bottom: AppSpacing.s6),
            children: [
              DsGroupLabel(l.allTags),
              DsGroup(
                children: [
                  for (final tag in tags)
                    DsSettingRow(
                      label: tag.name,
                      value: l.dayItemCount(_countFor(ref, tag.id)),
                      leading: DsDot(
                        color: ColorUtils.parseHex(tag.color),
                        size: 8,
                      ),
                      trailing: DsIconButton(
                        icon: CupertinoIcons.delete,
                        size: 16,
                        compact: true,
                        tooltip: l.deleteTag,
                        onPressed: () => _confirmDeleteTag(context, ref, tag),
                      ),
                      onTap: () => _editTag(context, ref, tag),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s3,
                  AppSpacing.s4,
                  AppSpacing.s1,
                ),
                child: DsButton(
                  label: l.createTag,
                  icon: CupertinoIcons.add,
                  tone: DsButtonTone.secondary,
                  expand: true,
                  onPressed: () => _editTag(context, ref, null),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s5,
                  AppSpacing.s3,
                  AppSpacing.s5,
                  AppSpacing.s2,
                ),
                child: Text(
                  l.tagEmptyHint,
                  style: AppTypography.caption.copyWith(color: ds.ink3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _countFor(WidgetRef ref, int tagId) {
    final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];
    final tagMap = ref.watch(todoTagIdsMapProvider).valueOrNull ?? const {};
    var count = 0;
    for (final todo in todos) {
      if (todo.status == 'COMPLETED' || todo.status == 'CANCELLED') continue;
      if (tagMap[todo.id]?.contains(tagId) ?? false) count++;
    }
    return count;
  }

  Future<void> _confirmDeleteTag(
    BuildContext context,
    WidgetRef ref,
    Tag tag,
  ) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DsDialog(
        title: l.deleteTag,
        width: 440,
        actions: [
          const Spacer(),
          DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s2),
          DsButton(
            label: l.delete,
            tone: DsButtonTone.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        // A delete that says which tag, and what happens to the records, is
        // the difference between a mistake and a decision.
        child: Text(
          l.tagDeleteBody(tag.name),
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
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
    final selectedColor = ValueNotifier<String>(tag?.color ?? '#6B7280');
    final error = ValueNotifier<String?>(null);
    final saving = ValueNotifier<bool>(false);

    Future<void> save(BuildContext sheetContext) async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        error.value = l.tagNameRequired;
        return;
      }
      if (name.length > _maxTagNameLength) {
        error.value = l.tagNameTooLong(_maxTagNameLength);
        return;
      }
      final clash = existing.any(
        (other) =>
            other.id != tag?.id &&
            other.name.toLowerCase() == name.toLowerCase(),
      );
      if (clash) {
        error.value = l.tagDuplicate;
        return;
      }
      error.value = null;
      saving.value = true;
      try {
        if (tag == null) {
          await ref.read(createTagProvider)(
            name: name,
            color: selectedColor.value,
          );
        } else {
          await ref.read(updateTagProvider)(
            id: tag.id,
            name: name,
            color: selectedColor.value,
          );
        }
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      } catch (failure) {
        debugPrint('tags: save error: $failure');
        if (sheetContext.mounted) {
          saving.value = false;
          error.value = l.actionFailedRetry;
        }
      }
    }

    await showDsSheet<void>(
      context: context,
      title: tag == null ? l.createTag : l.editTag,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: error,
            builder: (ctx, message, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DsField(
                  label: l.tagName,
                  child: DsTextField(
                    controller: nameController,
                    autofocus: tag == null,
                    onSubmitted: (_) => save(ctx),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                    child: Text(
                      message,
                      style: AppTypography.small.copyWith(
                        color: context.ds.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: selectedColor,
            builder: (ctx, color, _) => ColorSwatchGrid(
              colors: _tagColors,
              selected: color,
              onSelected: (hex) => selectedColor.value = hex,
            ),
          ),
        ],
      ),
      actions: [
        const Spacer(),
        Builder(
          builder: (ctx) => DsButton(
            label: l.cancel,
            tone: DsButtonTone.ghost,
            onPressed: () => Navigator.of(ctx).maybePop(),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        ValueListenableBuilder<bool>(
          valueListenable: saving,
          builder: (ctx, isSaving, _) => DsButton(
            label: tag == null ? l.create : l.save,
            loading: isSaving,
            onPressed: () => save(ctx),
          ),
        ),
      ],
    );
  }
}
