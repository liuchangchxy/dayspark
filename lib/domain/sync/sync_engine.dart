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

enum SyncConflictResolution { keepLocal, keepRemote }

/// One record the server refused because this device's base revision was
/// stale. The pending outbox op is kept (not overwritten by the server
/// copy) so a local edit can still be reconciled; banner/settings read
/// this list instead of the conflict disappearing into a server-wins
/// overwrite.
class SyncConflict {
  const SyncConflict({
    required this.recordId,
    required this.type,
    required this.code,
    required this.at,
    this.localPayload,
    this.serverPayload,
    this.serverRev,
    this.serverDeleted = false,
  });

  final String recordId;
  final RecordType? type;
  final String? code;
  final DateTime at;

  /// The fields this device last tried to push, as captured from the outbox.
  final Map<String, Object?>? localPayload;

  /// The server's copy that caused the conflict, when the push response
  /// carried it. Both are display data; two conflicts are equal when their
  /// identity and time match.
  final Map<String, Object?>? serverPayload;
  final int? serverRev;
  final bool serverDeleted;

  bool get hasServerCopy =>
      serverPayload != null || (serverDeleted && serverRev != null);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflict &&
          other.recordId == recordId &&
          other.type == type &&
          other.code == code &&
          other.at == at);

  @override
  int get hashCode => Object.hash(recordId, type, code, at);
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastError,
    this.lastErrorAt,
    this.lastSyncAt,
    this.lastRejected = const [],
    this.rejectedCount = 0,
    this.rejectedCodes = const [],
    this.conflicts = const [],
  });

  final SyncPhase phase;
  final String? lastError;
  final DateTime? lastErrorAt;
  final DateTime? lastSyncAt;

  /// Op verdict codes from the most recent push — `rejected` ops are
  /// dropped (and surfaced here) instead of failing the round.
  final List<String> lastRejected;

  /// Rejected ops never disappear silently: the total is accumulated for
  /// the engine lifetime and [rejectedCodes] keeps the distinct reasons.
  final int rejectedCount;
  final List<String> rejectedCodes;

  /// Conflicts newest-first, one entry per record id.
  final List<SyncConflict> conflicts;

  SyncConflict? get latestConflict =>
      conflicts.isEmpty ? null : conflicts.first;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStatus &&
          other.phase == phase &&
          other.lastError == lastError &&
          other.lastErrorAt == lastErrorAt &&
          other.lastSyncAt == lastSyncAt &&
          other.rejectedCount == rejectedCount &&
          _listEq(other.lastRejected, lastRejected) &&
          _listEq(other.rejectedCodes, rejectedCodes) &&
          _listEq(other.conflicts, conflicts));

  @override
  int get hashCode => Object.hash(
    phase,
    lastError,
    lastErrorAt,
    lastSyncAt,
    rejectedCount,
    Object.hashAll(lastRejected),
    Object.hashAll(rejectedCodes),
    Object.hashAll(conflicts),
  );

  static bool _listEq<T>(List<T> a, List<T> b) {
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
    Future<void> Function()? beforeRound,
  }) : _applier = applier ?? SyncApplier(db),
       _beforeRound = beforeRound {
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

  /// Runs before the outbox is read, so work it enqueues (attachment blob
  /// uploads) rides the same round instead of needing a follow-up. Must not
  /// throw — a round is not the place to surface side-work failures.
  final Future<void> Function()? _beforeRound;

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

  final List<SyncConflict> _conflicts = [];
  final Set<String> _conflictedOpIds = {};
  final Set<String> _rejectedCodes = <String>{};
  int _rejectedCount = 0;

  SyncStatus get status => _status;

  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// True between a successful start() and stop() — the foreground
  /// poller gates on this so a logged-out provider build never arms it.
  bool get isRunning => _started && !_stopped;

  /// Surfaces a failure outside a round (engine/SSE startup) on the same
  /// status stream the UI reads, instead of leaving it in a debug log.
  void reportStartupError(Object error) {
    _emitStatus(
      phase: SyncPhase.error,
      lastError: '$error',
      lastErrorAt: DateTime.now(),
      lastSyncAt: _status.lastSyncAt,
      lastRejected: _status.lastRejected,
    );
  }

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
      final beforeRound = _beforeRound;
      if (beforeRound != null) {
        try {
          await beforeRound();
        } catch (e) {
          debugPrint('sync: pre-round work failed: $e');
        }
      }

      _emitStatus(
        phase: SyncPhase.pushing,
        lastSyncAt: _status.lastSyncAt,
        lastRejected: _status.lastRejected,
      );

      final storedCursor = await cursorStore.read();
      if (storedCursor == null) {
        // First configure: give pre-existing rows an identity + op so
        // local history reaches the server at least once.
        await _baselineSweep();
      }
      final cursor = storedCursor ?? 0;

      final serverCapabilities = (await api.fetchServerCapabilities())
          .capabilities
          .toSet();
      final taskAllocationEnabled = serverCapabilities.contains(
        SyncCapability.taskAllocationV1,
      );
      final todoRecurrenceEnabled = serverCapabilities.contains(
        SyncCapability.todoRecurrenceV1,
      );
      final taskInstanceStateEnabled = serverCapabilities.contains(
        SyncCapability.taskInstanceStateV1,
      );
      final reminderTagAttachmentEnabled = serverCapabilities.contains(
        SyncCapability.reminderTagAttachmentV1,
      );
      final priorTaskAllocationEnabled = await cursorStore
          .readTaskAllocationCapabilityState();
      final capabilityBackfill =
          taskAllocationEnabled && priorTaskAllocationEnabled != true;
      final priorTodoRecurrenceEnabled = await cursorStore
          .readTodoRecurrenceCapabilityState();
      final todoRecurrenceBackfill =
          todoRecurrenceEnabled && priorTodoRecurrenceEnabled != true;
      final priorTaskInstanceStateEnabled = await cursorStore
          .readTaskInstanceStateCapabilityState();
      final taskInstanceStateBackfill =
          taskInstanceStateEnabled && priorTaskInstanceStateEnabled != true;
      final priorReminderTagAttachmentEnabled = await cursorStore
          .readReminderTagAttachmentCapabilityState();
      final reminderTagAttachmentBackfill =
          reminderTagAttachmentEnabled &&
          priorReminderTagAttachmentEnabled != true;
      final roundCursor =
          capabilityBackfill ||
              todoRecurrenceBackfill ||
              taskInstanceStateBackfill ||
              reminderTagAttachmentBackfill
          ? 0
          : cursor;

      // --- push ---
      final entries = await (db.select(
        db.syncOutbox,
      )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
      final (ops, converged) = await _buildOps(
        entries,
        serverCapabilities: serverCapabilities,
      );
      if (converged.isNotEmpty) {
        // Local row already equals the last-known server truth — nothing
        // to send (an empty upsert would be rejected by the server).
        await _dropOps(converged);
      }
      final push = await api.push(
        PushRequest(
          deviceId: deviceId,
          ops: ops,
          cursor: roundCursor,
          capabilities: const [
            SyncCapability.taskAllocationV1,
            SyncCapability.todoRecurrenceV1,
            SyncCapability.taskInstanceStateV1,
            SyncCapability.reminderTagAttachmentV1,
          ],
        ),
      );

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
              final resolvedId = recordIdByOp[result.opId];
              if (resolvedId != null) {
                _conflicts.removeWhere((c) => c.recordId == resolvedId);
              }
            case OpStatus.conflict:
              // Do not overwrite the local row: the pending op is the only
              // copy of this device's newer intent. Keep both the row and
              // its op, stop re-pushing that op until a fresh edit mints a
              // new op id, and surface the conflict to the UI.
              final recordId =
                  recordIdByOp[result.opId] ??
                  result.serverRecord?.id ??
                  result.opId;
              RecordType? conflictType;
              for (final e in entries) {
                if (e.opId == result.opId) {
                  conflictType = recordTypeFromJson(e.type, 'outbox type');
                  break;
                }
              }
              conflictType ??= result.serverRecord?.type;
              Map<String, Object?>? localPayload;
              for (final e in entries) {
                if (e.recordId != recordId || e.payloadJson == null) continue;
                try {
                  final decoded = jsonDecode(e.payloadJson!);
                  if (decoded is Map<String, dynamic>) {
                    localPayload = Map<String, Object?>.from(decoded);
                  }
                } on FormatException catch (error) {
                  debugPrint('sync: unreadable outbox payload: $error');
                }
                break;
              }
              final server = result.serverRecord;
              _conflicts.removeWhere((c) => c.recordId == recordId);
              _conflicts.insert(
                0,
                SyncConflict(
                  recordId: recordId,
                  type: conflictType,
                  code: result.code,
                  at: DateTime.now(),
                  localPayload: localPayload,
                  serverPayload: server?.payload,
                  serverRev: server?.rev,
                  serverDeleted: server?.deleted ?? false,
                ),
              );
              _conflictedOpIds.add(result.opId);
              for (final e in entries) {
                if (e.recordId == recordId) _conflictedOpIds.add(e.opId);
              }
            case OpStatus.rejected:
              await _dropOps([result.opId]);
              _rejectedCount++;
              if (result.code != null) _rejectedCodes.add(result.code!);
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
      _emitStatus(
        phase: SyncPhase.pulling,
        lastSyncAt: _status.lastSyncAt,
        lastRejected: rejected,
      );
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

      // Commit only after the complete push/pull round succeeds. If the
      // capability was newly enabled, the round started at zero and scanned
      // the server's current snapshot (including tombstones).
      await cursorStore.writeTaskAllocationCapabilityState(
        taskAllocationEnabled,
      );
      await cursorStore.writeTodoRecurrenceCapabilityState(
        todoRecurrenceEnabled,
      );
      await cursorStore.writeTaskInstanceStateCapabilityState(
        taskInstanceStateEnabled,
      );
      await cursorStore.writeReminderTagAttachmentCapabilityState(
        reminderTagAttachmentEnabled,
      );

      _backoffSeconds = 1;
      _emitStatus(
        phase: SyncPhase.idle,
        lastSyncAt: DateTime.now(),
        lastRejected: rejected,
      );
      return true;
    } catch (e) {
      _emitStatus(
        phase: SyncPhase.error,
        lastError: '$e',
        lastErrorAt: DateTime.now(),
        lastSyncAt: _status.lastSyncAt,
        lastRejected: _status.lastRejected,
      );
      _scheduleRetry();
      return false;
    }
  }

  Future<(List<PushOp>, List<String>)> _buildOps(
    List<SyncOutboxEntry> entries, {
    required Set<String> serverCapabilities,
  }) async {
    final ops = <PushOp>[];
    final converged = <String>[];
    _conflictedOpIds.removeWhere(
      (id) => !entries.any((entry) => entry.opId == id),
    );
    for (final entry in entries) {
      if (_conflictedOpIds.contains(entry.opId)) continue;
      final type = recordTypeFromJson(entry.type, 'outbox type');
      if (type == RecordType.taskAllocation &&
          !serverCapabilities.contains(SyncCapability.taskAllocationV1)) {
        continue;
      }
      if (type == RecordType.taskInstanceState &&
          !serverCapabilities.contains(SyncCapability.taskInstanceStateV1)) {
        continue;
      }
      if (_reminderTagAttachmentTypes.contains(type) &&
          !serverCapabilities.contains(
            SyncCapability.reminderTagAttachmentV1,
          )) {
        continue;
      }
      var baseRev = entry.baseRev;
      var fields = entry.payloadJson == null
          ? null
          : jsonDecode(entry.payloadJson!) as Map<String, dynamic>;
      if (entry.op == OpType.upsert.name) {
        // baseRev is the record's CURRENT last-known server rev — the
        // applier may have advanced it after this op was enqueued.
        baseRev = await _liveServerRev(type, entry.recordId) ?? baseRev;
        final snapshot = await snapshots.read(entry.recordId);
        if (snapshot != null &&
            fields != null &&
            type != RecordType.taskInstanceState) {
          final dirty = dirtyFields(fields, snapshot.payload);
          if (dirty.isEmpty) {
            converged.add(entry.opId);
            continue;
          }
          fields = dirty;
        }
      }
      ops.add(
        PushOp(
          opId: entry.opId,
          op: OpType.values.byName(entry.op),
          recordId: entry.recordId,
          type: type,
          fields: fields,
          baseRev: baseRev,
        ),
      );
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

  /// The user chose this device's version. The stored server payload becomes
  /// the new diff base and the gated outbox op is released, so the next round
  /// re-applies this device's fields on top of the server's latest revision.
  /// If the server copy was not returned, nothing is invented: the conflict
  /// stays visible.
  Future<void> resolveConflictKeepLocal(String recordId) async {
    final conflict = _conflicts
        .where((c) => c.recordId == recordId)
        .firstOrNull;
    if (conflict == null) return;
    final server = conflict.serverPayload;
    final rev = conflict.serverRev;
    if (server == null || rev == null) {
      if (!conflict.serverDeleted) {
        throw StateError('the server copy is unavailable');
      }
      await snapshots.remove(recordId);
    } else {
      await snapshots.write(
        recordId,
        SyncSnapshot(rev: rev, payload: server),
      );
    }

    final entries = await (db.select(
      db.syncOutbox,
    )..where((t) => t.recordId.equals(recordId))).get();
    if (entries.isEmpty) {
      _forgetConflict(recordId);
      throw StateError('this record no longer has a pending local change');
    }
    for (final entry in entries) {
      _conflictedOpIds.remove(entry.opId);
    }
    if (rev != null) {
      await (db.update(
        db.syncOutbox,
      )..where((t) => t.recordId.equals(recordId))).write(
        SyncOutboxCompanion(baseRev: Value(rev)),
      );
    }
    _forgetConflict(recordId);
    _emitCurrentStatus();
    await requestRound();
  }

  /// The user chose the server's version. Apply that exact copy locally and
  /// drop this record's pending op; no merge and no re-push.
  Future<void> resolveConflictKeepRemote(String recordId) async {
    final conflict = _conflicts
        .where((c) => c.recordId == recordId)
        .firstOrNull;
    if (conflict == null) return;
    final type = conflict.type;
    if (type == null) throw StateError('the conflict has no record type');
    if (conflict.serverDeleted && conflict.serverRev == null) {
      throw StateError('the server copy is unavailable');
    }
    if (!conflict.serverDeleted && conflict.serverPayload == null) {
      throw StateError('the server copy is unavailable');
    }

    await RecordScope.run(db, (tx) async {
      final entries = await (db.select(
        db.syncOutbox,
      )..where((t) => t.recordId.equals(recordId))).get();
      await _dropOps(entries.map((e) => e.opId).toList(growable: false));
      await _applyRemote(
        SyncRecord(
          id: recordId,
          type: type,
          payload: conflict.serverPayload ?? const {},
          rev: conflict.serverRev ?? 0,
          deleted: conflict.serverDeleted,
          serverTs: conflict.at,
        ),
        tx,
      );
    });
    _forgetConflict(recordId);
    _emitCurrentStatus();
    await requestRound();
  }

  void _forgetConflict(String recordId) {
    _conflicts.removeWhere((c) => c.recordId == recordId);
    // Any op id still parked for this record is pruned from the gate by the
    // next _buildOps (ids no longer present in the outbox are dropped), and
    // keepRemote has already deleted the rows outright.
  }

  void _emitCurrentStatus() {
    _emitStatus(
      phase: _status.phase,
      lastError: _status.lastError,
      lastErrorAt: _status.lastErrorAt,
      lastSyncAt: _status.lastSyncAt,
      lastRejected: _status.lastRejected,
    );
  }

  Future<int?> _liveServerRev(RecordType type, String recordId) async {
    if (type == RecordType.event) {
      final row = await (db.select(
        db.events,
      )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
      return row?.serverRev;
    }
    if (type == RecordType.taskAllocation) {
      final row = await (db.select(
        db.taskAllocations,
      )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
      return row?.serverRev;
    }
    if (type == RecordType.taskInstanceState) {
      final row = await (db.select(
        db.taskInstanceStates,
      )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
      return row?.serverRev;
    }
    if (type == RecordType.reminder) {
      final row = await (db.select(
        db.reminders,
      )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
      return row?.serverRev;
    }
    if (type == RecordType.tag) {
      final row = await (db.select(
        db.tags,
      )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
      return row?.serverRev;
    }
    if (type == RecordType.attachment) {
      final row = await (db.select(
        db.attachments,
      )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
      return row?.serverRev;
    }
    final row = await (db.select(
      db.todos,
    )..where((t) => t.syncId.equals(recordId))).getSingleOrNull();
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
    final events = await (db.select(
      db.events,
    )..where((t) => t.syncId.isNull() & t.deletedAt.isNull())).get();
    for (final row in events) {
      await SyncOutbox.enqueueUpsert(db, RecordType.event, row.id);
    }
    final todos = await (db.select(
      db.todos,
    )..where((t) => t.syncId.isNull() & t.deletedAt.isNull())).get();
    for (final row in todos) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, row.id);
    }
    final allocations = await (db.select(
      db.taskAllocations,
    )..where((t) => t.syncId.isNull())).get();
    for (final row in allocations) {
      await SyncOutbox.enqueueUpsert(db, RecordType.taskAllocation, row.id);
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

  void _emitStatus({
    required SyncPhase phase,
    String? lastError,
    DateTime? lastErrorAt,
    DateTime? lastSyncAt,
    List<String> lastRejected = const [],
  }) {
    _emit(
      SyncStatus(
        phase: phase,
        lastError: lastError,
        lastErrorAt: lastErrorAt,
        lastSyncAt: lastSyncAt,
        lastRejected: lastRejected,
        rejectedCount: _rejectedCount,
        rejectedCodes: List.unmodifiable(_rejectedCodes),
        conflicts: List.unmodifiable(_conflicts),
      ),
    );
  }

  void _emit(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}

const _reminderTagAttachmentTypes = {
  RecordType.reminder,
  RecordType.tag,
  RecordType.tagAssociation,
  RecordType.attachment,
};
