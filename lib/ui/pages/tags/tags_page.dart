import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/calendar/frozen_calendar_colors.dart';
import 'package:dayspark/ui/pages/settings/settings_ui.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';

const int _maxTagNameLength = 50;

enum _TagSubpage { list, newTag, editTag }

class TagsPage extends ConsumerStatefulWidget {
  const TagsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends ConsumerState<TagsPage> {
  _TagSubpage _subpage = _TagSubpage.list;
  Tag? _editingTag;

  final TextEditingController _nameController = TextEditingController();
  String _selectedColor = FrozenPalette.hexColors.first;
  String? _errorMessage;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startNewTag() {
    setState(() {
      _subpage = _TagSubpage.newTag;
      _editingTag = null;
      _nameController.text = '';
      _selectedColor = FrozenPalette.hexColors.first;
      _errorMessage = null;
      _saving = false;
    });
  }

  void _startEditTag(Tag tag) {
    setState(() {
      _subpage = _TagSubpage.editTag;
      _editingTag = tag;
      _nameController.text = tag.name;
      _selectedColor = tag.color.isNotEmpty ? tag.color : FrozenPalette.hexColors.first;
      _errorMessage = null;
      _saving = false;
    });
  }

  int _countFor(WidgetRef ref, int tagId) {
    final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];
    final todoTagMap = ref.watch(todoTagIdsMapProvider).valueOrNull ?? const {};
    final events = ref.watch(allEventsProvider).valueOrNull ?? const [];
    final eventTagMap =
        ref.watch(eventTagIdsMapProvider).valueOrNull ?? const {};
    var count = 0;
    for (final todo in todos) {
      if (todo.status == 'COMPLETED' || todo.status == 'CANCELLED') continue;
      if (todoTagMap[todo.id]?.contains(tagId) ?? false) count++;
    }
    for (final event in events) {
      if (eventTagMap[event.id]?.contains(tagId) ?? false) count++;
    }
    return count;
  }

  Future<void> _saveTag(AppLocalizations l) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = l.tagNameRequired);
      return;
    }
    if (name.length > _maxTagNameLength) {
      setState(() => _errorMessage = l.tagNameTooLong(_maxTagNameLength));
      return;
    }
    final existing = ref.read(tagsProvider).valueOrNull ?? const <Tag>[];
    final clash = existing.any(
      (other) =>
          other.id != _editingTag?.id &&
          other.name.toLowerCase() == name.toLowerCase(),
    );
    if (clash) {
      setState(() => _errorMessage = l.tagDuplicate);
      return;
    }

    setState(() {
      _errorMessage = null;
      _saving = true;
    });

    try {
      if (_editingTag == null) {
        await ref.read(createTagProvider)(
          name: name,
          color: _selectedColor,
        );
      } else {
        await ref.read(updateTagProvider)(
          id: _editingTag!.id,
          name: name,
          color: _selectedColor,
        );
      }
      if (mounted) {
        setState(() => _subpage = _TagSubpage.list);
      }
    } catch (failure) {
      debugPrint('tags: save error: $failure');
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = l.actionFailedRetry;
        });
      }
    }
  }

  Future<void> _confirmDeleteTag(
    BuildContext context,
    AppLocalizations l,
    Tag tag,
    int count,
  ) async {
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
        child: Text(
          '${l.tagDeleteBody(tag.name)}\n${l.dayItemCount(count)}',
          style: AppTypography.body.copyWith(color: context.ds.ink2),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(deleteTagProvider)(tag.id);
      if (mounted) setState(() => _subpage = _TagSubpage.list);
    } catch (error) {
      debugPrint('tags: delete error: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    Widget body;
    switch (_subpage) {
      case _TagSubpage.newTag:
        body = _buildNewTagView(context, l);
        break;
      case _TagSubpage.editTag:
        body = _buildEditTagView(context, l, _editingTag!);
        break;
      case _TagSubpage.list:
        body = _buildListView(context, l);
        break;
    }

    if (widget.embedded) {
      return body;
    }

    return WorkspacePage(
      title: l.manageTags,
      maxContentWidth: 720,
      child: body,
    );
  }

  Widget _buildListView(BuildContext context, AppLocalizations l) {
    final ds = context.ds;
    final tagsAsync = ref.watch(tagsProvider);
    return tagsAsync.when(
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
              onPressed: _startNewTag,
            ),
          );
        }

        final tagRows = [
          for (final tag in tags)
            DsSettingRow(
              label: tag.name,
              value: l.dayItemCount(_countFor(ref, tag.id)),
              leading: DsDot(
                color: ColorUtils.parseHex(tag.color),
                size: 8,
              ),
              trailing: const Icon(
                CupertinoIcons.chevron_right,
                size: 11,
                color: SpecTokens.faint,
              ),
              onTap: () => _startEditTag(tag),
            ),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsGroup(margin: EdgeInsets.zero, children: tagRows),
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
                onPressed: _startNewTag,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNewTagView(BuildContext context, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.createTag,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SpecTokens.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.tagEmptyHint,
          style: const TextStyle(
            fontSize: 11,
            height: 1.55,
            color: SpecTokens.faint,
          ),
        ),
        const SizedBox(height: 12),
        IoCard(
          title: l.tagName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DsTextField(
                controller: _nameController,
                autofocus: true,
                onSubmitted: (_) => _saveTag(l),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 12, color: SpecTokens.red),
                  ),
                ),
            ],
          ),
        ),
        IoCard(
          title: l.calendarColorLabel,
          child: _buildColorChips(),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DsButton(
              label: l.cancel,
              tone: DsButtonTone.secondary,
              onPressed: () => setState(() => _subpage = _TagSubpage.list),
            ),
            const SizedBox(width: 8),
            DsButton(
              label: l.create,
              tone: DsButtonTone.primary,
              loading: _saving,
              onPressed: () => _saveTag(l),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditTagView(BuildContext context, AppLocalizations l, Tag tag) {
    final count = _countFor(ref, tag.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.editTag,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SpecTokens.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.tagEditDesc(tag.name),
          style: const TextStyle(
            fontSize: 11,
            height: 1.55,
            color: SpecTokens.faint,
          ),
        ),
        const SizedBox(height: 12),
        IoCard(
          title: l.tagName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DsTextField(
                controller: _nameController,
                autofocus: false,
                onSubmitted: (_) => _saveTag(l),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 12, color: SpecTokens.red),
                  ),
                ),
            ],
          ),
        ),
        IoCard(
          title: l.calendarColorLabel,
          child: _buildColorChips(),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DsButton(
              label: l.cancel,
              tone: DsButtonTone.secondary,
              onPressed: () => setState(() => _subpage = _TagSubpage.list),
            ),
            const SizedBox(width: 8),
            DsButton(
              label: '${l.deleteTag} ($count)',
              tone: DsButtonTone.danger,
              onPressed: () => _confirmDeleteTag(context, l, tag, count),
            ),
            const SizedBox(width: 8),
            DsButton(
              label: l.save,
              tone: DsButtonTone.primary,
              loading: _saving,
              onPressed: () => _saveTag(l),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorChips() {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in FrozenPalette.hexColors)
          FocusableTap(
            onTap: () => setState(() => _selectedColor = hex),
            semanticsLabel: _colorLabel(l, hex),
            selected: _selectedColor.toUpperCase() == hex.toUpperCase(),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 28,
              height: 24,
              decoration: BoxDecoration(
                color: ColorUtils.parseHex(hex),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _selectedColor.toUpperCase() == hex.toUpperCase()
                      ? SpecTokens.ink
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: _selectedColor.toUpperCase() == hex.toUpperCase()
                  ? const Center(
                      child: Icon(
                        CupertinoIcons.checkmark,
                        size: 12,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  String _colorLabel(AppLocalizations l, String hex) {
    return switch (hex.toUpperCase()) {
      '#4F7BBF' => l.colorBlue,
      '#6A9464' => l.colorGreen,
      '#C4794A' => l.colorOrange,
      '#6C6FA8' => l.colorPurple,
      '#A98B4F' => l.colorAmber,
      '#8A8A82' => l.colorGray,
      _ => hex,
    };
  }
}
