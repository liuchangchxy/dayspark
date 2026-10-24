import 'package:dayspark/data/local/database/app_database.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:dayspark/domain/records/todo_recurrence.dart';
import 'package:uuid/uuid.dart';

const Uuid _calendarUuid = Uuid();

// Payload ↔ row mapping for P2 sync scope (event + todo + TaskAllocation;
// tag, reminder and attachment payloads are P2.5). DateTimes travel as UTC
// ISO-8601 strings; drift stores the same instant as unix seconds.

String? isoOf(DateTime? dt) => dt?.toUtc().toIso8601String();

/// Keys of [current] whose values differ from the last-known server
/// payload — the dirty-field set a push op may carry. The server's
/// per-field LWW (server lww.dart) only honors keys the op SETS, so
/// sending the whole record would clobber fields this device never
/// edited (lost update on concurrent disjoint edits).
Map<String, dynamic> dirtyFields(
  Map<String, dynamic> current,
  Map<String, Object?> lastKnownServer,
) {
  final dirty = <String, dynamic>{};
  for (final field in current.entries) {
    if (!lastKnownServer.containsKey(field.key) ||
        lastKnownServer[field.key] != field.value) {
      dirty[field.key] = field.value;
    }
  }
  if (dirty.keys.any(_isRecurrenceWireKey)) {
    for (final key in const [
      'recurrenceSpec',
      'recurrenceRevision',
      'recurrenceLegacyState',
    ]) {
      dirty[key] = current[key];
    }
  }
  return dirty;
}

bool _isRecurrenceWireKey(String key) =>
    key == 'recurrenceSpec' ||
    key == 'recurrenceRevision' ||
    key == 'recurrenceLegacyState';

DateTime? parseIso(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

Future<String> ensureCalendarSyncId(AppDatabase db, int calendarId) async {
  final cal = await (db.select(
    db.calendars,
  )..where((c) => c.id.equals(calendarId))).getSingleOrNull();
  if (cal != null && cal.syncId != null && cal.syncId!.isNotEmpty) {
    return cal.syncId!;
  }
  final newSyncId = _calendarUuid.v7();
  if (cal != null) {
    await (db.update(db.calendars)..where((c) => c.id.equals(calendarId)))
        .write(CalendarsCompanion(syncId: Value(newSyncId)));
  }
  return newSyncId;
}

Future<Map<String, Object?>> eventToPayload(AppDatabase db, Event e) async {
  final calSyncId = await ensureCalendarSyncId(db, e.calendarId);
  return <String, Object?>{
    'calendarId': e.calendarId,
    'calendarSyncId': calSyncId,
    'summary': e.summary,
    'startDt': isoOf(e.startDt),
    'endDt': isoOf(e.endDt),
    'isAllDay': e.isAllDay,
    'description': e.description,
    'location': e.location,
    'rrule': e.rrule,
    'exdates': e.exdates,
    'deletedAt': isoOf(e.deletedAt),
    'createdAt': isoOf(e.createdAt),
    'updatedAt': isoOf(e.updatedAt),
  };
}

Future<Map<String, Object?>> todoToPayload(AppDatabase db, Todo t) async {
  String? parentSyncId;
  final parentId = t.parentId;
  if (parentId != null) {
    final parent = await (db.select(
      db.todos,
    )..where((r) => r.id.equals(parentId))).getSingleOrNull();
    parentSyncId = parent?.syncId;
  }
  final calSyncId = await ensureCalendarSyncId(db, t.calendarId);
  return <String, Object?>{
    'calendarId': t.calendarId,
    'calendarSyncId': calSyncId,
    'summary': t.summary,
    'dueDate': isoOf(t.dueDate),
    'startDate': isoOf(t.startDate),
    'priority': t.priority,
    'status': t.status,
    'description': t.description,
    'rrule': t.rrule,
    'completedAt': isoOf(t.completedAt),
    'percentComplete': t.percentComplete,
    'deletedAt': isoOf(t.deletedAt),
    'createdAt': isoOf(t.createdAt),
    'updatedAt': isoOf(t.updatedAt),
    'sortOrder': t.sortOrder,
    // Local integer ids are device-scoped and cannot cross devices; the
    // parent travels as its sync UUID and is resolved back on apply.
    'parentSyncId': parentSyncId,
    ...TodoRecurrence.fromTodo(t).toJson(),
  };
}

Map<String, Object?> taskAllocationToPayload(TaskAllocation allocation) =>
    <String, Object?>{
      'todoSyncId': allocation.todoSyncId,
      'occurrenceId': allocation.occurrenceId,
      'startAt': isoOf(allocation.startAt),
      'endAt': isoOf(allocation.endAt),
      'state': allocation.state,
      'createdAt': isoOf(allocation.createdAt),
      'updatedAt': isoOf(allocation.updatedAt),
    };

Map<String, Object?> taskInstanceStateToPayload(TaskInstanceState state) =>
    <String, Object?>{
      'todoSyncId': state.todoSyncId,
      'occurrenceId': state.occurrenceId,
      'status': state.status,
      'completedAt': isoOf(state.completedAt),
      'updatedAt': isoOf(state.updatedAt),
    };

Map<String, Object?> reminderToPayload(Reminder reminder) => <String, Object?>{
  'parentType': reminder.parentType,
  'parentSyncId': reminder.parentSyncId,
  'triggerTime': isoOf(reminder.triggerTime),
  'isTriggered': reminder.isTriggered,
};

Map<String, Object?> tagToPayload(Tag tag) => <String, Object?>{
  'name': tag.name,
  'color': tag.color,
};

Map<String, Object?> tagAssociationToPayload({
  required String parentType,
  required String parentSyncId,
  required String tagSyncId,
}) => <String, Object?>{
  'parentType': parentType,
  'parentSyncId': parentSyncId,
  'tagSyncId': tagSyncId,
};

Map<String, Object?> attachmentToPayload(Attachment attachment) =>
    <String, Object?>{
      'parentType': attachment.parentType,
      'parentSyncId': attachment.parentSyncId,
      'fileName': attachment.fileName,
      'fileSize': attachment.fileSize,
      'mimeType': attachment.mimeType,
      'serverFileRef': attachment.serverFileRef,
    };

String requireString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String) {
    throw FormatException('payload missing field: $key');
  }
  return value;
}

DateTime requireDateTime(Map<String, Object?> payload, String key) {
  final value = parseIso(payload[key]);
  if (value == null) {
    throw FormatException('payload missing datetime: $key');
  }
  return value;
}

int? optionalInt(Object? raw) => raw is int ? raw : null;
bool? optionalBool(Object? raw) => raw is bool ? raw : null;
String? optionalString(Object? raw) => raw is String ? raw : null;

/// Resolves the calendar ID from a sync payload.
///
/// Priority:
/// 1. If payload provides `calendarSyncId`, find a calendar whose `syncId` matches.
/// 2. If no `syncId` match and `raw` (local integer id) is provided, check if a calendar
///    with that integer ID exists. If that calendar does NOT have a conflicting syncId, match it.
/// 3. Otherwise, look for default/personal calendar, or create one if none exists.
Future<int> resolveCalendarId(
  AppDatabase db,
  Object? raw, {
  String? calendarSyncId,
}) async {
  if (calendarSyncId != null && calendarSyncId.isNotEmpty) {
    final bySyncId = await (db.select(
      db.calendars,
    )..where((t) => t.syncId.equals(calendarSyncId))).getSingleOrNull();
    if (bySyncId != null) return bySyncId.id;
  }

  // Fallback to integer id only if calendar has no conflicting syncId
  if (raw is int) {
    final byId = await (db.select(
      db.calendars,
    )..where((t) => t.id.equals(raw))).getSingleOrNull();
    if (byId != null) {
      if (calendarSyncId != null &&
          calendarSyncId.isNotEmpty &&
          byId.syncId == null) {
        // Link the incoming syncId to the local calendar
        await (db.update(db.calendars)..where((t) => t.id.equals(raw))).write(
          CalendarsCompanion(syncId: Value(calendarSyncId)),
        );
      }
      return raw;
    }
  }

  final first =
      await (db.select(db.calendars)
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(1))
          .getSingleOrNull();
  if (first != null) {
    if (calendarSyncId != null &&
        calendarSyncId.isNotEmpty &&
        first.syncId == null) {
      await (db.update(db.calendars)..where((t) => t.id.equals(first.id)))
          .write(CalendarsCompanion(syncId: Value(calendarSyncId)));
    }
    return first.id;
  }

  return db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          name: 'Personal',
          syncId: calendarSyncId != null
              ? Value(calendarSyncId)
              : const Value.absent(),
        ),
      );
}
