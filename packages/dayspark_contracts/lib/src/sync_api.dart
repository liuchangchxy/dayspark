import 'record_dto.dart';

enum OpType { upsert, delete }

enum OpStatus { applied, conflict, rejected, duplicate }

OpType _opTypeFromJson(Object value, String field) => switch (value) {
      'upsert' => OpType.upsert,
      'delete' => OpType.delete,
      _ => throw FormatException('invalid $field value: $value'),
    };

OpStatus _opStatusFromJson(Object value, String field) => switch (value) {
      'applied' => OpStatus.applied,
      'conflict' => OpStatus.conflict,
      'rejected' => OpStatus.rejected,
      'duplicate' => OpStatus.duplicate,
      _ => throw FormatException('invalid $field value: $value'),
    };

T _requireField<T>(Map<String, dynamic> json, String field) {
  if (!json.containsKey(field)) {
    throw FormatException('missing required field: $field');
  }
  final value = json[field];
  if (value is! T) {
    throw FormatException('invalid field: $field');
  }
  return value;
}

T? _optionalField<T>(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! T) {
    throw FormatException('invalid field: $field');
  }
  return value;
}

Map<String, dynamic> _asJsonMap(Object value) => Map<String, dynamic>.from(value as Map);

class PushOp {
  const PushOp({
    required this.opId,
    required this.op,
    required this.recordId,
    required this.type,
    this.fields,
    this.baseRev,
  });

  factory PushOp.fromJson(Map<String, dynamic> json) {
    final fields = _optionalField<Map>(json, 'fields');
    return PushOp(
      opId: _requireField<String>(json, 'opId'),
      op: _opTypeFromJson(_requireField<Object>(json, 'op'), 'op'),
      recordId: _requireField<String>(json, 'recordId'),
      type: recordTypeFromJson(_requireField<Object>(json, 'type'), 'type'),
      fields: fields == null ? null : _asJsonMap(fields),
      baseRev: _optionalField<int>(json, 'baseRev'),
    );
  }

  final String opId;
  final OpType op;
  final String recordId;
  final RecordType type;
  final Map<String, dynamic>? fields;
  final int? baseRev;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'opId': opId,
        'op': op.name,
        'recordId': recordId,
        'type': type.name,
        'fields': fields,
        'baseRev': baseRev,
      };
}

class PushRequest {
  const PushRequest({
    required this.deviceId,
    required this.ops,
    this.cursor,
  });

  factory PushRequest.fromJson(Map<String, dynamic> json) {
    return PushRequest(
      deviceId: _requireField<String>(json, 'deviceId'),
      ops: _requireField<List>(json, 'ops')
          .map((Object? op) => PushOp.fromJson(_asJsonMap(op!)))
          .toList(),
      cursor: _optionalField<int>(json, 'cursor'),
    );
  }

  final String deviceId;
  final List<PushOp> ops;
  final int? cursor;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'ops': ops.map((PushOp op) => op.toJson()).toList(),
        'cursor': cursor,
      };
}

class OpResult {
  const OpResult({
    required this.opId,
    required this.status,
    this.serverRecord,
    this.code,
  });

  factory OpResult.fromJson(Map<String, dynamic> json) {
    return OpResult(
      opId: _requireField<String>(json, 'opId'),
      status: _opStatusFromJson(_requireField<Object>(json, 'status'), 'status'),
      serverRecord: json['serverRecord'] == null
          ? null
          : SyncRecord.fromJson(_asJsonMap(json['serverRecord']!)),
      code: _optionalField<String>(json, 'code'),
    );
  }

  final String opId;
  final OpStatus status;
  final SyncRecord? serverRecord;
  final String? code;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'opId': opId,
        'status': status.name,
        'serverRecord': serverRecord?.toJson(),
        'code': code,
      };
}

class PushResponse {
  const PushResponse({
    required this.results,
    required this.piggyback,
    required this.cursor,
  });

  factory PushResponse.fromJson(Map<String, dynamic> json) {
    return PushResponse(
      results: _requireField<List>(json, 'results')
          .map((Object? result) => OpResult.fromJson(_asJsonMap(result!)))
          .toList(),
      piggyback: _requireField<List>(json, 'piggyback')
          .map((Object? record) => SyncRecord.fromJson(_asJsonMap(record!)))
          .toList(),
      cursor: _requireField<int>(json, 'cursor'),
    );
  }

  final List<OpResult> results;
  final List<SyncRecord> piggyback;
  final int cursor;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'results': results.map((OpResult result) => result.toJson()).toList(),
        'piggyback': piggyback.map((SyncRecord record) => record.toJson()).toList(),
        'cursor': cursor,
      };
}

class PullResponse {
  const PullResponse({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  factory PullResponse.fromJson(Map<String, dynamic> json) {
    return PullResponse(
      changes: _requireField<List>(json, 'changes')
          .map((Object? record) => SyncRecord.fromJson(_asJsonMap(record!)))
          .toList(),
      nextCursor: _requireField<int>(json, 'nextCursor'),
      hasMore: _requireField<bool>(json, 'hasMore'),
    );
  }

  final List<SyncRecord> changes;
  final int nextCursor;
  final bool hasMore;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'changes': changes.map((SyncRecord record) => record.toJson()).toList(),
        'nextCursor': nextCursor,
        'hasMore': hasMore,
      };
}
