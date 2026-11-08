import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// Fast capture: a title, an optional visible deadline, and save.
///
/// The deadline is never inherited silently. If a context supplies one it is
/// rendered as an editable chip before anything is written.
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
          constraints: const BoxConstraints(maxWidth: 420),
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
  late DateTime? _dueDate = widget.initialDueDate;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noCalendar)));
        setState(() => _saving = false);
        return;
      }
      await ref.read(createTodoProvider)(
        calendarId: calendars.first.id,
        summary: title,
        priority: 0,
        status: 'NEEDS-ACTION',
        dueDate: _dueDate,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      debugPrint('quick create: save failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
    }
  }

  Future<void> _pickDeadline() async {
    final picked = await pickDeadline(
      context,
      initial: _dueDate ?? DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  void _openFullForm() {
    final due = _dueDate;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(
      due == null
          ? '/todo/new'
          : '/todo/new?due=${due.millisecondsSinceEpoch}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          if (_dueDate != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(
                  l.deadlinePrefix(
                    DateFormatters.formatDate(_dueDate!),
                  ),
                ),
                onPressed: _pickDeadline,
                onDeleted: () => setState(() => _dueDate = null),
                deleteButtonTooltipMessage: l.clearDeadline,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : _openFullForm,
                child: Text(l.moreOptions),
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
    );
  }
}
