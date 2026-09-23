import 'package:dayspark/data/local/database/app_database.dart';
import 'package:drift/drift.dart' show OrderingTerm;

// Payload ↔ row mapping for P2 sync scope (event + todo only; tag,
// reminder and attachment payloads are P2.5). DateTimes travel as UTC
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
  return dirty;
}

DateTime? parseIso(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

Map<String, Object?> eventToPayload(Event e) => <String, Object?>{
  'calendarId': e.calendarId,
  'summary': e.summary,
  'startDt': isoOf(e.startDt),
  'endDt': isoOf(e.endDt),
  'isAllDay': e.isAllDay,
  'description': e.description,
  'location': e.location,
  'rrule': e.rrule,
  'deletedAt': isoOf(e.deletedAt),
  'createdAt': isoOf(e.createdAt),
  'updatedAt': isoOf(e.updatedAt),
};

Future<Map<String, Object?>> todoToPayload(AppDatabase db, Todo t) async {
  String? parentSyncId;
  final parentId = t.parentId;
  if (parentId != null) {
    final parent = await (db.select(db.todos)
          ..where((r) => r.id.equals(parentId)))
        .getSingleOrNull();
    parentSyncId = parent?.syncId;
  }
  return <String, Object?>{
    'calendarId': t.calendarId,
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
  };
}

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

/// Calendars do not sync in P2, so a payload calendarId only matches when
/// the ids line up (fresh installs all seed "Personal" first); anything
/// else falls back to the earliest local calendar.
Future<int> resolveCalendarId(AppDatabase db, Object? raw) async {
  if (raw is int) {
    final byId = await (db.select(db.calendars)
          ..where((t) => t.id.equals(raw)))
        .getSingleOrNull();
    if (byId != null) return raw;
  }
  final first = await (db.select(db.calendars)
        ..orderBy([(t) => OrderingTerm.asc(t.id)])
        ..limit(1))
      .getSingleOrNull();
  if (first != null) return first.id;
  return db.into(db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
}
