import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

/// The single completion entry point for every surface that can tick a todo.
///
/// A recurring todo cannot be completed as a row: the writer requires the
/// occurrence the user means. Pages used to call [toggleTodoProvider]
/// directly and decide for themselves whether to pass one, which is how the
/// detail page ended up throwing on every recurring todo while the list asked
/// the user which occurrence. Resolution lives here so it cannot drift again.
///
/// Returns true when the todo changed, false when the user dismissed the
/// occurrence selector.
/// [occurrenceId] is for callers that already know which occurrence they
/// mean — a calendar allocation is bound to one — so the picker is skipped.
Future<bool> toggleTodoCompletion(
  BuildContext context,
  WidgetRef ref, {
  required Todo todo,
  required bool completed,
  String? occurrenceId,
}) async {
  if (occurrenceId != null) {
    await ref.read(toggleTodoProvider)(
      id: todo.id,
      isCompleted: completed,
      occurrenceId: occurrenceId,
    );
    return true;
  }

  final recurring = todo.rrule != null;
  if (!recurring) {
    await ref.read(toggleTodoProvider)(id: todo.id, isCompleted: completed);
    return true;
  }

  // A series that is already completed has no single occurrence to point at;
  // reopening it means reopening the parent row, exactly like the list.
  if (todo.status == 'COMPLETED') {
    await ref.read(toggleTodoProvider)(id: todo.id, isCompleted: false);
    return true;
  }

  final selected = await TodoOccurrencePickerSheet.show(
    context,
    ref: ref,
    todo: todo,
  );
  if (selected == null || !context.mounted) return false;
  await ref.read(toggleTodoProvider)(
    id: todo.id,
    isCompleted: completed,
    occurrenceId: selected.occurrenceId,
  );
  return true;
}

/// Reports a completion failure without leaking the raw exception.
void showCompletionError(BuildContext context, Object error) {
  debugPrint('todo completion failed: $error');
  final l = AppLocalizations.of(context);
  if (l == null) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(l.actionFailedRetry)));
}
