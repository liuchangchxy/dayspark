import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';

import 'sync_api_client.dart';
import 'sync_applier.dart';
import 'sync_config.dart';
import 'sync_outbox.dart';
import 'sync_payload.dart';

enum SyncPhase { idle, pushing, pulling, error }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastError,
    this.lastSyncAt,
    this.lastRejected = const [],
  });

  final SyncPhase phase;
  final String? lastError;
  final DateTime? lastSyncAt;

  /// Op verdict codes from the most recent push — `rejected` ops are
  /// dropped (and surfaced here) instead of failing the round.
  final List<String> lastRejected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStatus &&
          other.phase == phase &&
          other.lastError == lastError &&
          other.lastSyncAt == lastSyncAt &&
          _listEq(other.lastRejected, lastRejected));

  @override
  int get hashCode => Object.hash(phase, lastError, lastSyncAt, Object.hashAll(lastRejected));

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Serialized sync rounds: drain outbox → push → adopt watermark → pull
/// until hasMore. Errors back off 1s → 60s and retry; triggers (outbox
/// writes, remote cursor signals, connectivity regain) coalesce into one
/// queued round.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.api,
    required this.cursorStore,
    required this.tokenStore,
    required this.snapshots,
    required this.deviceId,
    SyncApplier? applier,
  }) : _applier = applier ?? SyncApplier(db) {
    _statusController = StreamController<SyncStatus>.broadcast(
      onListen: () => _statusController.add(_status),
    );
  }

  final AppDatabase db;
  final SyncApiClient api;
  final SyncCursorStore cursorStore;
  final SyncTokenStore tokenStore;

  /// Last-known server payload per record — diffs push ops down to the
  /// fields this device actually changed (see [dirtyFields]).
  final SyncSnapshotStore snapshots;
  final String deviceId;
  final SyncApplier _applier;

  SyncStatus _status = const SyncStatus();
  late final StreamController<SyncStatus> _statusController;
  StreamSubscription? _outboxSub;
  Timer? _retryTimer;
  Timer? _outboxKickTimer;
  bool _started = false;
  bool _stopped = false;
  bool _roundRunning = false;
  bool _roundQueued = false;
  int _backoffSeconds = 1;

  SyncStatus get status => _status;

  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// True between a successful start() and stop() — the foreground
  /// poller gates on this so a logged-out provider build never arms it.
  bool get isRunning => _started && !_stopped;

  /// Wires the outbox trigger and runs the first round. No-ops until
  /// tokens exist ("engine runs only when configured"): T6 login writes
  /// the token pair and invalidates the engine provider to (re)start.
  Future<void> start() async {
    if (_started || _stopped) return;
    if (!await tokenStore.isConfigured()) return;
    if (_stopped) return;
    _started = true;
    _outboxSub = db
        .tableUpdates(TableUpdateQuery.onTable(db.syncOutbox))
        .listen((_) => _onOutboxEvent());
    await requestRound();
  }

  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _outboxKickTimer?.cancel();
    await _outboxSub?.cancel();
    if (!_statusController.isClosed) await _statusController.close();
  }

  /// SSE / connectivity seam: run a round when the remote head moved past
  /// our stored watermark.
  Future<void> notifyRemoteCursor(int cursor) async {
    final stored = await cursorStore.read() ?? 0;
    if (cursor > stored) await requestRound();
  }

  /// SSE self-heal, called with the INITIAL head signal of each
  /// (re)connection. WHY: the server may have been restored from a backup
  /// OLDER than this client — its head then sits BELOW our stored
  /// watermark, and pull (which only returns seq > cursor) would return
  /// nothing forever: a silent permanent stall. Rewind the cursor to the
  /// server head and round from there so post-restore changes flow again.
  /// Later signals are forward advances and must never rewind — only the
  /// initial head of a connection may.
  Future<void> adoptServerHead(int serverHead) async {
    final stored = await cursorStore.read();
    if (stored == null || serverHead >= stored) return;
    await cursorStore.write(serverHead);
    await requestRound();
  }

  /// Coalesces concurrent triggers: one round runs, at most one follow-up
  /// is queued behind it.
  Future<void> requestRound() async {
    if (!_started || _stopped) return;
    if (_roundRunning) {
      _roundQueued = true;
      return;
    }
    _roundRunning = true;
    try {
      do {
        _roundQueued = false;
        final ok = await _runRound();
        if (!ok) break;
      } while (_roundQueued && !_stopped);
    } finally {
      _roundRunning = false;
    }
  }

  void _onOutboxEvent() {
    // Debounced so the round's own drain writes (baseline enqueue, op
    // drops) settle first: re-kick only when ops are still pending once
    // the burst goes quiet — fresh mid-round enqueues queue the next round.
    _outboxKickTimer?.cancel();
    _outboxKickTimer = Timer(const Duration(milliseconds: 50), () async {
      if (_stopped || !_started) return;
      final pending = await (db.select(db.syncOutbox)).get();
      if (pending.isNotEmpty) await requestRound();
    });
  }

  Future<bool> _runRound() async {
    try {
      _emit(SyncStatus(
        phase: SyncPhase.pushing,
        lastSyncAt: _status.lastSyncAt,
        lastRejected: _status.lastRejected,
      ));

      final storedCursor = await cursorStore.read();
      if (storedCursor == null) {
        // First configure: give pre-existing rows an identity + op so
        // local history reaches the server at least once.
        await _baselineSweep();
      }
      final cursor = storedCursor ?? 0;

      // --- push ---
      final entries = await (db.select(db.syncOutbox)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
      final (ops, converged) = await _buildOps(entries);
      if (converged.isNotEmpty) {
        // Local row already equals the last-known server truth — nothing
        // to send (an empty upsert would be rejected by the server).
        await _dropOps(converged);
      }
      final push = await api.push(PushRequest(
        deviceId: deviceId,
        ops: ops,
        cursor: cursor,
      ));

      final rejected = <String>[];
      await RecordScope.run(db, (tx) async {
        final recordIdByOp = {for (final e in entries) e.opId: e.recordId};
        for (final result in push.results) {
          switch (result.status) {
            case OpStatus.applied:
            case OpStatus.duplicate:
              if (result.serverRecord != null) {
                await _applyRemote(result.serverRecord!, tx);
              }
              await _dropOps([result.opId]);
            case OpStatus.conflict:
              // Server wins: overwrite local with serverRecord and drop
              // this record's pending ops from the push snapshot. Ops
              // enqueued after the snapshot (in-flight race) survive and
              // push their newer payload next round.
              if (result.serverRecord != null) {
                await _applyRemote(result.serverRecord!, tx);
              }
              final recordId = recordIdByOp[result.opId] ??
                  result.serverRecord?.id;
              final snapshotIds = [
                if (recordId != null)
                  for (final e in entries)
                    if (e.recordId == recordId) e.opId,
              ];
              await _dropOps(snapshotIds.isNotEmpty
                  ? snapshotIds
                  : [result.opId]);
            case OpStatus.rejected:
              await _dropOps([result.opId]);
              rejected.add(result.code ?? 'rejected');
          }
        }
        // Watermark rule: piggyback covers everything (oldCursor, push.cursor];
        // applying it and adopting push.cursor together keeps no gap.
        for (final record in push.piggyback) {
          await _applyRemote(record, tx);
        }
        await cursorStore.write(push.cursor);
      });

      // --- pull ---
      _emit(SyncStatus(
        phase: SyncPhase.pulling,
        lastSyncAt: _status.lastSyncAt,
        lastRejected: rejected,
      ));
      while (true) {
        final before = await cursorStore.read() ?? 0;
        final pull = await api.pull(before);
        await RecordScope.run(db, (tx) async {
          for (final change in pull.changes) {
            await _applyRemote(change, tx);
          }
          await cursorStore.write(pull.nextCursor);
        });
        if (!pull.hasMore) break;
        if (pull.nextCursor <= before) {
          debugPrint('sync: pull cursor did not advance, stopping');
          break;
        }
      }

      _backoffSeconds = 1;
      _emit(SyncStatus(
        phase: SyncPhase.idle,
        lastSyncAt: DateTime.now(),
        lastRejected: rejected,
      ));
      return true;
    } catch (e) {
      _emit(SyncStatus(
        phase: SyncPhase.error,
        lastError: '$e',
        lastSyncAt: _status.lastSyncAt,
        lastRejected: _status.lastRejected,
      ));
      _scheduleRetry();
      return false;
    }
  }

  Future<(List<PushOp>, List<String>)> _buildOps(
    List<SyncOutboxEntry> entries,
  ) async {
    final ops = <PushOp>[];
    final converged = <String>[];
    for (final entry in entries) {
      final type = RecordType.values.byName(entry.type);
      var baseRev = entry.baseRev;
      var fields = entry.payloadJson == null
          ? null
          : jsonDecode(entry.payloadJson!) as Map<String, dynamic>;
      if (entry.op == OpType.upsert.name) {
        // baseRev is the record's CURRENT last-known server rev — the
        // applier may have advanced it after this op was enqueued.
        baseRev = await _liveServerRev(type, entry.recordId) ?? baseRev;
        final snapshot = await snapshots.read(entry.recordId);
        if (snapshot != null && fields != null) {
          final dirty = dirtyFields(fields, snapshot.payload);
          if (dirty.isEmpty) {
            converged.add(entry.opId);
            continue;
          }
          fields = dirty;
        }
      }
      ops.add(PushOp(
        opId: entry.opId,
        op: OpType.values.byName(entry.op),
        recordId: entry.recordId,
        type: type,
        fields: fields,
        baseRev: baseRev,
      ));
    }
    return (ops, converged);
  }

  /// Writes server truth onto the local row and records the payload as
  /// the diff base for this record's future pushes.
  Future<void> _applyRemote(SyncRecord record, RecordScope tx) async {
    final applied = await _applier.apply(record, tx);
    if (record.deleted) {
      await snapshots.remove(record.id);
    } else if (applied) {
      await snapshots.write(
        record.id,
        SyncSnapshot(rev: record.rev, payload: record.payload),
      );
    }
  }

  Future<int?> _liveServerRev(RecordType type, String recordId) async {
    if (type == RecordType.event) {
      final row = await (db.select(db.events)
            ..where((t) => t.syncId.equals(recordId)))
          .getSingleOrNull();
      return row?.serverRev;
    }
    final row = await (db.select(db.todos)
          ..where((t) => t.syncId.equals(recordId)))
        .getSingleOrNull();
    return row?.serverRev;
  }

  Future<void> _dropOps(List<String> opIds) async {
    if (opIds.isEmpty) return;
    await (db.delete(db.syncOutbox)..where((t) => t.opId.isIn(opIds))).go();
  }

  // 身份回填只改 syncId，参考时间与父状态都没变 → 有意空登记（空批被 publish
  // 丢弃，不发事件）。仍经 RecordScope 开事务：SPEC §3.5 规则 1 的口径是"一切
  // events/todos 行写入都在缝里"，与要不要发事件是两回事。
  Future<void> _baselineSweep() => RecordScope.run(db, (_) async {
        final events = await (db.select(db.events)
              ..where((t) => t.syncId.isNull() & t.deletedAt.isNull()))
            .get();
        for (final row in events) {
          await SyncOutbox.enqueueUpsert(db, RecordType.event, row.id);
        }
        final todos = await (db.select(db.todos)
              ..where((t) => t.syncId.isNull() & t.deletedAt.isNull()))
            .get();
        for (final row in todos) {
          await SyncOutbox.enqueueUpsert(db, RecordType.todo, row.id);
        }
      });

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _backoffSeconds;
    _backoffSeconds = min(_backoffSeconds * 2, 60);
    _retryTimer = Timer(Duration(seconds: delay), () {
      if (!_stopped) unawaited(requestRound());
    });
  }

  void _emit(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}
