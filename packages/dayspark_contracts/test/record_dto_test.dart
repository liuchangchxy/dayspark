import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:test/test.dart';

SyncRecord _sample() => SyncRecord(
  id: 'rec-1',
  type: RecordType.event,
  payload: {'title': 'Meeting', 'start': '2026-09-23T10:00:00.000Z'},
  rev: 3,
  deleted: false,
  serverTs: DateTime.utc(2026, 9, 23, 12, 30, 45, 123),
);

void main() {
  group('SyncRecord', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      final original = _sample();
      final restored = SyncRecord.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.payload, original.payload);
      expect(restored.rev, original.rev);
      expect(restored.deleted, original.deleted);
      expect(restored.serverTs, original.serverTs);
      expect(restored.serverTs.isUtc, isTrue);
    });

    test('toJson serializes serverTs as UTC ISO-8601 string', () {
      final json = _sample().toJson();

      expect(json['serverTs'], '2026-09-23T12:30:45.123Z');
    });

    test('fromJson parses offset timestamps as UTC', () {
      final json = _sample().toJson();
      json['serverTs'] = '2026-09-23T12:30:45.123+08:00';

      final restored = SyncRecord.fromJson(json);

      expect(restored.serverTs.isUtc, isTrue);
      expect(
        restored.serverTs.toUtc().toIso8601String(),
        '2026-09-23T04:30:45.123Z',
      );
    });

    test('normalizes local DateTime to UTC on serialize', () {
      final record = SyncRecord(
        id: 'rec-2',
        type: RecordType.todo,
        payload: const {},
        rev: 1,
        deleted: true,
        serverTs: DateTime.utc(2026, 9, 23, 8).toLocal(),
      );

      final json = record.toJson();
      final restored = SyncRecord.fromJson(json);

      expect(json['serverTs'], endsWith('Z'));
      expect(restored.serverTs.isUtc, isTrue);
      expect(
        restored.serverTs.microsecondsSinceEpoch,
        record.serverTs.toUtc().microsecondsSinceEpoch,
      );
    });

    test('ignores unknown JSON keys for forward compatibility', () {
      final json = _sample().toJson();
      json['futureField'] = {'nested': true};

      final restored = SyncRecord.fromJson(json);

      expect(restored.id, 'rec-1');
      expect(restored.type, RecordType.event);
    });

    test('missing required key throws FormatException naming the field', () {
      for (final field in [
        'id',
        'type',
        'payload',
        'rev',
        'deleted',
        'serverTs',
      ]) {
        final json = _sample().toJson();
        json.remove(field);

        expect(
          () => SyncRecord.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(field),
            ),
          ),
          reason: 'expected FormatException for missing field $field',
        );
      }
    });

    test('invalid type enum throws FormatException', () {
      final json = _sample().toJson();
      json['type'] = 'task';

      expect(
        () => SyncRecord.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('type'),
          ),
        ),
      );
    });

    test('enum values serialize as lowercase wire strings', () {
      final event = _sample().toJson();
      final todo = SyncRecord(
        id: 'rec-3',
        type: RecordType.todo,
        payload: const {},
        rev: 1,
        deleted: false,
        serverTs: DateTime.utc(2026, 9, 23),
      ).toJson();

      expect(event['type'], 'event');
      expect(todo['type'], 'todo');
    });

    test('TaskAllocation uses the stable task_allocation wire type', () {
      final record = SyncRecord(
        id: 'allocation-1',
        type: RecordType.taskAllocation,
        payload: const {},
        rev: 1,
        deleted: false,
        serverTs: DateTime.utc(2026, 10, 4),
      );

      expect(record.toJson()['type'], 'task_allocation');
      expect(
        SyncRecord.fromJson(record.toJson()).type,
        RecordType.taskAllocation,
      );
    });
  });

  group('TaskAllocationPayload', () {
    test('roundtrips only the first-version domain fields', () {
      final original = TaskAllocationPayload(
        todoSyncId: 'todo-uuid',
        occurrenceId: null,
        startAt: DateTime.utc(2026, 10, 7, 9, 0, 0, 123),
        endAt: DateTime.utc(2026, 10, 7, 10),
        state: TaskAllocationState.active,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 2),
      );

      final json = original.toJson();
      final restored = TaskAllocationPayload.fromJson(json);

      expect(restored.toJson(), json);
      expect(json.keys, {
        'todoSyncId',
        'occurrenceId',
        'startAt',
        'endAt',
        'state',
        'createdAt',
        'updatedAt',
      });
    });

    test('rejects invalid intervals and unknown states', () {
      final json = TaskAllocationPayload(
        todoSyncId: 'todo-uuid',
        startAt: DateTime.utc(2026, 10, 7, 10),
        endAt: DateTime.utc(2026, 10, 7, 11),
        state: TaskAllocationState.active,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 2),
      ).toJson();

      expect(
        () =>
            TaskAllocationPayload.fromJson({...json, 'endAt': json['startAt']}),
        throwsFormatException,
      );
      expect(
        () => TaskAllocationPayload.fromJson({...json, 'state': 'scheduled'}),
        throwsFormatException,
      );
    });

    test('accepts payloads written before optional occurrenceId existed', () {
      final payload = TaskAllocationPayload(
        todoSyncId: 'todo-uuid',
        startAt: DateTime.utc(2026, 10, 7, 10),
        endAt: DateTime.utc(2026, 10, 7, 11),
        state: TaskAllocationState.active,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 2),
      ).toJson()..remove('occurrenceId');

      expect(TaskAllocationPayload.fromJson(payload).occurrenceId, isNull);
    });
  });
}
