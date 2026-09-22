import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/utils/date_formatters.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.trash),
        actions: [
          if (hasAny)
            IconButton(
              icon: const Icon(CupertinoIcons.trash),
              tooltip: l.emptyTrash,
              onPressed: () => _confirmEmptyTrash(context, ref, l),
            ),
        ],
      ),
      body: deletedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error('$e'))),
        data: (todoRows) => deletedEventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(l.error('$e'))),
          data: (eventRows) {
            if (todoRows.isEmpty && eventRows.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.trash,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.trashEmpty,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('todo-${todo.id}'),
      background: Container(
        color: theme.colorScheme.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: Icon(
          CupertinoIcons.arrow_uturn_left,
          color: theme.colorScheme.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(CupertinoIcons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await ref.read(restoreTodoProvider)(todo.id);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.restoreTodo)));
          }
          return true;
        } else {
          return _confirmPermanentDelete(context, l);
        }
      },
      child: ListTile(
        leading: const Icon(CupertinoIcons.checkmark_rectangle, size: 20),
        title: Text(
          todo.summary,
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ),
        subtitle: Text(
          todo.deletedAt != null
              ? DateFormatters.formatDateTime(todo.deletedAt!)
              : '',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _restoreDeleteActions(
          context,
          ref,
          l,
          onRestore: () => ref.read(restoreTodoProvider)(todo.id),
          onDelete: () =>
              ref.read(permanentDeleteTodoProvider)(todo.id),
        ),
      ),
    );
  }

  Widget _buildEventTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    Event event,
  ) {
    return Dismissible(
      key: ValueKey('event-${event.id}'),
      background: Container(
        color: Theme.of(context).colorScheme.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: Icon(
          CupertinoIcons.arrow_uturn_left,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(CupertinoIcons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await ref.read(restoreEventProvider)(event.id);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.restoreTodo)));
          }
          return true;
        } else {
          return _confirmPermanentDelete(context, l);
        }
      },
      child: ListTile(
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
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _restoreDeleteActions(
          context,
          ref,
          l,
          onRestore: () => ref.read(restoreEventProvider)(event.id),
          onDelete: () => ref
              .read(hardDeleteEventWithChildrenProvider)(event.id),
        ),
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
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
      context: context,
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
      context: context,
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
