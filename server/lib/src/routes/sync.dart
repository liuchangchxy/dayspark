import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../db.dart';
import '../http.dart';
import '../sync/idempotency.dart';
import '../sync/lww.dart';

const int _pullDefaultLimit = 100;
const int _pullMaxLimit = 500;
const int _piggybackLimit = 100;

void registerSyncRoutes(
  Router router, {
  required AppDatabase db,
  required Auth auth,
  required void Function(String userId, int seq) notifySeq,
}) {
  router.post('/sync/push', auth.requireAuth((request, context) async {
    final body = await readJsonObject(request);
    final PushRequest push;
    try {
      push = PushRequest.fromJson(body);
    } on FormatException catch (e) {
      throw ApiException(400, errValidation, e.message);
    }
    if (push.cursor != null && push.cursor! < 0) {
      throw ApiException(400, errValidation, 'cursor must be >= 0');
    }

    final userId = context.userId;
    final seqBefore = await _currentSeq(db, userId);
    final results = <OpResult>[];
    for (final op in push.ops) {
      // Each op runs in its own transaction: one bad op can never roll back
      // a neighbor, and results keep the request's op order.
      results.add(await db.transaction(() => _applyOp(db, userId, op)));
    }
    final seqAfter = await _currentSeq(db, userId);
    // Task-4 SSE consumer seam: fire only after commits and only when the
    // feed advanced.
    if (seqAfter > seqBefore) {
      notifySeq(userId, seqAfter);
    }

    final piggybackRows = await _changesSince(
      db,
      userId,
      afterSeq: push.cursor ?? 0,
      limit: _piggybackLimit,
    );
    // Watermark: every change <= cursor is included in this response — on a
    // capped piggyback the cursor must be the LAST DELIVERED seq, or a client
    // adopting the head would silently skip the undelivered tail.
    final outCursor = piggybackRows.isNotEmpty
        ? piggybackRows.last.seq
        : (push.cursor ?? seqAfter);
    return jsonResponse(
      200,
      PushResponse(
        results: results,
        piggyback: piggybackRows.map(_toSyncRecord).toList(),
        cursor: outCursor,
      ).toJson(),
    );
  }));

  router.get('/sync/pull', auth.requireAuth((request, context) async {
    final cursor = _parseQueryInt(request, 'cursor', fallback: 0);
    final limit = _parseQueryInt(request, 'limit', fallback: _pullDefaultLimit);
    if (cursor < 0) {
      throw ApiException(400, errValidation, 'cursor must be >= 0');
    }
    final pageLimit = limit < 1 ? 1 : (limit > _pullMaxLimit ? _pullMaxLimit : limit);

    final rows = await (db.select(db.records)
          ..where((t) => t.userId.equals(context.userId) & t.seq.isBiggerThanValue(cursor))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)])
          ..limit(pageLimit + 1))
        .get();
    final hasMore = rows.length > pageLimit;
    final page = hasMore ? rows.sublist(0, pageLimit) : rows;
    return jsonResponse(
      200,
      PullResponse(
        changes: page.map(_toSyncRecord).toList(),
        nextCursor: page.isEmpty ? cursor : page.last.seq,
        hasMore: hasMore,
      ).toJson(),
    );
  }));
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
      serverRecord: _toSyncRecord(record),
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
        serverRecord: _toSyncRecord(row),
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
    serverRecord: _toSyncRecord(updated),
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
      serverRecord: _toSyncRecord(record),
    );
  }
  if (row.deleted) {
    // Desired state already reached — no mutation, so no new seq.
    return OpResult(
      opId: op.opId,
      status: OpStatus.applied,
      serverRecord: _toSyncRecord(row),
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
    serverRecord: _toSyncRecord(updated),
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

Future<int> _currentSeq(AppDatabase db, String userId) async {
  final row = await (db.select(db.revisions)
        ..where((t) => t.userId.equals(userId)))
      .getSingleOrNull();
  return row?.seq ?? 0;
}

Future<List<RecordRow>> _changesSince(
  AppDatabase db,
  String userId, {
  required int afterSeq,
  required int limit,
}) {
  return (db.select(db.records)
        ..where((t) => t.userId.equals(userId) & t.seq.isBiggerThanValue(afterSeq))
        ..orderBy([(t) => OrderingTerm.asc(t.seq)])
        ..limit(limit))
      .get();
}

SyncRecord _toSyncRecord(RecordRow row) => SyncRecord(
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

int _parseQueryInt(Request request, String name, {required int fallback}) {
  final raw = request.url.queryParameters[name];
  if (raw == null) {
    return fallback;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null) {
    throw ApiException(400, errValidation, '$name must be an integer');
  }
  return parsed;
}
