import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// The always-present "just add it" line.
///
/// Enter writes the row and keeps the field focused, so five small tasks cost
/// five lines of typing. The desktop version sits on a surface-2 ground; the
/// mobile one is a hairline row, which is how the prototype keeps the list
/// from looking like a stack of cards.
class TodoQuickAdd extends ConsumerStatefulWidget {
  const TodoQuickAdd({super.key, this.dueDate});

  final DateTime? dueDate;

  @override
  ConsumerState<TodoQuickAdd> createState() => _TodoQuickAddState();
}

class _TodoQuickAddState extends ConsumerState<TodoQuickAdd> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    _controller.clear();
    _focus.requestFocus();
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        _showMessage(l.noCalendar);
        return;
      }
      await ref.read(createTodoProvider)(
        calendarId: calendars.first.id,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
        dueDate: widget.dueDate,
      );
    } on Object catch (error) {
      debugPrint('todo_quick_add: create failed: $error');
      _showMessage(l.actionFailedRetry);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final desktop = isWorkspaceLayout(context);

    final field = Row(
      children: [
        Icon(CupertinoIcons.add, size: 16, color: ds.ink3),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: TextField(
            key: const ValueKey('todo-quick-add'),
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onEditingComplete: () => _submit(_controller.text),
            style: AppTypography.body.copyWith(color: ds.ink),
            decoration: InputDecoration(
              hintText: l.quickAddTodo,
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: AppTypography.body.copyWith(color: ds.ink3),
            ),
          ),
        ),
      ],
    );

    final dueChip = widget.dueDate == null
        ? null
        : DsChip(
            compact: true,
            label: l.deadlinePrefix(formatDeadline(context, widget.dueDate!)),
            leading: Icon(CupertinoIcons.flag, size: 12, color: ds.warn),
            warm: true,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desktop) ...[
          if (dueChip != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s5,
                AppSpacing.s2,
                AppSpacing.s5,
                AppSpacing.s1,
              ),
              child: Align(alignment: Alignment.centerLeft, child: dueChip),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s5,
              AppSpacing.s2,
              AppSpacing.s5,
              AppSpacing.s2,
            ),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: ds.surface2,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: field,
            ),
          ),
        ] else
          // The due chip shares the field's row: on a phone a lone chip on the
          // line above cost 30px of list space and read as a stray control.
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: Row(
              children: [
                Expanded(child: field),
                if (dueChip != null) ...[
                  const SizedBox(width: AppSpacing.s2),
                  dueChip,
                ],
              ],
            ),
          ),
        Container(
          height: 1,
          color: desktop ? ds.lineSoft : ds.lineSoft,
        ),
      ],
    );
  }
}
