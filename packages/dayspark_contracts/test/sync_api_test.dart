import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:test/test.dart';

PushOp _sampleOp() => const PushOp(
      opId: 'op-1',
      op: OpType.upsert,
      recordId: 'rec-1',
      type: RecordType.event,
      fields: {'title': 'Meeting', 'rev': 3},
      baseRev: 2,
    );

PushRequest _sampleRequest() => PushRequest(
      deviceId: 'device-a',
      ops: [_sampleOp()],
      cursor: 42,
    );

OpResult _sampleResult() => OpResult(
      opId: 'op-1',
      status: OpStatus.conflict,
      serverRecord: SyncRecord(
        id: 'rec-1',
        type: RecordType.event,
        payload: {'title': 'Server wins'},
        rev: 5,
        deleted: false,
        serverTs: DateTime.utc(2026, 9, 23, 12),
      ),
      code: errConflict,
    );

void main() {
  group('PushOp', () {
    test('toJson/fromJson roundtrip with optionals set', () {
      final original = _sampleOp();
      final restored = PushOp.fromJson(original.toJson());

      expect(restored.opId, original.opId);
      expect(restored.op, original.op);
      expect(restored.recordId, original.recordId);
      expect(restored.type, original.type);
      expect(restored.fields, original.fields);
      expect(restored.baseRev, original.baseRev);
    });

    test('roundtrip with optionals null', () {
      const original = PushOp(
        opId: 'op-2',
        op: OpType.delete,
        recordId: 'rec-2',
        type: RecordType.todo,
      );

      final restored = PushOp.fromJson(original.toJson());

      expect(restored.op, OpType.delete);
      expect(restored.type, RecordType.todo);
      expect(restored.fields, isNull);
      expect(restored.baseRev, isNull);
    });

    test('parses when optional keys are absent entirely', () {
      final json = _sampleOp().toJson()
        ..remove('fields')
        ..remove('baseRev');

      final restored = PushOp.fromJson(json);

      expect(restored.fields, isNull);
      expect(restored.baseRev, isNull);
    });

    test('ignores unknown JSON keys', () {
      final json = _sampleOp().toJson();
      json['futureFlag'] = true;

      final restored = PushOp.fromJson(json);

      expect(restored.opId, 'op-1');
    });

    test('missing opId throws FormatException naming the field', () {
      final json = _sampleOp().toJson()..remove('opId');

      expect(
        () => PushOp.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('opId')),
        ),
      );
    });

    test('invalid op enum throws FormatException', () {
      final json = _sampleOp().toJson();
      json['op'] = 'remove';

      expect(
        () => PushOp.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('op')),
        ),
      );
    });

    test('invalid type enum throws FormatException', () {
      final json = _sampleOp().toJson();
      json['type'] = 'reminder';

      expect(
        () => PushOp.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('type')),
        ),
      );
    });

    test('enum values serialize as lowercase wire strings', () {
      final json = _sampleOp().toJson();

      expect(json['op'], 'upsert');
      expect(json['type'], 'event');
    });
  });

  group('PushRequest', () {
    test('toJson/fromJson roundtrip', () {
      final original = _sampleRequest();
      final restored = PushRequest.fromJson(original.toJson());

      expect(restored.deviceId, original.deviceId);
      expect(restored.ops, hasLength(1));
      expect(restored.ops.first.opId, 'op-1');
      expect(restored.cursor, 42);
    });

    test('roundtrip with null cursor', () {
      final original = PushRequest(deviceId: 'device-a', ops: const []);
      final restored = PushRequest.fromJson(original.toJson());

      expect(restored.ops, isEmpty);
      expect(restored.cursor, isNull);
    });

    test('ignores unknown JSON keys', () {
      final json = _sampleRequest().toJson();
      json['traceId'] = 'abc';

      final restored = PushRequest.fromJson(json);

      expect(restored.deviceId, 'device-a');
    });

    test('missing deviceId throws FormatException naming the field', () {
      final json = _sampleRequest().toJson()..remove('deviceId');

      expect(
        () => PushRequest.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('deviceId')),
        ),
      );
    });

    test('missing ops throws FormatException naming the field', () {
      final json = _sampleRequest().toJson()..remove('ops');

      expect(
        () => PushRequest.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('ops')),
        ),
      );
    });

    test('invalid nested op enum throws FormatException', () {
      final json = _sampleRequest().toJson();
      (json['ops'] as List).first['op'] = 'destroy';

      expect(
        () => PushRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OpResult', () {
    test('toJson/fromJson roundtrip with serverRecord and code', () {
      final original = _sampleResult();
      final restored = OpResult.fromJson(original.toJson());

      expect(restored.opId, original.opId);
      expect(restored.status, original.status);
      expect(restored.serverRecord, isNotNull);
      expect(restored.serverRecord!.id, 'rec-1');
      expect(restored.serverRecord!.serverTs, original.serverRecord!.serverTs);
      expect(restored.code, errConflict);
    });

    test('roundtrip with null optionals', () {
      const original = OpResult(
        opId: 'op-3',
        status: OpStatus.applied,
      );

      final restored = OpResult.fromJson(original.toJson());

      expect(restored.status, OpStatus.applied);
      expect(restored.serverRecord, isNull);
      expect(restored.code, isNull);
    });

    test('missing status throws FormatException naming the field', () {
      final json = _sampleResult().toJson()..remove('status');

      expect(
        () => OpResult.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('status')),
        ),
      );
    });

    test('invalid status enum throws FormatException', () {
      final json = _sampleResult().toJson();
      json['status'] = 'ok';

      expect(
        () => OpResult.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('status')),
        ),
      );
    });

    test('all four statuses roundtrip', () {
      for (final status in [
        OpStatus.applied,
        OpStatus.conflict,
        OpStatus.rejected,
        OpStatus.duplicate,
      ]) {
        final restored = OpResult.fromJson(
          OpResult(opId: 'op-x', status: status).toJson(),
        );
        expect(restored.status, status);
      }
    });

    test('statuses serialize as lowercase wire strings', () {
      expect(
        const OpResult(opId: 'a', status: OpStatus.applied).toJson()['status'],
        'applied',
      );
      expect(
        const OpResult(opId: 'b', status: OpStatus.conflict).toJson()['status'],
        'conflict',
      );
      expect(
        const OpResult(opId: 'c', status: OpStatus.rejected).toJson()['status'],
        'rejected',
      );
      expect(
        const OpResult(opId: 'd', status: OpStatus.duplicate).toJson()['status'],
        'duplicate',
      );
    });
  });

  group('PushResponse', () {
    test('toJson/fromJson roundtrip', () {
      final original = PushResponse(
        results: [_sampleResult()],
        piggyback: [
          SyncRecord(
            id: 'rec-9',
            type: RecordType.todo,
            payload: {'title': 'Piggybacked'},
            rev: 1,
            deleted: false,
            serverTs: DateTime.utc(2026, 9, 23, 9),
          ),
        ],
        cursor: 99,
      );

      final restored = PushResponse.fromJson(original.toJson());

      expect(restored.results, hasLength(1));
      expect(restored.results.first.status, OpStatus.conflict);
      expect(restored.piggyback, hasLength(1));
      expect(restored.piggyback.first.id, 'rec-9');
      expect(restored.cursor, 99);
    });

    test('missing cursor throws FormatException naming the field', () {
      final json = PushResponse(results: const [], piggyback: const [], cursor: 1)
          .toJson()
        ..remove('cursor');

      expect(
        () => PushResponse.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('cursor')),
        ),
      );
    });

    test('ignores unknown JSON keys', () {
      final json = PushResponse(results: const [], piggyback: const [], cursor: 5)
          .toJson();
      json['extra'] = 1;

      final restored = PushResponse.fromJson(json);

      expect(restored.cursor, 5);
    });
  });

  group('PullResponse', () {
    test('toJson/fromJson roundtrip', () {
      final original = PullResponse(
        changes: [
          SyncRecord(
            id: 'rec-5',
            type: RecordType.todo,
            payload: {'title': 'Changed'},
            rev: 7,
            deleted: true,
            serverTs: DateTime.utc(2026, 9, 23, 10),
          ),
        ],
        nextCursor: 120,
        hasMore: true,
      );

      final restored = PullResponse.fromJson(original.toJson());

      expect(restored.changes, hasLength(1));
      expect(restored.changes.first.id, 'rec-5');
      expect(restored.changes.first.deleted, isTrue);
      expect(restored.nextCursor, 120);
      expect(restored.hasMore, isTrue);
    });

    test('missing nextCursor throws FormatException naming the field', () {
      final json = PullResponse(changes: const [], nextCursor: 1, hasMore: false)
          .toJson()
        ..remove('nextCursor');

      expect(
        () => PullResponse.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('nextCursor')),
        ),
      );
    });

    test('missing hasMore throws FormatException naming the field', () {
      final json = PullResponse(changes: const [], nextCursor: 1, hasMore: false)
          .toJson()
        ..remove('hasMore');

      expect(
        () => PullResponse.fromJson(json),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', contains('hasMore')),
        ),
      );
    });

    test('ignores unknown JSON keys', () {
      final json = PullResponse(changes: const [], nextCursor: 2, hasMore: false)
          .toJson();
      json['serverVersion'] = '1.0.0';

      final restored = PullResponse.fromJson(json);

      expect(restored.nextCursor, 2);
      expect(restored.hasMore, isFalse);
    });
  });
}
