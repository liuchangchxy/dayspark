import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/records/todo_occurrence.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/todo/todo_occurrence_picker_sheet.dart';

/// Resolves the current uncompleted occurrence for a recurring series.
Future<String?> resolveCurrentOccurrenceId(
  WidgetRef ref,
  Todo todo, {
  DateTime? anchorDate,
}) async {
  var freshTodo = todo;
  if (freshTodo.syncId == null) {
    try {
      freshTodo = await ref.read(ensureTodoSyncIdentityProvider)(todo.id);
    } catch (_) {}
  }
  final db = ref.read(databaseProvider);
  final now = anchorDate ?? DateTime.now();
  final page = await loadOccurrencePage(
    db,
    freshTodo,
    historyPage: 1,
    anchorDate: now,
  );
  if (page.isEmpty) return null;
  final uncompleted = page.where((item) => !item.isCompleted).toList();
  if (uncompleted.isEmpty) {
    return page.last.occurrenceId;
  }
  final todayItem = uncompleted.where((item) => item.isToday(now)).firstOrNull;
  if (todayItem != null) return todayItem.occurrenceId;
  return uncompleted.first.occurrenceId;
}

/// The single completion entry point for every surface that can tick a todo.
Future<({bool changed, String? occurrenceId})> toggleTodoCompletion(
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
    return (changed: true, occurrenceId: occurrenceId);
  }

  final recurring = todo.rrule != null;
  if (!recurring) {
    await ref.read(toggleTodoProvider)(id: todo.id, isCompleted: completed);
    return (changed: true, occurrenceId: null);
  }

  // A series that is already completed has no single occurrence to point at;
  // reopening it means reopening the parent row, exactly like the list.
  if (todo.status == 'COMPLETED') {
    await ref.read(toggleTodoProvider)(id: todo.id, isCompleted: false);
    return (changed: true, occurrenceId: null);
  }

  var targetOccurrenceId = await resolveCurrentOccurrenceId(ref, todo);

  // If auto-resolution fails, fallback to picker sheet
  if (targetOccurrenceId == null && context.mounted) {
    final selected = await TodoOccurrencePickerSheet.show(
      context,
      ref: ref,
      todo: todo,
    );
    if (selected != null) {
      targetOccurrenceId = selected.occurrenceId;
    }
  }

  // If still no occurrence resolved, stay in place with error feedback and NEVER write to DB
  if (targetOccurrenceId == null) {
    if (context.mounted) {
      final l = AppLocalizations.of(context);
      if (l != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.actionFailedRetry)),
        );
      }
    }
    return (changed: false, occurrenceId: null);
  }

  await ref.read(toggleTodoProvider)(
    id: todo.id,
    isCompleted: completed,
    occurrenceId: targetOccurrenceId,
  );
  return (changed: true, occurrenceId: targetOccurrenceId);
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
