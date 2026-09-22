enum RecordType { event, todo }

RecordType recordTypeFromJson(Object value, String field) => switch (value) {
      'event' => RecordType.event,
      'todo' => RecordType.todo,
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

DateTime _parseUtcDateTime(Object value, String field) {
  if (value is! String) {
    throw FormatException('invalid field: $field');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('invalid field: $field');
  }
}

class SyncRecord {
  const SyncRecord({
    required this.id,
    required this.type,
    required this.payload,
    required this.rev,
    required this.deleted,
    required this.serverTs,
  });

  factory SyncRecord.fromJson(Map<String, dynamic> json) {
    return SyncRecord(
      id: _requireField<String>(json, 'id'),
      type: recordTypeFromJson(_requireField<Object>(json, 'type'), 'type'),
      payload: Map<String, dynamic>.from(_requireField<Map>(json, 'payload')),
      rev: _requireField<int>(json, 'rev'),
      deleted: _requireField<bool>(json, 'deleted'),
      serverTs: _parseUtcDateTime(_requireField<Object>(json, 'serverTs'), 'serverTs'),
    );
  }

  final String id;
  final RecordType type;
  final Map<String, dynamic> payload;
  final int rev;
  final bool deleted;
  final DateTime serverTs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'payload': payload,
        'rev': rev,
        'deleted': deleted,
        'serverTs': serverTs.toUtc().toIso8601String(),
      };
}
