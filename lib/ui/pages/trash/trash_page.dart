import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final deletedAsync = ref.watch(deletedTodosProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.trash),
        actions: [
          deletedAsync.when(
            data: (todos) {
              if (todos.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(CupertinoIcons.trash),
                tooltip: l.emptyTrash,
                onPressed: () => _confirmEmptyTrash(context, ref, l),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: deletedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.error('$e'))),
        data: (todos) {
          if (todos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.trash,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.trashEmpty,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return Dismissible(
                key: ValueKey(todo.id),
                background: Container(
                  color: Colors.blue,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  child: const Icon(
                    CupertinoIcons.arrow_uturn_left,
                    color: Colors.white,
                  ),
                ),
                secondaryBackground: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(CupertinoIcons.delete, color: Colors.white),
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
                  title: Text(
                    todo.summary,
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Text(
                    todo.deletedAt != null
                        ? '${todo.deletedAt!.month}/${todo.deletedAt!.day} ${todo.deletedAt!.hour}:${todo.deletedAt!.minute.toString().padLeft(2, '0')}'
                        : '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.arrow_uturn_left,
                          size: 18,
                        ),
                        tooltip: l.restoreTodo,
                        onPressed: () async {
                          await ref.read(restoreTodoProvider)(todo.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.restoreTodo)),
                            );
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
                          final confirmed = await _confirmPermanentDelete(
                            context,
                            l,
                          );
                          if (confirmed) {
                            await ref.read(permanentDeleteTodoProvider)(
                              todo.id,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
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
