import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// Minimal capture surface opened by a widget's `+`.
///
/// One autofocused line, a landing label and a save action. It deliberately
/// does not reuse the full Todo form: priority, tags, recurrence and reminders
/// all stay behind the App's normal creation flow.
class QuickAddPage extends ConsumerStatefulWidget {
  const QuickAddPage({super.key, this.dueDate});

  final DateTime? dueDate;

  @override
  ConsumerState<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends ConsumerState<QuickAddPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        setState(() {
          _saving = false;
          _error = l.widgetSaveFailed;
        });
        return;
      }
      await ref.read(createTodoProvider)(
        calendarId: calendars.first.id,
        summary: text,
        priority: 0,
        status: 'NEEDS-ACTION',
        dueDate: widget.dueDate,
      );
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } on Object catch (error) {
      debugPrint('quick_add: create failed: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l.widgetSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final landing = widget.dueDate == null ? l.inbox : l.today;
    return Scaffold(
      appBar: AppBar(
        title: Text(landing),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(l.save),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: AppTypography.body,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: l.widgetQuickAddHint,
                filled: true,
                fillColor: context.semantic.surfaceSecondary,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.caption.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
