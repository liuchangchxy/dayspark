import 'package:dayspark_contracts/dayspark_contracts.dart';

/// Wire format of the single document a cloud-drive transport keeps in the
/// user's drive. Everything the DaySpark server would hold in its records
/// table lives here instead, because a drive has no server to arbitrate:
/// the client merges locally and the conditional write (ETag / rev) is the
/// only thing serialising writers.
const String cloudStateFormat = 'dayspark.cloud.v1';

class CloudRecordEntry {
  const CloudRecordEntry({required this.record, required this.lastOpId});

  factory CloudRecordEntry.fromJson(Map<String, dynamic> json) {
    final lastOpId = json['lastOpId'];
    if (lastOpId is! String || lastOpId.isEmpty) {
      throw const FormatException('cloud record missing lastOpId');
    }
    return CloudRecordEntry(
      record: SyncRecord.fromJson(json),
      lastOpId: lastOpId,
    );
  }

  final SyncRecord record;

  /// Mirrors the server's `records.last_op_id`: the tie-breaker when a
  /// resurrect races a tombstone inside the same second.
  final String lastOpId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...record.toJson(),
    'lastOpId': lastOpId,
  };
}

class CloudSyncState {
  const CloudSyncState({
    required this.seq,
    required this.mergedAt,
    required this.records,
  });

  factory CloudSyncState.empty() =>
      CloudSyncState(seq: 0, mergedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), records: const {});

  factory CloudSyncState.fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format != cloudStateFormat) {
      throw FormatException('unsupported cloud state format: $format');
    }
    final seq = json['seq'];
    final mergedAt = json['mergedAt'];
    final records = json['records'];
    if (seq is! int) throw const FormatException('cloud state missing seq');
    if (mergedAt is! String) {
      throw const FormatException('cloud state missing mergedAt');
    }
    if (records is! Map) {
      throw const FormatException('cloud state missing records');
    }
    return CloudSyncState(
      seq: seq,
      mergedAt: DateTime.parse(mergedAt).toUtc(),
      records: <String, CloudRecordEntry>{
        for (final entry in records.entries)
          entry.key as String: CloudRecordEntry.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
    );
  }

  final int seq;

  /// Write time of the last accepted merge. The next merge is placed strictly
  /// after it, so a re-merge after a lost race can never lose the
  /// arrival-order comparison to the state it just observed.
  final DateTime mergedAt;

  final Map<String, CloudRecordEntry> records;

  /// Records the peer must be told about — everything, since the document is
  /// a full snapshot rather than a change log.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': cloudStateFormat,
    'seq': seq,
    'mergedAt': mergedAt.toUtc().toIso8601String(),
    'records': <String, dynamic>{
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    },
  };

  CloudSyncState copyWith({
    int? seq,
    DateTime? mergedAt,
    Map<String, CloudRecordEntry>? records,
  }) => CloudSyncState(
    seq: seq ?? this.seq,
    mergedAt: mergedAt ?? this.mergedAt,
    records: records ?? this.records,
  );
}

/// One pending local write, already reduced to the fields this device
/// actually changed (see `dirtyFields` in sync_payload.dart).
class CloudOp {
  const CloudOp({
    required this.opId,
    required this.recordId,
    required this.type,
    required this.op,
    required this.fields,
    required this.baseRev,
  });

  final String opId;
  final String recordId;
  final RecordType type;
  final OpType op;
  final Map<String, dynamic>? fields;
  final int baseRev;
}

enum CloudOpStatus { applied, conflict }

class CloudOpResult {
  const CloudOpResult(this.opId, this.status);

  final String opId;
  final CloudOpStatus status;
}

class CloudMergeOutcome {
  const CloudMergeOutcome({required this.state, required this.results});

  final CloudSyncState state;
  final List<CloudOpResult> results;

  List<String> get appliedOpIds => [
    for (final result in results)
      if (result.status == CloudOpStatus.applied) result.opId,
  ];

  List<String> get conflictedOpIds => [
    for (final result in results)
      if (result.status == CloudOpStatus.conflict) result.opId,
  ];
}

/// Applies [ops] to [state] the way the DaySpark server applies a push:
/// field-level last-writer-wins in arrival order, rev+1 per accepted write,
/// and a tombstone that a resurrect only beats when it is newer (or wins the
/// same-second opId tie).
///
/// [now] is the writer's clock, the only clock available without a server.
/// It is pushed strictly past the document's own [CloudSyncState.mergedAt], so
/// the order a re-merge observes is always the order it writes.
CloudMergeOutcome mergeCloudOps({
  required CloudSyncState state,
  required List<CloudOp> ops,
  required DateTime now,
}) {
  if (ops.isEmpty) {
    return CloudMergeOutcome(state: state, results: const []);
  }
  final opTs = nextCloudWriteTime(state: state, now: now);
  final records = Map<String, CloudRecordEntry>.from(state.records);
  final results = <CloudOpResult>[];
  for (final op in ops) {
    final existing = records[op.recordId];
    if (existing != null && existing.record.type != op.type) {
      results.add(CloudOpResult(op.opId, CloudOpStatus.conflict));
      continue;
    }
    if (op.op == OpType.delete) {
      records[op.recordId] = CloudRecordEntry(
        record: SyncRecord(
          id: op.recordId,
          type: op.type,
          payload: existing?.record.payload ?? const <String, dynamic>{},
          rev: (existing?.record.rev ?? 0) + 1,
          deleted: true,
          serverTs: opTs,
        ),
        lastOpId: op.opId,
      );
      results.add(CloudOpResult(op.opId, CloudOpStatus.applied));
      continue;
    }
    if (existing != null && existing.record.deleted) {
      final decision = decideTombstoneVsUpsert(
        recordServerTs: existing.record.serverTs,
        opTs: opTs,
        recordLastOpId: existing.lastOpId,
        incomingOpId: op.opId,
      );
      if (decision == TombstoneUpsertDecision.conflict) {
        results.add(CloudOpResult(op.opId, CloudOpStatus.conflict));
        continue;
      }
    }
    records[op.recordId] = CloudRecordEntry(
      record: SyncRecord(
        id: op.recordId,
        type: op.type,
        payload: mergeFields(existing?.record.payload ?? const {}, op.fields),
        rev: (existing?.record.rev ?? 0) + 1,
        deleted: false,
        serverTs: opTs,
      ),
      lastOpId: op.opId,
    );
    results.add(CloudOpResult(op.opId, CloudOpStatus.applied));
  }
  return CloudMergeOutcome(
    state: CloudSyncState(
      seq: state.seq + 1,
      mergedAt: opTs,
      records: records,
    ),
    results: results,
  );
}

/// One merge round is one write, so every op in it shares a timestamp.
/// Second granularity matches [decideTombstoneVsUpsert]'s comparison.
DateTime nextCloudWriteTime({
  required CloudSyncState state,
  required DateTime now,
}) {
  final wall = truncateToSecond(now);
  final floor = state.mergedAt.add(const Duration(seconds: 1));
  return wall.isAfter(floor) ? wall : floor;
}
