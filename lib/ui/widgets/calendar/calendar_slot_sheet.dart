import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class CalendarSlotSheet extends StatefulWidget {
  final DateTimeRange range;
  final VoidCallback onCreateEvent;
  final Future<void> Function(Todo todo) onScheduleTodo;
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
    required Future<void> Function(Todo todo) onScheduleTodo,
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
  State<CalendarSlotSheet> createState() => _CalendarSlotSheetState();
}

class _CalendarSlotSheetState extends State<CalendarSlotSheet> {
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
                      return ListTile(
                        leading: Icon(
                          CupertinoIcons.circle,
                          size: 20,
                          color: theme.colorScheme.outline,
                        ),
                        title: Text(todo.summary),
                        subtitle: todo.dueDate != null
                            ? Text(
                                '${l.dueDate}: ${DateFormatters.formatShortDate(todo.dueDate!)}',
                                style: AppTypography.caption,
                              )
                            : null,
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onScheduleTodo(todo);
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
}
