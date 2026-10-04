enum RecordType { event, todo, taskAllocation }

extension RecordTypeWireName on RecordType {
  String get wireName => switch (this) {
    RecordType.event => 'event',
    RecordType.todo => 'todo',
    RecordType.taskAllocation => 'task_allocation',
  };
}

RecordType recordTypeFromJson(Object value, String field) => switch (value) {
  'event' => RecordType.event,
  'todo' => RecordType.todo,
  'task_allocation' => RecordType.taskAllocation,
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
      serverTs: _parseUtcDateTime(
        _requireField<Object>(json, 'serverTs'),
        'serverTs',
      ),
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
    'type': type.wireName,
    'payload': payload,
    'rev': rev,
    'deleted': deleted,
    'serverTs': serverTs.toUtc().toIso8601String(),
  };
}

enum TaskAllocationState { active, cancelledByUser, invalidatedByCompletion }

extension TaskAllocationStateWireName on TaskAllocationState {
  String get wireName => switch (this) {
    TaskAllocationState.active => 'active',
    TaskAllocationState.cancelledByUser => 'cancelledByUser',
    TaskAllocationState.invalidatedByCompletion => 'invalidatedByCompletion',
  };
}

class TaskAllocationPayload {
  const TaskAllocationPayload({
    required this.todoSyncId,
    this.occurrenceId,
    required this.startAt,
    required this.endAt,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskAllocationPayload.fromJson(Map<String, dynamic> json) {
    const allowedFields = <String>{
      'todoSyncId',
      'occurrenceId',
      'startAt',
      'endAt',
      'state',
      'createdAt',
      'updatedAt',
    };
    if (json.keys.any((key) => !allowedFields.contains(key))) {
      throw const FormatException('unknown TaskAllocation payload field');
    }

    String requiredString(String field) {
      final value = _requireField<Object>(json, field);
      if (value is! String || value.isEmpty) {
        throw FormatException('invalid field: $field');
      }
      return value;
    }

    DateTime requiredDateTime(String field) =>
        _parseUtcDateTime(_requireField<Object>(json, field), field);

    final rawOccurrenceId = json['occurrenceId'];
    if (rawOccurrenceId != null && rawOccurrenceId is! String) {
      throw const FormatException('invalid field: occurrenceId');
    }
    final rawState = requiredString('state');
    final state = switch (rawState) {
      'active' => TaskAllocationState.active,
      'cancelledByUser' => TaskAllocationState.cancelledByUser,
      'invalidatedByCompletion' => TaskAllocationState.invalidatedByCompletion,
      _ => throw const FormatException('invalid field: state'),
    };
    final startAt = requiredDateTime('startAt');
    final endAt = requiredDateTime('endAt');
    if (!endAt.isAfter(startAt)) {
      throw const FormatException(
        'invalid interval: endAt must follow startAt',
      );
    }
    return TaskAllocationPayload(
      todoSyncId: requiredString('todoSyncId'),
      occurrenceId: rawOccurrenceId as String?,
      startAt: startAt,
      endAt: endAt,
      state: state,
      createdAt: requiredDateTime('createdAt'),
      updatedAt: requiredDateTime('updatedAt'),
    );
  }

  final String todoSyncId;
  final String? occurrenceId;
  final DateTime startAt;
  final DateTime endAt;
  final TaskAllocationState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'todoSyncId': todoSyncId,
    'occurrenceId': occurrenceId,
    'startAt': _millisecondUtc(startAt),
    'endAt': _millisecondUtc(endAt),
    'state': state.wireName,
    'createdAt': _millisecondUtc(createdAt),
    'updatedAt': _millisecondUtc(updatedAt),
  };
}

String _millisecondUtc(DateTime value) {
  final utc = value.toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}
