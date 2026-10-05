import 'dart:convert';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import 'sync_payload.dart';

const Uuid _uuid = Uuid();

/// Snapshot of a row captured before it is hard-deleted, so the tombstone
/// can still be enqueued once the row itself is gone.
class OutboxTarget {
  const OutboxTarget({
    required this.type,
    required this.recordId,
    required this.baseRev,
    this.fields,
  });

  final RecordType type;
  final String recordId;
  final int baseRev;
  final Map<String, Object?>? fields;
}

/// Explicit outbox write seam. Every event/todo mutation provider wraps its
/// writes in `db.transaction` and calls these helpers inside that same
/// transaction, so a row change and its pending sync op commit or roll back
/// together (a `tableUpdates`-only seam cannot give that atomicity — see
/// docs/superpowers/research/alliswell-outbox-comparison.md).
///
/// WHY merge — the outbox holds at most ONE op per recordId:
/// * successive upserts collapse to the newest payload, keeping the
///   OLDEST createdAt as a proxy for when the record first went dirty;
/// * a delete clears that record's pending upserts (the intent is now
///   "gone", shipping the stale upsert first would resurrect it);
/// * an upsert after a pending delete replaces the delete
///   (tombstone → resurrect intent);
/// * different records never interact.
/// Each enqueue mints a FRESH opId: the op it replaces may already be in
/// flight, and reusing its idempotency key would make the server replay a
/// stale verdict against newer intent.
class SyncOutbox {
  const SyncOutbox._();

  /// Queues an upsert for row [localId]. Must run inside the caller's
  /// Drift transaction. Assigns the row's UUIDv7 syncId on first enqueue;
  /// `syncId == NULL` therefore means "never enqueued / never pushed".
  static Future<void> enqueueUpsert(
    AppDatabase db,
    RecordType type,
    int localId,
  ) async {
    final String recordId;
    final String payloadJson;
    final int baseRev;
    if (type == RecordType.event) {
      final row = await (db.select(
        db.events,
      )..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (row == null) return;
      recordId = await _ensureSyncId(db, RecordType.event, localId, row.syncId);
      payloadJson = jsonEncode(eventToPayload(row));
      baseRev = row.serverRev;
    } else if (type == RecordType.todo) {
      final row = await (db.select(
        db.todos,
      )..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (row == null) return;
      recordId = await _ensureSyncId(db, RecordType.todo, localId, row.syncId);
      final parentId = row.parentId;
      if (parentId != null) {
        final parent = await (db.select(
          db.todos,
        )..where((t) => t.id.equals(parentId))).getSingleOrNull();
        // Pre-configure parents never got an identity; queue one now so
        // this child's parentSyncId can resolve on other devices.
        if (parent != null && parent.syncId == null) {
          await enqueueUpsert(db, RecordType.todo, parent.id);
        }
      }
      payloadJson = jsonEncode(await todoToPayload(db, row));
      baseRev = row.serverRev;
    } else if (type == RecordType.taskAllocation) {
      final row = await (db.select(
        db.taskAllocations,
      )..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (row == null) return;
      if (row.todoId != null) {
        await enqueueUpsert(db, RecordType.todo, row.todoId!);
      }
      final todo = row.todoId == null
          ? null
          : await (db.select(
              db.todos,
            )..where((t) => t.id.equals(row.todoId!))).getSingleOrNull();
      final parentSyncId = todo?.syncId ?? row.todoSyncId;
      if (parentSyncId == null || parentSyncId.isEmpty) {
        throw StateError('TaskAllocation has no parent Todo sync identity.');
      }
      if (row.todoSyncId != parentSyncId) {
        await (db.update(db.taskAllocations)
              ..where((t) => t.id.equals(localId)))
            .write(TaskAllocationsCompanion(todoSyncId: Value(parentSyncId)));
      }
      recordId = await _ensureSyncId(
        db,
        RecordType.taskAllocation,
        localId,
        row.syncId,
      );
      final refreshed = await (db.select(
        db.taskAllocations,
      )..where((t) => t.id.equals(localId))).getSingle();
      payloadJson = jsonEncode(taskAllocationToPayload(refreshed));
      baseRev = refreshed.serverRev;
    } else {
      final row = await (db.select(
        db.taskInstanceStates,
      )..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (row == null) return;
      recordId = row.syncId;
      payloadJson = jsonEncode(taskInstanceStateToPayload(row));
      baseRev = row.serverRev;
    }
    final oldest = await _existingCreatedAt(db, recordId);
    await _collapse(db, recordId);
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            opId: _uuid.v7(),
            recordId: recordId,
            type: type.wireName,
            op: OpType.upsert.name,
            payloadJson: Value(payloadJson),
            baseRev: Value(baseRev),
            createdAt: oldest ?? DateTime.now(),
          ),
        );
  }

  /// Queues a delete for a row that still exists (soft-delete / trash
  /// paths). Rows with NULL syncId were never pushed, so there is no
  /// server-side record to tombstone — they are skipped.
  static Future<void> enqueueDelete(
    AppDatabase db,
    RecordType type,
    int localId,
  ) async {
    await enqueueDeletes(db, await captureDeletes(db, type, [localId]));
  }

  /// Reads recordId + baseRev while rows still exist. Hard-delete call
  /// sites must call this BEFORE dropping rows, then [enqueueDeletes]
  /// inside the same transaction.
  static Future<List<OutboxTarget>> captureDeletes(
    AppDatabase db,
    RecordType type,
    List<int> localIds, {
    bool hardDelete = false,
  }) async {
    if (localIds.isEmpty) return const [];
    if (type == RecordType.event) {
      final rows = await (db.select(
        db.events,
      )..where((t) => t.id.isIn(localIds))).get();
      return [
        for (final row in rows)
          if (row.syncId != null)
            OutboxTarget(
              type: RecordType.event,
              recordId: row.syncId!,
              baseRev: row.serverRev,
            ),
      ];
    }
    if (type == RecordType.taskAllocation) {
      final rows = await (db.select(
        db.taskAllocations,
      )..where((t) => t.id.isIn(localIds))).get();
      return [
        for (final row in rows)
          if (row.syncId != null)
            OutboxTarget(
              type: RecordType.taskAllocation,
              recordId: row.syncId!,
              baseRev: row.serverRev,
            ),
      ];
    }
    if (type == RecordType.taskInstanceState) {
      final rows = await (db.select(
        db.taskInstanceStates,
      )..where((t) => t.id.isIn(localIds))).get();
      return [
        for (final row in rows)
          OutboxTarget(
            type: RecordType.taskInstanceState,
            recordId: row.syncId,
            baseRev: row.serverRev,
          ),
      ];
    }
    final rows = await (db.select(
      db.todos,
    )..where((t) => t.id.isIn(localIds))).get();
    return [
      for (final row in rows)
        if (row.syncId != null)
          OutboxTarget(
            type: RecordType.todo,
            recordId: row.syncId!,
            baseRev: row.serverRev,
            fields: hardDelete ? const {'hardDelete': true} : null,
          ),
    ];
  }

  static Future<void> enqueueDeletes(
    AppDatabase db,
    List<OutboxTarget> targets,
  ) async {
    for (final target in targets) {
      final oldest = await _existingCreatedAt(db, target.recordId);
      await _collapse(db, target.recordId);
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              opId: _uuid.v7(),
              recordId: target.recordId,
              type: target.type.wireName,
              op: OpType.delete.name,
              payloadJson: Value(
                target.fields == null ? null : jsonEncode(target.fields),
              ),
              baseRev: Value(target.baseRev),
              createdAt: oldest ?? DateTime.now(),
            ),
          );
    }
  }

  static Future<String> _ensureSyncId(
    AppDatabase db,
    RecordType type,
    int localId,
    String? current,
  ) async {
    if (current != null) return current;
    final syncId = _uuid.v7();
    if (type == RecordType.event) {
      await (db.update(db.events)..where((t) => t.id.equals(localId))).write(
        EventsCompanion(syncId: Value(syncId)),
      );
    } else if (type == RecordType.todo) {
      await (db.update(db.todos)..where((t) => t.id.equals(localId))).write(
        TodosCompanion(syncId: Value(syncId)),
      );
    } else if (type == RecordType.taskAllocation) {
      await (db.update(db.taskAllocations)..where((t) => t.id.equals(localId)))
          .write(TaskAllocationsCompanion(syncId: Value(syncId)));
    } else {
      await (db.update(db.taskInstanceStates)
            ..where((t) => t.id.equals(localId)))
          .write(TaskInstanceStatesCompanion(syncId: Value(syncId)));
    }
    return syncId;
  }

  static Future<DateTime?> _existingCreatedAt(
    AppDatabase db,
    String recordId,
  ) async {
    final rows = await (db.select(
      db.syncOutbox,
    )..where((t) => t.recordId.equals(recordId))).get();
    if (rows.isEmpty) return null;
    return rows.map((r) => r.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  static Future<void> _collapse(AppDatabase db, String recordId) async {
    await (db.delete(
      db.syncOutbox,
    )..where((t) => t.recordId.equals(recordId))).go();
  }
}
