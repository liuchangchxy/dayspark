import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/todo/legacy_recurrence_dialog.dart';

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
          : (await (ref
                        .read(databaseProvider)
                        .select(ref.read(databaseProvider).todos)
                      ..where((row) => row.id.equals(todo.id)))
                    .getSingleOrNull() ??
                todo);
    } catch (_) {
      freshTodo = todo;
    }
    if (!context.mounted) return null;

    if (TodoRecurrence.fromTodo(freshTodo).isUnknownLegacy) {
      if (!legacyRuleIsSupported(freshTodo.rrule ?? '')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.unsupportedLegacyRecurrence)));
        return null;
      }
      final confirmed = await confirmLegacyRecurrence(context, ref, freshTodo);
      if (!confirmed || !context.mounted) return null;
      freshTodo =
          (await (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).todos)
                ..where((row) => row.id.equals(todo.id)))
              .getSingleOrNull() ??
          freshTodo);
      if (!context.mounted) return null;
    }

    return showDialog<ProjectedTaskInstance>(
    animationStyle: AnimationStyle.noAnimation, context: context,
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

    return DsDialog(
      title: l.selectTodoOccurrence,
      width: 440,
      actions: [
        const Spacer(),
        DsButton(
          label: l.cancel,
          tone: DsButtonTone.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DsButton(
                label: l.earlierThirtyDays,
                tone: DsButtonTone.ghost,
                small: true,
                onPressed: () => _changePage(_historyPage + 1),
              ),
              if (_historyPage > 1) ...[
                const SizedBox(width: AppSpacing.s2),
                DsButton(
                  label: l.newerOccurrences,
                  tone: DsButtonTone.ghost,
                  small: true,
                  onPressed: () => _changePage(_historyPage - 1),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.occurrenceWindowHint,
            style: AppTypography.caption.copyWith(color: context.ds.ink3),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<ProjectedTaskInstance>>(
            future: _pageFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                // A raw exception here names tables and types the user
                // never chose; the log keeps the detail.
                debugPrint('occurrence picker: load error: ${snapshot.error}');
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.error),
                );
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.noOccurrencesAvailable),
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    DsSettingRow(
                      label: formatOccurrenceAnchor(
                        context,
                        item.occurrence.displayLabel,
                      ),
                      trailing: item.isCompleted
                          ? Icon(
                              CupertinoIcons.checkmark,
                              size: 16,
                              color: context.ds.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
