import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

class CalendarSlotSheet extends ConsumerStatefulWidget {
  final DateTimeRange range;
  final VoidCallback onCreateEvent;
  final Function onScheduleTodo;
  final Future<List<Todo>> Function() loadSchedulableTodos;

  const CalendarSlotSheet({
    super.key,
    required this.range,
    required this.onCreateEvent,
    required this.onScheduleTodo,
    required this.loadSchedulableTodos,
  });

  static Future<void> show({
    required BuildContext context,
    required DateTimeRange range,
    required VoidCallback onCreateEvent,
    required Function onScheduleTodo,
    required Future<List<Todo>> Function() loadSchedulableTodos,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => CalendarSlotSheet(
        range: range,
        onCreateEvent: onCreateEvent,
        onScheduleTodo: onScheduleTodo,
        loadSchedulableTodos: loadSchedulableTodos,
      ),
    );
  }

  @override
  ConsumerState<CalendarSlotSheet> createState() => _CalendarSlotSheetState();
}

class _CalendarSlotSheetState extends ConsumerState<CalendarSlotSheet> {
  bool _showingTodoPicker = false;
  List<Todo>? _candidates;
  bool _loading = false;

  Future<void> _openTodoPicker() async {
    setState(() {
      _showingTodoPicker = true;
      _loading = true;
    });
    try {
      final list = await widget.loadSchedulableTodos();
      if (mounted) {
        setState(() {
          _candidates = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _candidates = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rangeText = DateFormatters.formatTaskAllocationRange(
      widget.range.start,
      widget.range.end,
      includeDate: true,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (!_showingTodoPicker) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  rangeText,
                  style: AppTypography.headline.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                leading: const Icon(CupertinoIcons.calendar_badge_plus),
                title: Text(l.createEventOption),
                subtitle: Text(l.createEventDesc),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onCreateEvent();
                },
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.clock),
                title: Text(l.scheduleTodo),
                subtitle: Text(l.scheduleTodoDesc),
                onTap: _openTodoPicker,
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.back),
                      onPressed: () => setState(() => _showingTodoPicker = false),
                    ),
                    Expanded(
                      child: Text(
                        l.selectTodoToSchedule,
                        style: AppTypography.title.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_candidates == null || _candidates!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: Text(
                      l.noSchedulableTodos,
                      style: AppTypography.body.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _candidates!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final todo = _candidates![i];
                      final isRecurring =
                          todo.rrule != null && todo.rrule!.isNotEmpty;
                      return ListTile(
                        leading: Icon(
                          isRecurring
                              ? CupertinoIcons.repeat
                              : CupertinoIcons.circle,
                          size: 20,
                          color: theme.colorScheme.outline,
                        ),
                        title: Text(todo.summary),
                        subtitle: Text(
                          isRecurring
                              ? l.recurringTask
                              : (todo.dueDate != null
                                  ? '${l.dueDate}: ${DateFormatters.formatShortDate(todo.dueDate!)}'
                                  : l.noDueDate),
                          style: AppTypography.caption,
                        ),
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          if (isRecurring) {
                            final selected =
                                await TodoOccurrencePickerSheet.show(
                              context,
                              ref: ref,
                              todo: todo,
                              anchorDate: widget.range.start,
                            );
                            if (selected == null || !mounted) return;
                            navigator.pop();
                            await _invokeScheduleTodo(
                              todo,
                              selected.occurrenceId,
                            );
                          } else {
                            navigator.pop();
                            await _invokeScheduleTodo(todo);
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _invokeScheduleTodo(Todo todo, [String? occurrenceId]) async {
    final fn = widget.onScheduleTodo;
    if (fn is Future<void> Function(Todo, String?)) {
      await fn(todo, occurrenceId);
    } else if (fn is Future<void> Function(Todo, [String?])) {
      await fn(todo, occurrenceId);
    } else if (fn is Future<void> Function(Todo, {String? occurrenceId})) {
      await fn(todo, occurrenceId: occurrenceId);
    } else if (fn is Future<void> Function(Todo)) {
      await fn(todo);
    } else {
      try {
        await Function.apply(fn, [todo, occurrenceId]);
      } catch (_) {
        await Function.apply(fn, [todo]);
      }
    }
  }
}
