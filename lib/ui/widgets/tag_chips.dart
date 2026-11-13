import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:go_router/go_router.dart';

/// A row of tag chips that toggles tag assignment.
///
/// Pass [selectedIds] to edit a form draft instead: the chips then change only
/// the draft, and the form decides when the associations are written.
class TagChips extends ConsumerWidget {
  const TagChips({
    super.key,
    this.parentType,
    this.parentId,
    this.assignedTags = const [],
    this.selectedIds,
    this.onSelectedIdsChanged,
  }) : assert(
         onSelectedIdsChanged != null || parentId != null,
         'either a saved parent or a draft selection is required',
       );

  final String? parentType; // 'event' or 'todo'
  final int? parentId;
  final List<Tag> assignedTags;

  final Set<int>? selectedIds;
  final ValueChanged<Set<int>>? onSelectedIdsChanged;

  bool get _isDraft => onSelectedIdsChanged != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return ref
        .watch(tagsProvider)
        .when(
          data: (allTags) {
            if (allTags.isEmpty) {
              return DsButton(
                label: l.createTag,
                icon: CupertinoIcons.add,
                tone: DsButtonTone.ghost,
                small: true,
                onPressed: () => context.push('/tags'),
              );
            }
            final assigned = _isDraft
                ? (selectedIds ?? const <int>{})
                : assignedTags.map((tag) => tag.id).toSet();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tags,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.ds.ink2,
                  ),
                ),
                const SizedBox(height: AppSpacing.s1),
                Wrap(
                  spacing: AppSpacing.s1 + 2,
                  runSpacing: AppSpacing.s1 + 2,
                  children: allTags.map((tag) {
                    final isAssigned = assigned.contains(tag.id);
                    final tagColor = ColorUtils.parseHex(tag.color);
                    return DsChip(
                      label: tag.name,
                      leading: DsDot(color: tagColor),
                      selected: isAssigned,
                      onTap: () => _toggle(context, ref, tag.id, !isAssigned),
                    );
                  }).toList(),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
  }

  void _toggle(BuildContext context, WidgetRef ref, int tagId, bool selected) {
    if (_isDraft) {
      final next = {...(selectedIds ?? const <int>{})};
      if (selected) {
        next.add(tagId);
      } else {
        next.remove(tagId);
      }
      onSelectedIdsChanged!(next);
      return;
    }
    if (parentType == 'event') {
      if (selected) {
        ref.read(addTagToEventProvider)(eventId: parentId!, tagId: tagId);
      } else {
        ref.read(removeTagFromEventProvider)(eventId: parentId!, tagId: tagId);
      }
      return;
    }
    if (selected) {
      ref.read(addTagToTodoProvider)(todoId: parentId!, tagId: tagId);
    } else {
      ref.read(removeTagFromTodoProvider)(todoId: parentId!, tagId: tagId);
    }
  }
}
