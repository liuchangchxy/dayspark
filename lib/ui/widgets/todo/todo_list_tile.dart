import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';

class TodoListTile extends ConsumerWidget {
  final String summary;
  final bool isCompleted;
  final int priority;
  final int todoId;
  final DateTime? dueDate;
  final DateTime? startDate;
  final int? index;
  final Future<void> Function(String? occurrenceId, bool isCompleted) onToggle;
  final VoidCallback onTap;
  final Todo? todo;

  const TodoListTile({
    super.key,
    required this.summary,
    required this.isCompleted,
    required this.priority,
    required this.todoId,
    this.dueDate,
    this.startDate,
    this.index,
    required this.onToggle,
    required this.onTap,
    this.todo,
  });

  Color _priorityColor(Brightness brightness) {
    if (isCompleted) {
      return brightness == Brightness.dark
          ? AppColors.darkDisabled
          : AppColors.lightDisabled;
    }
    if (priority == 1) {
      return brightness == Brightness.dark
          ? AppColors.darkError
          : AppColors.lightError;
    }
    if (priority >= 2 && priority <= 4) {
      return brightness == Brightness.dark
          ? AppColors.darkWarning
          : AppColors.lightWarning;
    }
    return Colors.transparent;
  }

  String _dueDateLabel(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (dueDate == null) return l.noDueDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return l.overdue;
    if (diff == 0) return l.today;
    if (diff == 1) return l.tomorrow;

    // Show date range when startDate differs from dueDate by > 1 day
    if (startDate != null) {
      final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
      final span = due.difference(start).inDays;
      if (span > 1) {
        return '${DateFormatters.formatShortDate(start)} – ${DateFormatters.formatShortDate(due)}';
      }
    }

    return DateFormatters.formatShortDate(dueDate!);
  }

  bool get _isOverdue {
    if (dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final textColor = isCompleted
        ? theme.disabledColor
        : theme.textTheme.bodyMedium?.color;
    final tagsAsync = ref.watch(todoTagsProvider(todoId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (_priorityColor(theme.brightness) != Colors.transparent)
            Semantics(
              label: priority == 1 ? l.highPriority : l.mediumPriority,
              child: Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: _priorityColor(theme.brightness),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            )
          else
            const SizedBox(width: 4),
          const SizedBox(width: 8),
          if (index != null) ...[
            Container(
              width: 20,
              alignment: Alignment.center,
              child: Text(
                '${index! + 1}',
                style: TextStyle(
                  fontSize: AppTypography.caption.fontSize,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          SizedBox(
            width: 24,
            height: 24,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: isCompleted
                  ? Semantics(
                      button: true,
                      label: l.markIncomplete,
                      child: Checkbox(
                        value: true,
                        onChanged: (_) => _toggle(context, ref),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                  : Semantics(
                      button: true,
                      label: l.markComplete,
                      child: Checkbox(
                        value: false,
                        onChanged: (_) => _toggle(context, ref),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              button: true,
              hint: l.openTodoDetails,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: AppTypography.body.fontSize,
                          color: textColor,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                _dueDateLabel(context),
                                style: TextStyle(
                                  fontSize: AppTypography.caption.fontSize,
                                  color: _isOverdue
                                      ? theme.colorScheme.error
                                      : (dueDate == null
                                            ? theme.colorScheme.onSurfaceVariant
                                            : theme.textTheme.bodySmall?.color),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          tagsAsync.when(
                            data: (tags) => _tagDots(context, tags),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagDots(BuildContext context, List tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tags.take(3).map<Widget>((tag) {
        final color = ColorUtils.parseHex(tag.color);
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Semantics(
            label: AppLocalizations.of(context)!.tagWith(tag.name),
            child: Tooltip(
              message: tag.name,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final row = todo;
    if (row?.rrule == null) {
      await onToggle(null, !isCompleted);
      return;
    }
    if (row!.status == 'COMPLETED') {
      await onToggle(null, false);
      return;
    }
    final l = AppLocalizations.of(context)!;
    try {
      final identifiedTodo = row.syncId == null
          ? await ref.read(ensureTodoSyncIdentityProvider)(todoId)
          : row;
      if (!context.mounted) return;
      final now = DateTime.now();
      final expansion = expandTodoOccurrences(
        identifiedTodo,
        startInclusive: DateTime(now.year, now.month, now.day),
        endExclusive: DateTime(now.year, now.month, now.day + 91),
        maxOccurrences: 100,
      );
      if (expansion.status != TodoOccurrenceExpansionStatus.expanded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.legacyRecurrenceRequiresConfirmation)),
        );
        return;
      }
      final db = ref.read(databaseProvider);
      Future<List<TodoOccurrenceStateProjection>> loadPage(int page) async {
        final today = DateTime(now.year, now.month, now.day);
        final past = expandTodoOccurrences(
          identifiedTodo,
          startInclusive: today.subtract(Duration(days: 30 * page)),
          endExclusive: today.subtract(Duration(days: 30 * (page - 1))),
          maxOccurrences: 100,
        );
        final future = page == 1
            ? expansion.occurrences
            : const <TodoOccurrence>[];
        final window = TodoOccurrenceExpansion(
          TodoOccurrenceExpansionStatus.expanded,
          [...past.occurrences, ...future],
        );
        return projectTodoOccurrenceStates(db, window);
      }

      var historyPage = 1;
      var pageFuture = loadPage(historyPage);
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
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
                          onPressed: () => setDialogState(() {
                            historyPage++;
                            pageFuture = loadPage(historyPage);
                          }),
                          child: Text(l.earlierThirtyDays),
                        ),
                        if (historyPage > 1)
                          TextButton(
                            onPressed: () => setDialogState(() {
                              historyPage--;
                              pageFuture = loadPage(historyPage);
                            }),
                            child: Text(l.newerOccurrences),
                          ),
                      ],
                    ),
                    Flexible(
                      child: FutureBuilder<List<TodoOccurrenceStateProjection>>(
                        future: pageFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Text('${snapshot.error}');
                          }
                          final pageItems =
                              (snapshot.data ?? const [])
                                  .where((item) => item.status != 'skipped')
                                  .toList()
                                ..sort(
                                  (left, right) => left
                                      .occurrence
                                      .nominalAnchor
                                      .canonical
                                      .compareTo(
                                        right
                                            .occurrence
                                            .nominalAnchor
                                            .canonical,
                                      ),
                                );
                          if (pageItems.isEmpty) {
                            return Text(l.noOccurrencesAvailable);
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: pageItems.length,
                            itemBuilder: (context, index) {
                              final item = pageItems[index];
                              final occurrenceId = item.occurrence.occurrenceId;
                              return ListTile(
                                title: Text(
                                  item.occurrence.nominalAnchor.canonical
                                      .replaceFirst('T', '  '),
                                ),
                                trailing: item.status == 'completed'
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () =>
                                    Navigator.of(context).pop(occurrenceId),
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
          },
        ),
      );
      if (!context.mounted) return;
      if (selected != null) {
        final projected = await pageFuture;
        final completed = projected.any(
          (item) =>
              item.occurrence.occurrenceId == selected &&
              item.status == 'completed',
        );
        await onToggle(selected, !completed);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
