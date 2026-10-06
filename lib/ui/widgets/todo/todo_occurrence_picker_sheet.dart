import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/task_allocations_section.dart';

class TodoOccurrencePickerSheet extends ConsumerStatefulWidget {
  final Todo todo;
  final int initialPage;
  final DateTime? anchorDate;

  const TodoOccurrencePickerSheet({
    super.key,
    required this.todo,
    this.initialPage = 1,
    this.anchorDate,
  });

  static Future<ProjectedTaskInstance?> show(
    BuildContext context, {
    required WidgetRef ref,
    required Todo todo,
    int initialPage = 1,
    DateTime? anchorDate,
  }) async {
    final l = AppLocalizations.of(context)!;
    Todo freshTodo;
    try {
      freshTodo = todo.syncId == null
          ? await ref.read(ensureTodoSyncIdentityProvider)(todo.id)
          : (await (ref.read(databaseProvider).select(ref.read(databaseProvider).todos)
                ..where((row) => row.id.equals(todo.id)))
              .getSingleOrNull() ??
            todo);
    } catch (_) {
      freshTodo = todo;
    }
    if (!context.mounted) return null;

    if (TodoRecurrence.fromTodo(freshTodo).isUnknownLegacy) {
      if (!TaskAllocationsSection.legacyRuleIsSupported(freshTodo.rrule ?? '')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.unsupportedLegacyRecurrence)),
        );
        return null;
      }
      final confirmed = await TaskAllocationsSection.confirmLegacyRecurrence(
        context,
        ref,
        freshTodo,
      );
      if (!confirmed || !context.mounted) return null;
      freshTodo = (await (ref.read(databaseProvider).select(ref.read(databaseProvider).todos)
                ..where((row) => row.id.equals(todo.id)))
              .getSingleOrNull() ??
            freshTodo);
      if (!context.mounted) return null;
    }

    return showDialog<ProjectedTaskInstance>(
      context: context,
      builder: (ctx) => TodoOccurrencePickerSheet(
        todo: freshTodo,
        initialPage: initialPage,
        anchorDate: anchorDate,
      ),
    );
  }

  @override
  ConsumerState<TodoOccurrencePickerSheet> createState() =>
      _TodoOccurrencePickerSheetState();
}

class _TodoOccurrencePickerSheetState
    extends ConsumerState<TodoOccurrencePickerSheet> {
  late int _historyPage;
  late Future<List<ProjectedTaskInstance>> _pageFuture;

  @override
  void initState() {
    super.initState();
    _historyPage = widget.initialPage;
    _pageFuture = _load();
  }

  Future<List<ProjectedTaskInstance>> _load() {
    final db = ref.read(databaseProvider);
    return loadOccurrencePage(
      db,
      widget.todo,
      historyPage: _historyPage,
      anchorDate: widget.anchorDate ?? DateTime.now(),
    );
  }

  void _changePage(int nextPage) {
    setState(() {
      _historyPage = nextPage;
      _pageFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l.selectTodoOccurrence),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => _changePage(_historyPage + 1),
                  child: Text(l.earlierThirtyDays),
                ),
                if (_historyPage > 1)
                  TextButton(
                    onPressed: () => _changePage(_historyPage - 1),
                    child: Text(l.newerOccurrences),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                l.occurrenceWindowHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: FutureBuilder<List<ProjectedTaskInstance>>(
                future: _pageFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${snapshot.error}'),
                    );
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.noOccurrencesAvailable),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return SimpleDialogOption(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(item),
                        child: ListTile(
                          title: Text(item.occurrence.displayLabel),
                          trailing: item.isCompleted
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
