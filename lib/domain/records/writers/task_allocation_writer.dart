import 'package:drift/drift.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

final class TaskAllocationWriter {
  const TaskAllocationWriter._();

  static Future<int> create(
    AppDatabase db,
    RecordScope tx, {
    required int todoId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final range = _canonicalRange(startAt, endAt);
    await _requireSchedulableTodo(db, todoId);
    final now = DateTime.now();
    final id = await db
        .into(db.taskAllocations)
        .insert(
          TaskAllocationsCompanion.insert(
            todoId: Value(todoId),
            startAt: range.$1,
            endAt: range.$2,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await SyncOutbox.enqueueUpsert(db, RecordType.taskAllocation, id);
    tx.taskAllocationChanged(id);
    return id;
  }

  static Future<void> reschedule(
    AppDatabase db,
    RecordScope tx, {
    required int id,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final range = _canonicalRange(startAt, endAt);
    final allocation = await (db.select(
      db.taskAllocations,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (allocation == null || allocation.state != 'active') {
      throw StateError('Only active TaskAllocations can be rescheduled.');
    }
    final todoId = allocation.todoId;
    if (todoId == null) {
      throw StateError('Unresolved TaskAllocation cannot be rescheduled.');
    }
    await _requireSchedulableTodo(db, todoId);
    await (db.update(
      db.taskAllocations,
    )..where((row) => row.id.equals(id))).write(
      TaskAllocationsCompanion(
        startAt: Value(range.$1),
        endAt: Value(range.$2),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncOutbox.enqueueUpsert(db, RecordType.taskAllocation, id);
    tx.taskAllocationChanged(id);
  }

  static Future<void> cancel(AppDatabase db, RecordScope tx, int id) async {
    final allocation = await (db.select(
      db.taskAllocations,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (allocation == null) return;
    if (allocation.state == 'cancelledByUser') return;
    if (allocation.state != 'active') {
      throw StateError('Only active TaskAllocations can be cancelled.');
    }
    await (db.update(
      db.taskAllocations,
    )..where((row) => row.id.equals(id))).write(
      TaskAllocationsCompanion(
        state: const Value('cancelledByUser'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncOutbox.enqueueUpsert(db, RecordType.taskAllocation, id);
    tx.taskAllocationChanged(id);
  }

  static Future<void> applyRemote(
    AppDatabase db,
    RecordScope tx, {
    required int? existingId,
    required TaskAllocationsCompanion data,
  }) async {
    if (existingId == null) {
      final id = await db.into(db.taskAllocations).insert(data);
      tx.taskAllocationChanged(id);
      return;
    }
    await (db.update(
      db.taskAllocations,
    )..where((row) => row.id.equals(existingId))).write(data);
    tx.taskAllocationChanged(existingId);
  }

  static Future<void> applyRemoteDelete(
    AppDatabase db,
    RecordScope tx,
    int id,
  ) async {
    await (db.delete(
      db.taskAllocations,
    )..where((row) => row.id.equals(id))).go();
    tx.taskAllocationChanged(id);
  }

  static (DateTime, DateTime) _canonicalRange(
    DateTime startAt,
    DateTime endAt,
  ) {
    DateTime canonical(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

    final canonicalStart = canonical(startAt);
    final canonicalEnd = canonical(endAt);
    if (!canonicalEnd.isAfter(canonicalStart)) {
      throw ArgumentError.value(
        endAt,
        'endAt',
        'TaskAllocation endAt must be after startAt.',
      );
    }
    return (canonicalStart, canonicalEnd);
  }

  static Future<void> _requireSchedulableTodo(
    AppDatabase db,
    int todoId,
  ) async {
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(todoId))).getSingleOrNull();
    if (todo == null ||
        todo.deletedAt != null ||
        todo.status == 'COMPLETED' ||
        todo.status == 'CANCELLED') {
      throw StateError('TaskAllocation requires an active Todo.');
    }
    if (todo.rrule != null && todo.rrule!.isNotEmpty) {
      throw StateError('Recurring Todos cannot be scheduled in Phase 1.');
    }
  }
}
