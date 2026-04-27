import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';

/// A row of tag chips that can toggle tag assignment.
class TagChips extends ConsumerWidget {
  final String parentType; // 'event' or 'todo'
  final int parentId;
  final List<Tag> assignedTags;

  const TagChips({
    super.key,
    required this.parentType,
    required this.parentId,
    required this.assignedTags,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTagsAsync = ref.watch(tagsProvider);

    return allTagsAsync.when(
      data: (allTags) {
        if (allTags.isEmpty) return const SizedBox.shrink();

        final assignedIds = assignedTags.map((t) => t.id).toSet();

        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: allTags.map((tag) {
            final isAssigned = assignedIds.contains(tag.id);
            final tagColor = ColorUtils.parseHex(tag.color);
            return FilterChip(
              label: Text(tag.name),
              avatar: CircleAvatar(radius: 6, backgroundColor: tagColor),
              selected: isAssigned,
              selectedColor: tagColor.withValues(alpha: 0.3),
              checkmarkColor: tagColor,
              onSelected: (selected) {
                if (parentType == 'event') {
                  if (selected) {
                    ref.read(addTagToEventProvider)(
                      eventId: parentId,
                      tagId: tag.id,
                    );
                  } else {
                    ref.read(removeTagFromEventProvider)(
                      eventId: parentId,
                      tagId: tag.id,
                    );
                  }
                } else {
                  if (selected) {
                    ref.read(addTagToTodoProvider)(
                      todoId: parentId,
                      tagId: tag.id,
                    );
                  } else {
                    ref.read(removeTagFromTodoProvider)(
                      todoId: parentId,
                      tagId: tag.id,
                    );
                  }
                }
              },
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
