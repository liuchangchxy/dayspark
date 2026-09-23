import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../data/record_writer.dart';
import '../db.dart';
import '../http.dart';

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
    final results = <OpResult>[];
    for (final op in push.ops) {
      // Same per-op seam as internal/MCP writes: one transaction + LWW +
      // sync_ops + post-commit notify per op; request order is preserved.
      results.add(
        await applyInternalOp(db: db, userId: userId, op: op, notify: notifySeq),
      );
    }
    final seqAfter = await currentSeq(db, userId);

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
        piggyback: piggybackRows.map(toSyncRecord).toList(),
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
        changes: page.map(toSyncRecord).toList(),
        nextCursor: page.isEmpty ? cursor : page.last.seq,
        hasMore: hasMore,
      ).toJson(),
    );
  }));
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
