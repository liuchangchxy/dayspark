import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';

final class TaskInstanceWriter {
  const TaskInstanceWriter._();

  static Future<void> setCompletion(
    AppDatabase db,
    RecordScope tx, {
    required int todoId,
    required String occurrenceId,
    required bool completed,
  }) async {
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingleOrNull();
    if (todo == null) throw StateError('Todo does not exist.');
    if (todo.status == 'COMPLETED') {
      throw StateError(
        'Reopen the legacy completed series before instance actions.',
      );
    }
    final recurrence = TodoRecurrence.fromTodo(todo);
    final spec = recurrence.spec;
    if (spec == null || recurrence.isUnknownLegacy) {
      throw StateError(
        'A valid occurrenceId from a known recurrence is required.',
      );
    }
    final occurrenceIsCurrent = isOccurrenceValidForSpec(spec, occurrenceId);
    if (todo.syncId == null || todo.syncId!.isEmpty) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, todoId);
    }
    final refreshedTodo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingle();
    final syncId = taskInstanceStateRecordId(
      refreshedTodo.syncId!,
      occurrenceId,
    );
    final existing = await (db.select(
      db.taskInstanceStates,
    )..where((row) => row.syncId.equals(syncId))).getSingleOrNull();
    if (!occurrenceIsCurrent && (existing == null || completed)) {
      throw StateError(
        'Only an existing instance state can be reopened after a series edit.',
      );
    }
    if (existing == null && !completed) return;
    final now = DateTime.now().toUtc();
    final completedAt = completed ? (existing?.completedAt ?? now) : null;
    if (existing == null) {
      await db
          .into(db.taskInstanceStates)
          .insert(
            TaskInstanceStatesCompanion.insert(
              syncId: syncId,
              todoSyncId: refreshedTodo.syncId!,
              todoId: Value(todoId),
              occurrenceId: occurrenceId,
              status: Value(completed ? 'completed' : 'pending'),
              completedAt: Value(completedAt),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.taskInstanceStates,
      )..where((row) => row.id.equals(existing.id))).write(
        TaskInstanceStatesCompanion(
          status: Value(completed ? 'completed' : 'pending'),
          completedAt: Value(completedAt),
          updatedAt: Value(now),
        ),
      );
    }
    await _invalidateAllocations(db, tx, todoId, occurrenceId, completedAt);
    final state = await (db.select(
      db.taskInstanceStates,
    )..where((row) => row.syncId.equals(syncId))).getSingle();
    await SyncOutbox.enqueueUpsert(db, RecordType.taskInstanceState, state.id);
    tx.taskInstanceStateChanged(state.id);
  }

  static Future<void> _invalidateAllocations(
    AppDatabase db,
    RecordScope tx,
    int todoId,
    String occurrenceId,
    DateTime? completedAt,
  ) async {
    if (completedAt == null) return;
    final allocations =
        await (db.select(db.taskAllocations)..where(
              (row) =>
                  row.todoId.equals(todoId) &
                  row.occurrenceId.equals(occurrenceId) &
                  row.state.equals('active'),
            ))
            .get();
    for (final allocation in allocations) {
      if (allocation.startAt.toUtc().millisecondsSinceEpoch <
          completedAt.toUtc().millisecondsSinceEpoch) {
        continue;
      }
      await (db.update(
        db.taskAllocations,
      )..where((row) => row.id.equals(allocation.id))).write(
        TaskAllocationsCompanion(
          state: const Value('invalidatedByCompletion'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await SyncOutbox.enqueueUpsert(
        db,
        RecordType.taskAllocation,
        allocation.id,
      );
      tx.taskAllocationChanged(allocation.id);
    }
  }
}
