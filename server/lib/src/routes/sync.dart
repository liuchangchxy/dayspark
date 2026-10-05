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
  router.get(
    '/sync/capabilities',
    auth.requireAuth((request, context) async {
      return jsonResponse(
        200,
        const SyncCapabilitiesResponse(
          capabilities: [
            SyncCapability.taskAllocationV1,
            SyncCapability.todoRecurrenceV1,
            SyncCapability.taskInstanceStateV1,
          ],
        ).toJson(),
      );
    }),
  );

  router.post(
    '/sync/push',
    auth.requireAuth((request, context) async {
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
      // The header is authoritative (it identifies the caller's install); the
      // body field is the legacy path the client has always sent. Either way the
      // id lands on the op ledger so "which device wrote this" is answerable.
      final deviceId = context.deviceId ?? push.deviceId;
      await _touchDevice(db, userId: userId, deviceId: deviceId);
      final results = <OpResult>[];
      for (final op in push.ops) {
        final hasRecurrenceUpdate =
            op.type == RecordType.todo &&
            op.fields?.keys.any(
                  const {
                    'recurrenceSpec',
                    'recurrenceRevision',
                    'recurrenceLegacyState',
                  }.contains,
                ) ==
                true;
        if (hasRecurrenceUpdate &&
            !push.capabilities.contains(SyncCapability.todoRecurrenceV1)) {
          results.add(
            OpResult(
              opId: op.opId,
              status: OpStatus.rejected,
              code: errValidation,
            ),
          );
          continue;
        }
        if (op.type == RecordType.taskAllocation &&
            !push.capabilities.contains(SyncCapability.taskAllocationV1)) {
          results.add(
            OpResult(
              opId: op.opId,
              status: OpStatus.rejected,
              code: errValidation,
            ),
          );
          continue;
        }
        if (op.type == RecordType.taskInstanceState &&
            !push.capabilities.contains(SyncCapability.taskInstanceStateV1)) {
          results.add(
            OpResult(
              opId: op.opId,
              status: OpStatus.rejected,
              code: errValidation,
            ),
          );
          continue;
        }
        // Same per-op seam as internal/MCP writes: one transaction + LWW +
        // sync_ops + post-commit notify per op; request order is preserved.
        results.add(
          await applyInternalOp(
            db: db,
            userId: userId,
            op: op,
            notify: notifySeq,
            deviceId: deviceId,
          ),
        );
      }
      final seqAfter = await currentSeq(db, userId);

      final scannedPiggybackRows = await _changesSince(
        db,
        userId,
        afterSeq: push.cursor ?? 0,
        limit: _piggybackLimit,
      );
      final piggybackRows = _filterCapabilities(
        scannedPiggybackRows,
        push.capabilities,
      );
      // Advance by the last raw row scanned, even when capability filtering
      // hides some rows. The next pull resumes after that exact server seq.
      final outCursor = scannedPiggybackRows.isNotEmpty
          ? scannedPiggybackRows.last.seq
          : (push.cursor ?? seqAfter);
      return jsonResponse(
        200,
        PushResponse(
          results: results,
          piggyback: piggybackRows.map(toSyncRecord).toList(),
          cursor: outCursor,
        ).toJson(),
      );
    }),
  );

  router.get(
    '/sync/pull',
    auth.requireAuth((request, context) async {
      final cursor = _parseQueryInt(request, 'cursor', fallback: 0);
      final limit = _parseQueryInt(
        request,
        'limit',
        fallback: _pullDefaultLimit,
      );
      if (cursor < 0) {
        throw ApiException(400, errValidation, 'cursor must be >= 0');
      }
      final pageLimit = limit < 1
          ? 1
          : (limit > _pullMaxLimit ? _pullMaxLimit : limit);
      final capabilities = _queryCapabilities(request);

      final rows =
          await (db.select(db.records)
                ..where(
                  (t) =>
                      t.userId.equals(context.userId) &
                      t.seq.isBiggerThanValue(cursor),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.seq)])
                ..limit(pageLimit + 1))
              .get();
      final hasMore = rows.length > pageLimit;
      final page = hasMore ? rows.sublist(0, pageLimit) : rows;
      final visible = _filterCapabilities(page, capabilities);
      return jsonResponse(
        200,
        PullResponse(
          changes: visible.map(toSyncRecord).toList(),
          nextCursor: page.isEmpty ? cursor : page.last.seq,
          hasMore: hasMore,
        ).toJson(),
      );
    }),
  );
}

Set<String> _queryCapabilities(Request request) =>
    request.url.queryParametersAll['capabilities']
        ?.expand((value) => value.split(','))
        .where((value) => value.isNotEmpty)
        .toSet() ??
    const <String>{};

List<RecordRow> _filterCapabilities(
  List<RecordRow> rows,
  Iterable<String> capabilities,
) {
  return rows.where((row) {
    if (row.type == RecordType.taskAllocation.wireName &&
        !capabilities.contains(SyncCapability.taskAllocationV1)) {
      return false;
    }
    if (row.type == RecordType.taskInstanceState.wireName &&
        !capabilities.contains(SyncCapability.taskInstanceStateV1)) {
      return false;
    }
    return true;
  }).toList();
}

Future<List<RecordRow>> _changesSince(
  AppDatabase db,
  String userId, {
  required int afterSeq,
  required int limit,
}) {
  return (db.select(db.records)
        ..where(
          (t) => t.userId.equals(userId) & t.seq.isBiggerThanValue(afterSeq),
        )
        ..orderBy([(t) => OrderingTerm.asc(t.seq)])
        ..limit(limit))
      .get();
}

/// Best-effort liveness stamp. A push from an unregistered device still
/// applies - registration is not a precondition for syncing, it only decides
/// whether we have a row to stamp.
Future<void> _touchDevice(
  AppDatabase db, {
  required String userId,
  required String deviceId,
}) async {
  if (deviceId.isEmpty) {
    return;
  }
  await (db.update(db.devices)
        ..where((t) => t.deviceId.equals(deviceId) & t.userId.equals(userId)))
      .write(DevicesCompanion(lastSeen: Value(DateTime.now().toUtc())));
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
