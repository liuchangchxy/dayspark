import 'dart:convert';
import 'dart:math';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';

import '../db.dart';
import '../sync/idempotency.dart';
import '../sync/lww.dart';

// Shared per-op write path for every internal mutation: the HTTP push route
// and the MCP/AI writer both land here so there is exactly one implementation
// of the per-op transaction, field-level LWW, sync_ops idempotency, seq
// advancement and the post-commit seq-advanced notification.
//
// Contract: one op = one transaction (a bad op never rolls back a neighbor);
// notify fires AFTER commit and only when the user's feed actually advanced,
// so idempotent replays and rejected ops stay silent.

Future<OpResult> applyInternalOp({
  required DatabaseConnectionUser db,
  required String userId,
  required PushOp op,
  required void Function(String userId, int seq) notify,
}) async {
  final app = _asAppDatabase(db);
  final seqBefore = await currentSeq(app, userId);
  final result = await app.transaction(() => _applyOp(app, userId, op));
  final seqAfter = await currentSeq(app, userId);
  if (seqAfter > seqBefore) {
    notify(userId, seqAfter);
  }
  return result;
}

AppDatabase _asAppDatabase(DatabaseConnectionUser db) {
  if (db is AppDatabase) {
    return db;
  }
  throw ArgumentError.value(
    db,
    'db',
    'applyInternalOp needs the AppDatabase instance so table accessors and '
        'nextSeq resolve to the same database',
  );
}

// Time-ordered opaque id for internal ops (uuid-v7 shape): same-second LWW
// tie-breaks then follow real write order, like the client outbox's v7 ids.
final Random _secureRandom = Random.secure();

String newOpId() {
  final timeHex = DateTime.now()
      .toUtc()
      .millisecondsSinceEpoch
      .toRadixString(16)
      .padLeft(12, '0');
  final buffer = StringBuffer(timeHex)..write('7');
  for (var i = 0; i < 3; i++) {
    buffer.write(_secureRandom.nextInt(16).toRadixString(16));
  }
  buffer.write(const ['8', '9', 'a', 'b'][_secureRandom.nextInt(4)]);
  for (var i = 0; i < 15; i++) {
    buffer.write(_secureRandom.nextInt(16).toRadixString(16));
  }
  final hex = buffer.toString();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

Future<OpResult> _applyOp(AppDatabase db, String userId, PushOp op) async {
  final stored = await findSyncOp(db, op.opId);
  if (stored != null) {
    if (stored.userId != userId) {
      // PK collision with another tenant's opId: reject without touching
      // their stored verdict.
      return OpResult(opId: op.opId, status: OpStatus.rejected, code: errConflict);
    }
    return decodeStoredOpResult(stored);
  }

  final result = await _processOp(db, userId, op);
  await storeOpResult(db, opId: op.opId, userId: userId, result: result);
  return result;
}

Future<OpResult> _processOp(AppDatabase db, String userId, PushOp op) async {
  final now = DateTime.now().toUtc();
  if (op.op == OpType.upsert) {
    return _processUpsert(db, userId, op, now);
  }
  return _processDelete(db, userId, op, now);
}

Future<OpResult> _processUpsert(
  AppDatabase db,
  String userId,
  PushOp op,
  DateTime now,
) async {
  final fields = op.fields;
  if (fields == null || fields.isEmpty) {
    return OpResult(opId: op.opId, status: OpStatus.rejected, code: errValidation);
  }

  final row = await _selectRecord(db, userId, op.recordId);
  if (row == null) {
    if (op.baseRev != null && op.baseRev! > 0) {
      return OpResult(opId: op.opId, status: OpStatus.rejected, code: errValidation);
    }
    final record = await _insertRecord(db, userId, op, fields, now, deleted: false);
    return OpResult(
      opId: op.opId,
      status: OpStatus.applied,
      serverRecord: toSyncRecord(record),
    );
  }

  // Type is part of the record's identity: an upsert must not silently
  // retag an event as a todo (or vice versa) on update or resurrect.
  if (row.type != op.type.name) {
    return OpResult(opId: op.opId, status: OpStatus.rejected, code: errValidation);
  }

  if (row.deleted) {
    final decision = decideTombstoneVsUpsert(
      recordServerTs: row.serverTs,
      opTs: now,
      recordLastOpId: row.lastOpId,
      incomingOpId: op.opId,
    );
    if (decision == TombstoneUpsertDecision.conflict) {
      return OpResult(
        opId: op.opId,
        status: OpStatus.conflict,
        serverRecord: toSyncRecord(row),
        code: errConflict,
      );
    }
  }

  // Field-level LWW: keys the op sets win (arrival order = server order),
  // keys it does not set keep server values — for both matching and stale
  // baseRev, per the LWW ruling.
  final merged = mergeFields(
    jsonDecode(row.payloadJson) as Map<String, dynamic>,
    fields,
  );
  final updated = await _writeRecord(
    db,
    userId,
    op.recordId,
    row.copyWith(
      payloadJson: jsonEncode(merged),
      rev: row.rev + 1,
      deleted: false,
      serverTs: now,
      lastOpId: op.opId,
    ),
    now: now,
  );
  return OpResult(
    opId: op.opId,
    status: OpStatus.applied,
    serverRecord: toSyncRecord(updated),
  );
}

Future<OpResult> _processDelete(
  AppDatabase db,
  String userId,
  PushOp op,
  DateTime now,
) async {
  final row = await _selectRecord(db, userId, op.recordId);
  if (row == null) {
    // Deleting a record the server has never seen still materializes a
    // tombstone so the deletion propagates.
    final record = await _insertRecord(
      db,
      userId,
      op,
      const <String, dynamic>{},
      now,
      deleted: true,
    );
    return OpResult(
      opId: op.opId,
      status: OpStatus.applied,
      serverRecord: toSyncRecord(record),
    );
  }
  if (row.deleted) {
    // Desired state already reached — no mutation, so no new seq.
    return OpResult(
      opId: op.opId,
      status: OpStatus.applied,
      serverRecord: toSyncRecord(row),
    );
  }
  final tombstone = row.copyWith(
    rev: row.rev + 1,
    deleted: true,
    serverTs: now,
    lastOpId: op.opId,
  );
  final updated = await _writeRecord(db, userId, op.recordId, tombstone, now: now);
  return OpResult(
    opId: op.opId,
    status: OpStatus.applied,
    serverRecord: toSyncRecord(updated),
  );
}

Future<RecordRow> _insertRecord(
  AppDatabase db,
  String userId,
  PushOp op,
  Map<String, dynamic> payload,
  DateTime now, {
  required bool deleted,
}) async {
  final seq = await db.nextSeq(db, userId);
  final record = RecordRow(
    userId: userId,
    id: op.recordId,
    type: op.type.name,
    payloadJson: jsonEncode(payload),
    rev: 1,
    deleted: deleted,
    serverTs: now,
    seq: seq,
    lastOpId: op.opId,
  );
  await db.into(db.records).insert(record);
  return record;
}

Future<RecordRow> _writeRecord(
  AppDatabase db,
  String userId,
  String recordId,
  RecordRow row, {
  required DateTime now,
}) async {
  // seq assignment and the record write share this transaction (binding rule).
  final seq = await db.nextSeq(db, userId);
  final withSeq = row.copyWith(seq: seq);
  await (db.update(db.records)
        ..where((t) => t.userId.equals(userId) & t.id.equals(recordId)))
      .write(withSeq);
  return withSeq;
}

Future<RecordRow?> _selectRecord(AppDatabase db, String userId, String id) {
  return (db.select(db.records)
        ..where((t) => t.userId.equals(userId) & t.id.equals(id)))
      .getSingleOrNull();
}

Future<int> currentSeq(AppDatabase db, String userId) async {
  final row = await (db.select(db.revisions)
        ..where((t) => t.userId.equals(userId)))
      .getSingleOrNull();
  return row?.seq ?? 0;
}

SyncRecord toSyncRecord(RecordRow row) => SyncRecord(
      id: row.id,
      type: switch (row.type) {
        'event' => RecordType.event,
        'todo' => RecordType.todo,
        _ => throw FormatException('invalid record type: ${row.type}'),
      },
      payload: jsonDecode(row.payloadJson) as Map<String, dynamic>,
      rev: row.rev,
      deleted: row.deleted,
      serverTs: row.serverTs.toUtc(),
    );
