import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';

import '../sync_applier.dart';
import '../sync_config.dart';
import '../sync_engine.dart' show SyncPhase, SyncStatus;
import '../sync_outbox.dart';
import '../sync_payload.dart';
import 'cloud_sync_backend.dart';
import 'cloud_sync_settings.dart';
import 'cloud_sync_state.dart';

/// The provider-neutral half of cloud-drive sync: one document, read →
/// merge → conditional write → apply. Every provider contributes only a
/// [CloudSyncBackend]; none of them gets its own algorithm.
///
/// Differences from [SyncEngine] (the self-hosted transport), and why:
/// - There is no server clock, so the merge timestamp is this device's clock
///   pushed past the document's own `mergedAt` (see [nextCloudWriteTime]).
/// - There is no server to assign op verdicts, so the merge runs locally and
///   the conditional write is what turns a lost race into a retry instead of
///   a silent overwrite.
/// - There is no cursor: the document is a full snapshot, so "pull" is
///   "apply every record whose rev differs from the last one we applied".
class CloudSyncEngine {
  CloudSyncEngine({
    required this.db,
    required this.backend,
    required this.snapshots,
    required this.stateStore,
    SyncApplier? applier,
    DateTime Function()? clock,
  }) : _applier = applier ?? SyncApplier(db),
       _clock = clock ?? DateTime.now {
    _statusController = StreamController<SyncStatus>.broadcast(
      onListen: () => _statusController.add(_status),
    );
  }

  /// A conditional write that keeps losing means the peer is writing faster
  /// than we can merge; give up this round and let the retry timer re-run it
  /// instead of spinning.
  static const int maxMergeRetries = 3;

  final AppDatabase db;
  final CloudSyncBackend backend;
  final SyncSnapshotStore snapshots;
  final CloudSyncStateStore stateStore;
  final SyncApplier _applier;
  final DateTime Function() _clock;

  SyncStatus _status = const SyncStatus();
  late final StreamController<SyncStatus> _statusController;
  StreamSubscription? _outboxSub;
  Timer? _kickTimer;
  Timer? _retryTimer;
  bool _started = false;
  bool _stopped = false;
  bool _roundRunning = false;
  bool _roundQueued = false;
  int _backoffSeconds = 1;

  SyncStatus get status => _status;
  Stream<SyncStatus> get statusStream => _statusController.stream;
  bool get isRunning => _started && !_stopped;

  Future<void> start() async {
    if (_started || _stopped) return;
    _started = true;
    _outboxSub = db
        .tableUpdates(TableUpdateQuery.onTable(db.syncOutbox))
        .listen((_) => _onOutboxEvent());
    await requestRound();
  }

  Future<void> stop() async {
    _stopped = true;
    _kickTimer?.cancel();
    _retryTimer?.cancel();
    await _outboxSub?.cancel();
    if (!_statusController.isClosed) await _statusController.close();
  }

  /// Manual "sync now": one round, awaited, no retry timer involvement.
  /// Coalesces with the automatic rounds the same way they coalesce with each
  /// other, so a tap during an in-flight round cannot start a second one.
  Future<bool> syncNow() async {
    if (_stopped) return false;
    if (_roundRunning) return true;
    _roundRunning = true;
    try {
      return await _runRound();
    } finally {
      _roundRunning = false;
    }
  }

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
    _kickTimer?.cancel();
    _kickTimer = Timer(const Duration(milliseconds: 50), () async {
      if (_stopped || !_started) return;
      final pending = await (db.select(db.syncOutbox)).get();
      if (pending.isNotEmpty) await requestRound();
    });
  }

  Future<bool> _runRound() async {
    final startedAt = _clock();
    try {
      _emit(
        SyncStatus(phase: SyncPhase.pushing, lastSyncAt: _status.lastSyncAt),
      );

      if (!await stateStore.isProvisioned()) {
        await _baselineSweep();
      }

      final entries = await (db.select(
        db.syncOutbox,
      )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
      final converged = <String>[];
      final ops = await _buildOps(entries, converged);
      if (converged.isNotEmpty) await _dropOps(converged);

      var directoryReady = false;
      for (var attempt = 0; ; attempt++) {
        final file = await backend.read();
        final remote = file == null
            ? CloudSyncState.empty()
            : CloudSyncState.fromJson(
                jsonDecode(file.body) as Map<String, dynamic>,
              );
        final outcome = mergeCloudOps(state: remote, ops: ops, now: _clock());
        if (file == null && !directoryReady) {
          await backend.ensureReady();
          directoryReady = true;
        }
        if (ops.isEmpty && file != null) {
          // Nothing local to send: the document is the truth, so apply only
          // what this device has not applied yet. Writing an identical body
          // would bump the validator and make the peer re-read for nothing.
          await _commit(
            ops: ops,
            outcome: outcome,
            etag: file.etag,
            at: startedAt,
          );
          _emit(
            SyncStatus(
              phase: SyncPhase.idle,
              lastSyncAt: startedAt,
              lastRejected: _status.lastRejected,
            ),
          );
          return true;
        }
        try {
          final etag = await backend.write(
            body: jsonEncode(outcome.state.toJson()),
            ifMatch: file?.etag,
          );
          await _commit(ops: ops, outcome: outcome, etag: etag, at: startedAt);
          _backoffSeconds = 1;
          _emit(
            SyncStatus(
              phase: SyncPhase.idle,
              lastSyncAt: startedAt,
              lastRejected: outcome.conflictedOpIds.isEmpty
                  ? _status.lastRejected
                  : const ['conflict'],
            ),
          );
          return true;
        } on CloudPreconditionFailed {
          if (attempt + 1 >= maxMergeRetries) rethrow;
          _emit(
            SyncStatus(
              phase: SyncPhase.pushing,
              lastSyncAt: _status.lastSyncAt,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('cloud sync: round failed: $e');
      _emit(
        SyncStatus(
          phase: SyncPhase.error,
          lastError: '$e',
          lastSyncAt: _status.lastSyncAt,
          lastRejected: _status.lastRejected,
        ),
      );
      _scheduleRetry();
      return false;
    }
  }

  Future<void> _commit({
    required List<CloudOp> ops,
    required CloudMergeOutcome outcome,
    required String etag,
    required DateTime at,
  }) async {
    final recordIdByOp = {for (final op in ops) op.opId: op.recordId};
    final conflicted = <String>{
      for (final result in outcome.results)
        if (result.status == CloudOpStatus.conflict)
          if (recordIdByOp[result.opId] != null) recordIdByOp[result.opId]!,
    };
    await RecordScope.run(db, (tx) async {
      for (final entry in outcome.state.records.values) {
        final record = entry.record;
        final snapshot = await snapshots.read(record.id);
        final forced = conflicted.contains(record.id);
        if (!forced && snapshot != null && snapshot.rev == record.rev) {
          continue;
        }
        final applied = await _applier.apply(record, tx);
        if (record.deleted) {
          await snapshots.remove(record.id);
        } else if (applied || forced) {
          await snapshots.write(
            record.id,
            SyncSnapshot(rev: record.rev, payload: record.payload),
          );
        }
      }
      await _dropOps([for (final result in outcome.results) result.opId]);
    });
    await stateStore.writeEtag(etag);
    if (!await stateStore.isProvisioned()) {
      await stateStore.markProvisioned();
    }
    await stateStore.writeLastSyncAt(at);
  }

  Future<List<CloudOp>> _buildOps(
    List<SyncOutboxEntry> entries,
    List<String> converged,
  ) async {
    final ops = <CloudOp>[];
    for (final entry in entries) {
      final type = recordTypeFromJson(entry.type, 'outbox type');
      var fields = entry.payloadJson == null
          ? null
          : jsonDecode(entry.payloadJson!) as Map<String, dynamic>;
      if (entry.op == OpType.upsert.name) {
        final snapshot = await snapshots.read(entry.recordId);
        // taskInstanceState is a whole small state (status/completedAt/
        // updatedAt) arbitrated by updatedAt, not a field union — diffing it
        // against the snapshot could drop the very field that wins.
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
        CloudOp(
          opId: entry.opId,
          recordId: entry.recordId,
          type: type,
          op: OpType.values.byName(entry.op),
          fields: fields,
          baseRev: entry.baseRev ?? 0,
        ),
      );
    }
    return ops;
  }

  /// Gives every local row an op so the destination receives the full
  /// dataset on first configure and after a source switch.
  ///
  /// Enqueues rows that already have a syncId too: a switch keeps the rows but
  /// drops the snapshots that made them look converged, and a row that is only
  /// re-enqueued when it changes would never reach the new destination. Covers
  /// all synced types, unlike the server transport's sweep, because a drive has
  /// no capability backfill to catch what was never enqueued.
  Future<void> _baselineSweep() => RecordScope.run(db, (_) async {
    final events = await (db.select(
      db.events,
    )..where((t) => t.deletedAt.isNull())).get();
    for (final row in events) {
      await SyncOutbox.enqueueUpsert(db, RecordType.event, row.id);
    }
    final todos = await (db.select(
      db.todos,
    )..where((t) => t.deletedAt.isNull())).get();
    for (final row in todos) {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, row.id);
    }
    final allocations = await db.select(db.taskAllocations).get();
    for (final row in allocations) {
      await SyncOutbox.enqueueUpsert(db, RecordType.taskAllocation, row.id);
    }
    final instances = await db.select(db.taskInstanceStates).get();
    for (final row in instances) {
      await SyncOutbox.enqueueUpsert(db, RecordType.taskInstanceState, row.id);
    }
    final reminders = await db.select(db.reminders).get();
    for (final row in reminders) {
      await SyncOutbox.enqueueUpsert(db, RecordType.reminder, row.id);
    }
    final tags = await db.select(db.tags).get();
    for (final row in tags) {
      await SyncOutbox.enqueueUpsert(db, RecordType.tag, row.id);
    }
    final attachments = await db.select(db.attachments).get();
    for (final row in attachments) {
      await SyncOutbox.enqueueUpsert(db, RecordType.attachment, row.id);
    }
    final eventTags = await db.select(db.eventTags).get();
    for (final row in eventTags) {
      await SyncOutbox.enqueueTagAssociationUpsert(
        db,
        parentType: 'event',
        parentId: row.eventId,
        tagId: row.tagId,
      );
    }
    final todoTags = await db.select(db.todoTags).get();
    for (final row in todoTags) {
      await SyncOutbox.enqueueTagAssociationUpsert(
        db,
        parentType: 'todo',
        parentId: row.todoId,
        tagId: row.tagId,
      );
    }
  });

  Future<void> _dropOps(List<String> opIds) async {
    if (opIds.isEmpty) return;
    await (db.delete(db.syncOutbox)..where((t) => t.opId.isIn(opIds))).go();
  }

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
