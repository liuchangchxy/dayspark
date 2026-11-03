import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// One always-present line for "just add it".
///
/// Enter writes the row and keeps the field focused, so five small tasks cost
/// five lines of typing rather than five trips through the form. Anything that
/// needs a date rule, a schedule or reminders still belongs to the full form.
class TodoQuickAdd extends ConsumerStatefulWidget {
  const TodoQuickAdd({super.key, this.dueDate});

  /// Landing date for the new row: the day being viewed, or none in Inbox/All.
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
    // Clear and refocus before the write: the next task can be typed while the
    // previous one is still committing.
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
    final horizontal = isWorkspaceLayout(context) ? 28.0 : AppSpacing.lg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.add,
                  size: 15,
                  color: context.semantic.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('todo-quick-add'),
                    controller: _controller,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    // onEditingComplete, not onSubmitted: the framework only
                    // unfocuses after submit when onSubmitted is the handler,
                    // and a field that loses focus after every line cannot
                    // take the next one.
                    onEditingComplete: () => _submit(_controller.text),
                    style: AppTypography.body,
                    decoration: InputDecoration(
                      hintText: l.quickAdd,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      hintStyle: AppTypography.body.copyWith(
                        color: context.semantic.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: context.semantic.separatorSoft),
      ],
    );
  }
}
