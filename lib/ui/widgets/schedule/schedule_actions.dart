import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';

/// "Plan when I'll do it": a start moment and a length, nothing else.
///
/// Kept in one place because Today's rail, the Todo detail pane and the
/// calendar slot sheet all offer the same action; three copies is how the
/// pickers drifted apart.
Future<bool> scheduleTodoBlock(
  BuildContext context,
  WidgetRef ref,
  Todo todo,
) async {
  final l = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final initial = DateTime(
    now.year,
    now.month,
    now.day,
    (now.hour + 1).clamp(0, 23),
  );
  final start = await pickDateTime(context, initial: initial);
  if (start == null || !context.mounted) return false;

  final length = await showModalBottomSheet<Duration>(
    context: context,
    backgroundColor: context.ds.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l.duration,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: ctx.ds.ink,
                ),
              ),
            ),
          ),
          for (final option in kExecutionLengths)
            ListTile(
              title: Text(formatExecutionLength(ctx, option)),
              onTap: () => Navigator.of(ctx).pop(option),
            ),
        ],
      ),
    ),
  );
  if (length == null || !context.mounted) return false;

  final end = start.add(length);
  await ref.read(createTaskAllocationProvider)(
    todoId: todo.id,
    startAt: start,
    endAt: end,
  );
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l.scheduledTodoSuccess(todo.summary))));
  return true;
}
