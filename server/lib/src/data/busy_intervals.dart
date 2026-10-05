import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';

import '../db.dart';
import 'record_query.dart';
import 'rrule_window.dart';

enum BusyIntervalSource { event, taskAllocation }

class BusyIntervalSourceRef {
  const BusyIntervalSourceRef({required this.type, required this.id});

  final BusyIntervalSource type;
  final String id;
}

class BusyInterval {
  const BusyInterval({
    required this.startAt,
    required this.endAt,
    required this.sources,
  });

  final DateTime startAt;
  final DateTime endAt;
  final List<BusyIntervalSourceRef> sources;
}

Future<List<BusyInterval>> getBusyIntervals(
  AppDatabase db, {
  required String userId,
  required DateTime from,
  required DateTime to,
}) async {
  final fromUtc = from.toUtc();
  final toUtc = to.toUtc();
  final eventPage = await queryRecords(
    db,
    userId: userId,
    type: RecordType.event,
    from: fromUtc,
    to: toUtc,
    timezone: 'UTC',
    limit: recordQueryMaxLimit,
  );
  final expansion = expandRecordsInWindow(
    eventPage.records,
    from: fromUtc,
    to: toUtc,
  );
  final intervals = <_SourceInterval>[
    for (final instance in expansion.instances)
      _SourceInterval(
        startAt: instance.start,
        endAt: instance.end,
        source: BusyIntervalSourceRef(
          type: BusyIntervalSource.event,
          id: instance.master.id,
        ),
      ),
  ];

  final allocationRows = await queryTaskAllocationRecordsInWindow(
    db,
    userId: userId,
    from: fromUtc,
    to: toUtc,
  );
  final candidates = <(RecordRow, Map<String, dynamic>, DateTime, DateTime)>[];
  final todoIds = <String>{};
  for (final row in allocationRows) {
    try {
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final startAt = DateTime.parse(payload['startAt'] as String).toUtc();
      final endAt = DateTime.parse(payload['endAt'] as String).toUtc();
      if (payload['state'] != TaskAllocationState.active.wireName ||
          !endAt.isAfter(startAt) ||
          !startAt.isBefore(toUtc) ||
          !endAt.isAfter(fromUtc)) {
        continue;
      }
      final todoSyncId = payload['todoSyncId'];
      if (todoSyncId is! String || todoSyncId.isEmpty) continue;
      candidates.add((row, payload, startAt, endAt));
      todoIds.add(todoSyncId);
    } on Object {
      continue;
    }
  }

  if (todoIds.isNotEmpty) {
    final todoRows =
        await (db.select(db.records)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.type.equals(RecordType.todo.wireName) &
                  row.id.isIn(todoIds),
            ))
            .get();
    final todosById = {for (final row in todoRows) row.id: row};
    for (final candidate in candidates) {
      final (allocationRow, payload, startAt, endAt) = candidate;
      final todoSyncId = payload['todoSyncId'] as String;
      final todoRow = todosById[todoSyncId];
      if (todoRow == null || todoRow.deleted) continue;
      try {
        final todo = jsonDecode(todoRow.payloadJson) as Map<String, dynamic>;
        if (todo['deletedAt'] != null ||
            todo['status'] == 'CANCELLED' ||
            (todo['rrule'] != null && payload['occurrenceId'] == null)) {
          continue;
        }
        if (todo['status'] == 'COMPLETED') {
          if (todo['rrule'] != null) continue;
          final rawCompletedAt = todo['completedAt'];
          if (rawCompletedAt is! String) continue;
          final completedAt = DateTime.parse(rawCompletedAt).toUtc();
          if (!startAt.isBefore(completedAt)) continue;
        }
        if (todo['rrule'] != null && payload['occurrenceId'] is String) {
          final instanceId = taskInstanceStateRecordId(
            todoSyncId,
            payload['occurrenceId'] as String,
          );
          final instanceRow =
              await (db.select(db.records)..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.id.equals(instanceId) &
                        row.type.equals(RecordType.taskInstanceState.wireName) &
                        row.deleted.equals(false),
                  ))
                  .getSingleOrNull();
          if (instanceRow != null) {
            final instance = TaskInstanceStatePayload.fromJson(
              jsonDecode(instanceRow.payloadJson) as Map<String, dynamic>,
            );
            if (instance.status == 'skipped') continue;
            final completedAt = instance.completedAt;
            if (instance.status == 'completed' &&
                (completedAt == null || !startAt.isBefore(completedAt))) {
              continue;
            }
          }
        }
      } on Object {
        continue;
      }
      intervals.add(
        _SourceInterval(
          startAt: startAt,
          endAt: endAt,
          source: BusyIntervalSourceRef(
            type: BusyIntervalSource.taskAllocation,
            id: allocationRow.id,
          ),
        ),
      );
    }
  }

  final clipped =
      <_SourceInterval>[
        for (final interval in intervals)
          if (interval.endAt.isAfter(fromUtc) &&
              interval.startAt.isBefore(toUtc))
            _SourceInterval(
              startAt: interval.startAt.isBefore(fromUtc)
                  ? fromUtc
                  : interval.startAt,
              endAt: interval.endAt.isAfter(toUtc) ? toUtc : interval.endAt,
              source: interval.source,
            ),
      ]..sort((a, b) {
        final byStart = a.startAt.compareTo(b.startAt);
        return byStart != 0 ? byStart : a.endAt.compareTo(b.endAt);
      });

  final merged = <BusyInterval>[];
  for (final interval in clipped) {
    if (merged.isEmpty || interval.startAt.isAfter(merged.last.endAt)) {
      merged.add(
        BusyInterval(
          startAt: interval.startAt,
          endAt: interval.endAt,
          sources: [interval.source],
        ),
      );
      continue;
    }
    final previous = merged.removeLast();
    merged.add(
      BusyInterval(
        startAt: previous.startAt,
        endAt: interval.endAt.isAfter(previous.endAt)
            ? interval.endAt
            : previous.endAt,
        sources: [...previous.sources, interval.source],
      ),
    );
  }
  return merged;
}

class _SourceInterval {
  const _SourceInterval({
    required this.startAt,
    required this.endAt,
    required this.source,
  });

  final DateTime startAt;
  final DateTime endAt;
  final BusyIntervalSourceRef source;
}
