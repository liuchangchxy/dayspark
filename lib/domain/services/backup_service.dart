import 'dart:convert';
import 'package:drift/drift.dart';
import '../../data/local/database/app_database.dart';

/// Full DaySpark native backup & restore service.
/// Exports entire local database state to a JSON string or file,
/// and restores from a previously exported backup payload.
class BackupService {
  final AppDatabase _db;

  BackupService(this._db);

  /// Exports all tables to a structured map.
  Future<Map<String, dynamic>> exportData() async {
    final calendars = await _db.select(_db.calendars).get();
    final events = await _db.select(_db.events).get();
    final todos = await _db.select(_db.todos).get();
    final reminders = await _db.select(_db.reminders).get();
    final tags = await _db.select(_db.tags).get();
    final eventTags = await _db.select(_db.eventTags).get();
    final todoTags = await _db.select(_db.todoTags).get();
    final attachments = await _db.select(_db.attachments).get();

    return {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'calendars': calendars
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'color': c.color,
                'timezone': c.timezone,
                'isActive': c.isActive,
                'sortOrder': c.sortOrder,
                'syncId': c.syncId,
              })
          .toList(),
      'events': events
          .map((e) => {
                'id': e.id,
                'calendarId': e.calendarId,
                'summary': e.summary,
                'description': e.description,
                'startDt': e.startDt.toUtc().toIso8601String(),
                'endDt': e.endDt.toUtc().toIso8601String(),
                'isAllDay': e.isAllDay,
                'location': e.location,
                'rrule': e.rrule,
                'deletedAt': e.deletedAt?.toUtc().toIso8601String(),
                'syncId': e.syncId,
                'icsUid': e.icsUid,
              })
          .toList(),
      'todos': todos
          .map((t) => {
                'id': t.id,
                'calendarId': t.calendarId,
                'summary': t.summary,
                'description': t.description,
                'dueDate': t.dueDate?.toUtc().toIso8601String(),
                'startDate': t.startDate?.toUtc().toIso8601String(),
                'status': t.status,
                'completedAt': t.completedAt?.toUtc().toIso8601String(),
                'priority': t.priority,
                'parentId': t.parentId,
                'deletedAt': t.deletedAt?.toUtc().toIso8601String(),
                'syncId': t.syncId,
                'icsUid': t.icsUid,
              })
          .toList(),
      'reminders': reminders
          .map((r) => {
                'id': r.id,
                'parentType': r.parentType,
                'parentId': r.parentId,
                'triggerTime': r.triggerTime.toUtc().toIso8601String(),
                'isTriggered': r.isTriggered,
                'syncId': r.syncId,
                'parentSyncId': r.parentSyncId,
              })
          .toList(),
      'tags': tags
          .map((tg) => {
                'id': tg.id,
                'name': tg.name,
                'color': tg.color,
                'syncId': tg.syncId,
              })
          .toList(),
      'eventTags': eventTags
          .map((et) => {
                'eventId': et.eventId,
                'tagId': et.tagId,
                'syncId': et.syncId,
              })
          .toList(),
      'todoTags': todoTags
          .map((tt) => {
                'todoId': tt.todoId,
                'tagId': tt.tagId,
                'syncId': tt.syncId,
              })
          .toList(),
      'attachments': attachments
          .map((a) => {
                'id': a.id,
                'parentType': a.parentType,
                'parentId': a.parentId,
                'filePath': a.filePath,
                'fileName': a.fileName,
                'fileSize': a.fileSize,
                'mimeType': a.mimeType,
                'syncId': a.syncId,
                'parentSyncId': a.parentSyncId,
                'serverFileRef': a.serverFileRef,
              })
          .toList(),
    };
  }

  /// Exports all data directly to a formatted JSON string.
  Future<String> exportJson() async {
    final map = await exportData();
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Restores database state from a backup JSON string or decoded map.
  Future<void> restoreFromJson(String jsonString) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup JSON payload');
    }
    await restoreData(decoded);
  }

  /// Restores data from a parsed backup map inside a single transaction.
  Future<void> restoreData(Map<String, dynamic> data) async {
    await _db.transaction(() async {
      final calendars = (data['calendars'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final c in calendars) {
        await _db.into(_db.calendars).insertOnConflictUpdate(
          CalendarsCompanion(
            id: Value(c['id'] as int),
            name: Value(c['name'] as String),
            color: Value(c['color'] as String),
            timezone: Value(c['timezone'] as String? ?? 'UTC'),
            isActive: Value(c['isActive'] as bool? ?? true),
            sortOrder: Value(c['sortOrder'] as int? ?? 0),
            syncId: Value(c['syncId'] as String?),
          ),
        );
      }

      final tags = (data['tags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final tg in tags) {
        await _db.into(_db.tags).insertOnConflictUpdate(
          TagsCompanion(
            id: Value(tg['id'] as int),
            name: Value(tg['name'] as String),
            color: Value(tg['color'] as String),
            syncId: Value(tg['syncId'] as String?),
          ),
        );
      }

      final events = (data['events'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final e in events) {
        await _db.into(_db.events).insertOnConflictUpdate(
          EventsCompanion(
            id: Value(e['id'] as int),
            calendarId: Value(e['calendarId'] as int),
            summary: Value(e['summary'] as String),
            description: Value(e['description'] as String?),
            startDt: Value(DateTime.parse(e['startDt'] as String).toUtc()),
            endDt: Value(DateTime.parse(e['endDt'] as String).toUtc()),
            isAllDay: Value(e['isAllDay'] as bool? ?? false),
            location: Value(e['location'] as String?),
            rrule: Value(e['rrule'] as String?),
            deletedAt: Value(e['deletedAt'] == null ? null : DateTime.parse(e['deletedAt'] as String).toUtc()),
            syncId: Value(e['syncId'] as String?),
            icsUid: Value(e['icsUid'] as String?),
          ),
        );
      }

      final todos = (data['todos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final t in todos) {
        await _db.into(_db.todos).insertOnConflictUpdate(
          TodosCompanion(
            id: Value(t['id'] as int),
            calendarId: Value(t['calendarId'] as int),
            summary: Value(t['summary'] as String),
            description: Value(t['description'] as String?),
            dueDate: Value(t['dueDate'] == null ? null : DateTime.parse(t['dueDate'] as String).toUtc()),
            startDate: Value(t['startDate'] == null ? null : DateTime.parse(t['startDate'] as String).toUtc()),
            status: Value(t['status'] as String? ?? 'NEEDS-ACTION'),
            completedAt: Value(t['completedAt'] == null ? null : DateTime.parse(t['completedAt'] as String).toUtc()),
            priority: Value(t['priority'] as int? ?? 0),
            parentId: Value(t['parentId'] as int?),
            deletedAt: Value(t['deletedAt'] == null ? null : DateTime.parse(t['deletedAt'] as String).toUtc()),
            syncId: Value(t['syncId'] as String?),
            icsUid: Value(t['icsUid'] as String?),
          ),
        );
      }

      final reminders = (data['reminders'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final r in reminders) {
        await _db.into(_db.reminders).insertOnConflictUpdate(
          RemindersCompanion(
            id: Value(r['id'] as int),
            parentType: Value(r['parentType'] as String),
            parentId: Value(r['parentId'] as int),
            triggerTime: Value(DateTime.parse(r['triggerTime'] as String).toUtc()),
            isTriggered: Value(r['isTriggered'] as bool? ?? false),
            syncId: Value(r['syncId'] as String?),
            parentSyncId: Value(r['parentSyncId'] as String?),
          ),
        );
      }

      final eventTags = (data['eventTags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final et in eventTags) {
        await _db.into(_db.eventTags).insertOnConflictUpdate(
          EventTagsCompanion(
            eventId: Value(et['eventId'] as int),
            tagId: Value(et['tagId'] as int),
            syncId: Value(et['syncId'] as String?),
          ),
        );
      }

      final todoTags = (data['todoTags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final tt in todoTags) {
        await _db.into(_db.todoTags).insertOnConflictUpdate(
          TodoTagsCompanion(
            todoId: Value(tt['todoId'] as int),
            tagId: Value(tt['tagId'] as int),
            syncId: Value(tt['syncId'] as String?),
          ),
        );
      }

      final attachments = (data['attachments'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final a in attachments) {
        await _db.into(_db.attachments).insertOnConflictUpdate(
          AttachmentsCompanion(
            id: Value(a['id'] as int),
            parentType: Value(a['parentType'] as String),
            parentId: Value(a['parentId'] as int),
            filePath: Value(a['filePath'] as String? ?? ''),
            fileName: Value(a['fileName'] as String),
            fileSize: Value(a['fileSize'] as int? ?? 0),
            mimeType: Value(a['mimeType'] as String?),
            syncId: Value(a['syncId'] as String?),
            parentSyncId: Value(a['parentSyncId'] as String?),
            serverFileRef: Value(a['serverFileRef'] as String?),
          ),
        );
      }
    });
  }
}
