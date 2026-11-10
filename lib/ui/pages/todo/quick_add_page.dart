import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';

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
    final ds = context.ds;
    final landing = widget.dueDate == null ? l.inbox : l.deadlineToday;
    return Scaffold(
      backgroundColor: ds.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.s1),
                  DsIconButton(
                    icon: CupertinoIcons.xmark,
                    size: 18,
                    compact: true,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                  ),
                  const SizedBox(width: AppSpacing.s1),
                  Expanded(
                    child: Text(
                      landing,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: ds.ink,
                      ),
                    ),
                  ),
                  DsButton(
                    label: l.save,
                    small: true,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(width: AppSpacing.s3),
                ],
              ),
            ),
            Container(height: 1, color: ds.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s4,
                  AppSpacing.s4,
                  AppSpacing.s6,
                ),
                children: [
                  if (widget.dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: DsChip(
                          label: l.deadlinePrefix(
                            formatDeadline(context, widget.dueDate!),
                          ),
                          warm: true,
                          leading: Icon(
                            CupertinoIcons.flag,
                            size: 13,
                            color: ds.warn,
                          ),
                        ),
                      ),
                    ),
                  DsTextField(
                    key: const ValueKey('todo-quick-create-title'),
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    hint: l.widgetQuickAddHint,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s2),
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 12, color: ds.danger),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
