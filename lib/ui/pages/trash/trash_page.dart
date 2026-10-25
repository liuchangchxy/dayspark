import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/widgets/empty_state.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final deletedAsync = ref.watch(deletedTodosProvider);
    final deletedEventsAsync = ref.watch(deletedEventsProvider);
    final todos = deletedAsync.valueOrNull ?? [];
    final events = deletedEventsAsync.valueOrNull ?? [];
    final hasAny = todos.isNotEmpty || events.isNotEmpty;

    return WorkspacePage(
      title: l.trash,
      maxContentWidth: 720,
      actions: [
        if (hasAny)
          IconButton(
            icon: const Icon(CupertinoIcons.trash, size: 18),
            tooltip: l.emptyTrash,
            onPressed: () => _confirmEmptyTrash(context, ref, l),
            visualDensity: VisualDensity.compact,
          ),
      ],
      child: deletedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error)),
        data: (todoRows) => deletedEventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(l.error)),
          data: (eventRows) {
            if (todoRows.isEmpty && eventRows.isEmpty) {
              return EmptyState(
                icon: CupertinoIcons.trash,
                title: l.trashEmpty,
                hint: l.trashEmptyHint,
                action: FilledButton(
                  // "Back to todos" has to land on Todos — the Home root
                  // defaults to whichever tab was last open.
                  onPressed: () {
                    ref.read(workspaceTabProvider.notifier).state =
                        AppTab.todos;
                    context.go('/?tab=2');
                  },
                  child: Text(l.trashEmptyAction),
                ),
              );
            }
            return CustomScrollView(
              slivers: [
                if (todoRows.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _sectionHeader(context, l.todos, todoRows.length),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildTodoTile(context, ref, l, todoRows[index]),
                      childCount: todoRows.length,
                    ),
                  ),
                ],
                if (eventRows.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _sectionHeader(context, l.events, eventRows.length),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildEventTile(context, ref, l, eventRows[index]),
                      childCount: eventRows.length,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTodoTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Todo todo,
  ) {
    // No swipe-to-delete: on a desktop pointer a swipe is a mistimed drag, and
    // the row already carries two explicit buttons.
    return ListTile(
      key: ValueKey('trash-todo-${todo.id}'),
      leading: const Icon(CupertinoIcons.checkmark_rectangle, size: 20),
      title: Text(
        todo.summary,
        style: const TextStyle(decoration: TextDecoration.lineThrough),
      ),
      subtitle: Text(
        todo.deletedAt != null
            ? DateFormatters.formatDateTime(todo.deletedAt!)
            : '',
        style: TextStyle(fontSize: AppTypography.caption.fontSize),
      ),
      trailing: _restoreDeleteActions(
        context,
        ref,
        l,
        onRestore: () => ref.read(restoreTodoProvider)(todo.id),
        onDelete: () => ref.read(permanentDeleteTodoProvider)(todo.id),
      ),
    );
  }

  Widget _buildEventTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Event event,
  ) {
    return ListTile(
      key: ValueKey('trash-event-${event.id}'),
      leading: const Icon(CupertinoIcons.calendar_badge_plus, size: 20),
      title: Text(
        event.summary,
        style: const TextStyle(decoration: TextDecoration.lineThrough),
      ),
      subtitle: Text(
        event.deletedAt != null
            ? '${DateFormatters.formatDateTime(event.startDt)} · '
                  '${DateFormatters.formatDateTime(event.deletedAt!)}'
            : '',
        style: TextStyle(fontSize: AppTypography.caption.fontSize),
      ),
      trailing: _restoreDeleteActions(
        context,
        ref,
        l,
        onRestore: () => ref.read(restoreEventProvider)(event.id),
        onDelete: () => ref.read(hardDeleteEventWithChildrenProvider)(event.id),
      ),
    );
  }

  Widget _restoreDeleteActions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l, {
    required Future<void> Function() onRestore,
    required Future<void> Function() onDelete,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 18),
          tooltip: l.restoreTodo,
          onPressed: () async {
            await onRestore();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l.restoreTodo)));
            }
          },
        ),
        IconButton(
          icon: Icon(
            CupertinoIcons.delete,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: l.permanentDelete,
          onPressed: () async {
            final confirmed = await _confirmPermanentDelete(context, l);
            if (confirmed) {
              await onDelete();
            }
          },
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.title.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: TextStyle(
              fontSize: AppTypography.caption.fontSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmPermanentDelete(
    BuildContext context,
    AppLocalizations l,
  ) async {
    final result = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation, context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.permanentDelete),
        content: Text(l.confirmPermanentDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l.permanentDelete),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _confirmEmptyTrash(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) {
    showDialog(
    animationStyle: AnimationStyle.noAnimation, context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.emptyTrash),
        content: Text(l.confirmEmptyTrash),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(emptyTrashProvider)();
              await ref.read(emptyEventTrashProvider)();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l.emptyTrash),
          ),
        ],
      ),
    );
  }
}
