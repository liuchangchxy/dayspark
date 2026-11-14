import 'package:dayspark/domain/sync/cloud/cloud_sync_state.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

CloudOp _upsert({
  String opId = 'op-a',
  String recordId = 'todo-1',
  RecordType type = RecordType.todo,
  Map<String, dynamic>? fields,
}) => CloudOp(
  opId: opId,
  recordId: recordId,
  type: type,
  op: OpType.upsert,
  fields: fields ?? const {'summary': 'from-a'},
  baseRev: 0,
);

CloudOp _delete({
  String opId = 'op-del',
  String recordId = 'todo-1',
  RecordType type = RecordType.todo,
}) => CloudOp(
  opId: opId,
  recordId: recordId,
  type: type,
  op: OpType.delete,
  fields: null,
  baseRev: 0,
);

CloudSyncState _stateWith(CloudRecordEntry entry) => CloudSyncState(
  seq: 1,
  mergedAt: DateTime.utc(2026, 11, 14, 9),
  records: {entry.record.id: entry},
);

void main() {
  final now = DateTime.utc(2026, 11, 14, 10);

  test('an upsert writes its fields and bumps the rev from zero', () {
    final outcome = mergeCloudOps(
      state: CloudSyncState.empty(),
      ops: [_upsert(fields: const {'summary': 'buy milk'})],
      now: now,
    );
    final record = outcome.state.records['todo-1']!.record;
    expect(record.rev, 1);
    expect(record.deleted, isFalse);
    expect(record.payload, {'summary': 'buy milk'});
    expect(record.serverTs, DateTime.utc(2026, 11, 14, 10));
    expect(outcome.state.records['todo-1']!.lastOpId, 'op-a');
    expect(outcome.appliedOpIds, ['op-a']);
  });

  test('an upsert merges into the existing payload instead of replacing it', () {
    final state = _stateWith(
      CloudRecordEntry(
        record: SyncRecord(
          id: 'todo-1',
          type: RecordType.todo,
          payload: const {'summary': 'old', 'dueDate': '2026-11-15T00:00:00Z'},
          rev: 4,
          deleted: false,
          serverTs: DateTime.utc(2026, 11, 14, 9),
        ),
        lastOpId: 'op-peer',
      ),
    );
    final outcome = mergeCloudOps(
      state: state,
      ops: [_upsert(fields: const {'summary': 'new'})],
      now: now,
    );
    final record = outcome.state.records['todo-1']!.record;
    expect(record.rev, 5);
    expect(record.payload['summary'], 'new');
    // A field the op did not set keeps the value the document already had —
    // the whole point of dirty-field pushes.
    expect(record.payload['dueDate'], '2026-11-15T00:00:00Z');
  });

  test('a delete leaves a tombstone that keeps the last payload', () {
    final state = _stateWith(
      CloudRecordEntry(
        record: SyncRecord(
          id: 'todo-1',
          type: RecordType.todo,
          payload: const {'summary': 'old'},
          rev: 2,
          deleted: false,
          serverTs: DateTime.utc(2026, 11, 14, 9),
        ),
        lastOpId: 'op-peer',
      ),
    );
    final outcome = mergeCloudOps(state: state, ops: [_delete()], now: now);
    final record = outcome.state.records['todo-1']!.record;
    expect(record.deleted, isTrue);
    expect(record.rev, 3);
    expect(record.payload['summary'], 'old');
  });

  test('an upsert against a newer tombstone is a conflict, not a resurrect', () {
    final state = _stateWith(
      CloudRecordEntry(
        record: SyncRecord(
          id: 'todo-1',
          type: RecordType.todo,
          payload: const {'summary': 'gone'},
          rev: 3,
          deleted: true,
          serverTs: DateTime.utc(2026, 11, 14, 11),
        ),
        lastOpId: 'op-peer',
      ),
    );
    final outcome = mergeCloudOps(
      state: state,
      ops: [_upsert(opId: 'op-late')],
      now: now,
    );
    expect(outcome.conflictedOpIds, ['op-late']);
    expect(outcome.state.records['todo-1']!.record.deleted, isTrue);
    expect(outcome.state.records['todo-1']!.record.rev, 3);
  });

  test('the next round resurrects a record it just saw tombstoned', () {
    final deleted = mergeCloudOps(
      state: CloudSyncState.empty(),
      ops: [_delete(opId: 'op-del')],
      now: now,
    );
    final resurrect = mergeCloudOps(
      state: deleted.state,
      ops: [_upsert(opId: 'op-next', fields: const {'summary': 'back'})],
      // Same wall clock: the write time still has to move past the document
      // it observed, which is what makes a 412 retry safe.
      now: now,
    );
    expect(resurrect.appliedOpIds, ['op-next']);
    final record = resurrect.state.records['todo-1']!.record;
    expect(record.deleted, isFalse);
    expect(record.payload['summary'], 'back');
  });

  test('a same-second tie is decided by opId, as the server would', () {
    final at = DateTime.utc(2026, 11, 14, 10);
    CloudSyncState tombstoned(String lastOpId) => CloudSyncState(
      seq: 2,
      mergedAt: at.subtract(const Duration(seconds: 1)),
      records: {
        'todo-1': CloudRecordEntry(
          record: SyncRecord(
            id: 'todo-1',
            type: RecordType.todo,
            payload: const {},
            rev: 3,
            deleted: true,
            serverTs: at,
          ),
          lastOpId: lastOpId,
        ),
      },
    );

    expect(
      mergeCloudOps(
        state: tombstoned('op-m'),
        ops: [_upsert(opId: 'op-n')],
        now: at,
      ).appliedOpIds,
      ['op-n'],
    );
    expect(
      mergeCloudOps(
        state: tombstoned('op-z'),
        ops: [_upsert(opId: 'op-a')],
        now: at,
      ).conflictedOpIds,
      ['op-a'],
    );
  });

  test('a type mismatch is rejected instead of retagging the record', () {
    final state = _stateWith(
      CloudRecordEntry(
        record: SyncRecord(
          id: 'todo-1',
          type: RecordType.event,
          payload: const {'summary': 'an event'},
          rev: 1,
          deleted: false,
          serverTs: DateTime.utc(2026, 11, 14, 9),
        ),
        lastOpId: 'op-peer',
      ),
    );
    final outcome = mergeCloudOps(state: state, ops: [_upsert()], now: now);
    expect(outcome.conflictedOpIds, ['op-a']);
    expect(outcome.state.records['todo-1']!.record.type, RecordType.event);
  });

  test('the write time never goes backwards relative to the document', () {
    final state = CloudSyncState.empty().copyWith(
      mergedAt: DateTime.utc(2026, 11, 14, 12),
    );
    expect(
      nextCloudWriteTime(state: state, now: DateTime.utc(2026, 11, 14, 10)),
      DateTime.utc(2026, 11, 14, 12, 0, 1),
    );
    expect(
      nextCloudWriteTime(state: state, now: DateTime.utc(2026, 11, 14, 13)),
      DateTime.utc(2026, 11, 14, 13),
    );
  });

  test('the document survives a JSON round trip', () {
    final outcome = mergeCloudOps(
      state: CloudSyncState.empty(),
      ops: [_upsert(fields: const {'summary': 'buy milk', 'status': 'NEEDS-ACTION'})],
      now: now,
    );
    final restored = CloudSyncState.fromJson(outcome.state.toJson());
    expect(restored.seq, outcome.state.seq);
    expect(restored.mergedAt, outcome.state.mergedAt);
    final entry = restored.records['todo-1']!;
    expect(entry.lastOpId, 'op-a');
    expect(entry.record.rev, 1);
    expect(entry.record.payload['summary'], 'buy milk');
  });

  test('a document from another format is refused', () {
    expect(
      () => CloudSyncState.fromJson(const {'format': 'something-else'}),
      throwsFormatException,
    );
  });
}
