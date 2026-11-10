import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// Fast capture matching DESIGN.md and IMPLEMENTATION_HANDOFF:
/// Title, Deadline, Planned Execution, Reminder;
/// Expandable "More Options" without losing typed title.
Future<void> showTodoQuickCreateSheet(
  BuildContext context, {
  DateTime? dueDate,
}) {
  if (isWorkspaceLayout(context)) {
    return showDialog<void>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _QuickCreateForm(initialDueDate: dueDate),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _QuickCreateForm(initialDueDate: dueDate),
      ),
    ),
  );
}

class _QuickCreateForm extends ConsumerStatefulWidget {
  const _QuickCreateForm({this.initialDueDate});

  final DateTime? initialDueDate;

  @override
  ConsumerState<_QuickCreateForm> createState() => _QuickCreateFormState();
}

class _QuickCreateFormState extends ConsumerState<_QuickCreateForm> {
  final _controller = TextEditingController();
  final _descController = TextEditingController();
  late DateTime? _dueDate = widget.initialDueDate;
  DateTime? _plannedDate;
  int _priority = 0;
  int? _selectedCalendarId;
  final Set<int> _selectedTagIds = {};
  bool _showMore = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _saving) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (!mounted) return;
      if (calendars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.noCalendar)),
        );
        setState(() => _saving = false);
        return;
      }
      final targetCalId = _selectedCalendarId ?? calendars.first.id;
      final newTodoId = await ref.read(createTodoProvider)(
        calendarId: targetCalId,
        summary: title,
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
        priority: _priority,
        status: 'NEEDS-ACTION',
        dueDate: _dueDate,
      );

      // If tags selected
      for (final tagId in _selectedTagIds) {
        await ref.read(addTagToTodoProvider)(todoId: newTodoId, tagId: tagId);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      debugPrint('quick create: save failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.actionFailedRetry)),
      );
    }
  }

  Future<void> _pickDeadline() async {
    final picked = await pickDeadline(
      context,
      initial: _dueDate ?? DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Future<void> _pickPlannedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) {
      setState(() => _plannedDate = picked);
    }
  }

  void _openFullForm() {
    final title = _controller.text.trim();
    final due = _dueDate;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();

    final query = <String, String>{};
    if (title.isNotEmpty) query['title'] = title;
    if (due != null) query['due'] = due.millisecondsSinceEpoch.toString();

    final uri = Uri(path: '/todo/new', queryParameters: query.isEmpty ? null : query);
    router.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final calendarsAsync = ref.watch(calendarsProvider);
    final allTagsAsync = ref.watch(tagsProvider);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title input
            TextField(
              key: const ValueKey('todo-quick-create-title'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: AppTypography.title,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: l.quickCreateHint,
                border: InputBorder.none,
                hintStyle: AppTypography.title.copyWith(
                  color: context.semantic.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // First screen action chips: Deadline & Planned execution
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                InputChip(
                  avatar: Icon(
                    CupertinoIcons.flag,
                    size: 14,
                    color: _dueDate != null
                        ? context.semantic.warm
                        : context.semantic.textSecondary,
                  ),
                  label: Text(
                    _dueDate != null
                        ? l.deadlinePrefix(DateFormatters.formatDate(_dueDate!))
                        : l.setDeadline,
                    style: AppTypography.caption.copyWith(
                      color: _dueDate != null ? context.semantic.warm : null,
                    ),
                  ),
                  onPressed: _pickDeadline,
                  onDeleted: _dueDate != null ? () => setState(() => _dueDate = null) : null,
                ),
                ActionChip(
                  avatar: Icon(
                    CupertinoIcons.calendar,
                    size: 14,
                    color: _plannedDate != null
                        ? Theme.of(context).colorScheme.primary
                        : context.semantic.textSecondary,
                  ),
                  label: Text(
                    _plannedDate != null
                        ? DateFormatters.formatDate(_plannedDate!)
                        : l.executionSchedule,
                    style: AppTypography.caption.copyWith(
                      color: _plannedDate != null
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  onPressed: _pickPlannedDate,
                ),
              ],
            ),

            // Progressive disclosure: More options
            if (_showMore) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),

              // Calendar selector
              calendarsAsync.when(
                data: (cals) => Row(
                  children: [
                    Text(l.calendarField, style: AppTypography.caption),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: DropdownButton<int>(
                        value: _selectedCalendarId ?? (cals.isNotEmpty ? cals.first.id : null),
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: cals.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, style: AppTypography.body),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCalendarId = val);
                        },
                      ),
                    ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Priority selector
              Row(
                children: [
                  Text(l.priority, style: AppTypography.caption),
                  const SizedBox(width: AppSpacing.md),
                  ChoiceChip(
                    label: Text(l.priorityNone),
                    selected: _priority == 0,
                    onSelected: (s) => setState(() => _priority = 0),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ChoiceChip(
                    label: Text(l.mediumPriority),
                    selected: _priority == 2,
                    onSelected: (s) => setState(() => _priority = 2),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ChoiceChip(
                    label: Text(l.highPriority),
                    selected: _priority == 1,
                    onSelected: (s) => setState(() => _priority = 1),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Tags
              allTagsAsync.when(
                data: (tags) => tags.isEmpty
                    ? const SizedBox.shrink()
                    : Wrap(
                        spacing: AppSpacing.xs,
                        children: tags.map((tag) {
                          final selected = _selectedTagIds.contains(tag.id);
                          return FilterChip(
                            label: Text(tag.name),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedTagIds.add(tag.id);
                                } else {
                                  _selectedTagIds.remove(tag.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Description
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _descController,
                maxLines: 2,
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: l.description,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.sm),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            // Bottom Action Row
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    if (!_showMore) {
                      setState(() => _showMore = true);
                    } else {
                      _openFullForm();
                    }
                  },
                  child: Text(!_showMore ? l.moreOptions : l.openTodoDetails),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
