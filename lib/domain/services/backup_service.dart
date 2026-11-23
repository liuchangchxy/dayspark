import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../data/local/database/app_database.dart';
import '../records/record_scope.dart';
import 'attachment_files.dart';

enum BackupConflictResolution {
  keepLocal,
  keepRemote,
  merge,
}

class BackupConflictItem {
  const BackupConflictItem({
    required this.table,
    required this.id,
    required this.title,
    required this.localDescription,
    required this.remoteDescription,
  });

  final String table;
  final int id;
  final String title;
  final String localDescription;
  final String remoteDescription;

  String get key => '$table:$id';
}

/// Full DaySpark native backup & restore service.
///
/// The package is a zip: `db.json` (every table) plus `attachments/<key>`
/// entries holding the attachment bodies. Metadata-only backups look
/// complete but restore into rows whose files nobody has — the blobs are
/// the part that cannot be reconstructed from anywhere else.
class BackupService {
  static const dbEntryName = 'db.json';
  static const attachmentDir = 'attachments';

  final AppDatabase _db;
  final AttachmentFileStore _files;

  /// Web has no durable local store: bodies cannot be written back, so the
  /// restored rows stay fileless and fetch on first open.
  final bool localFiles;

  BackupService(
    this._db, {
    AttachmentFileStore? files,
    bool? localFiles,
  }) : _files = files ?? AttachmentFileStore(),
       localFiles = localFiles ?? !kIsWeb;

  /// Zip entry holding [fileName]'s bytes. Derived from the row rather than
  /// stored in `db.json` so restore recomputes it instead of trusting a
  /// path (absolute paths from another device mean nothing here).
  static String attachmentEntryName({
    required int id,
    String? syncId,
    required String fileName,
  }) => '$attachmentDir/${syncId ?? 'local$id'}_${sanitizeFileName(fileName)}';

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
                'exdates': e.exdates,
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
                // A todo's recurrence is one unit: the RRULE, the anchor it
                // counts from, and the legacy state that says whether it has
                // been reconciled yet. Dropping any of them turns a weekly
                // todo into a one-off on restore.
                'rrule': t.rrule,
                'recurrenceAnchorSource': t.recurrenceAnchorSource,
                'recurrenceValueType': t.recurrenceValueType,
                'recurrenceAnchorValue': t.recurrenceAnchorValue,
                'recurrenceTimeZone': t.recurrenceTimeZone,
                'recurrenceRule': t.recurrenceRule,
                'recurrenceLegacyState': t.recurrenceLegacyState,
                'recurrenceEvidence': t.recurrenceEvidence,
                'recurrenceRevision': t.recurrenceRevision,
                'percentComplete': t.percentComplete,
                'sortOrder': t.sortOrder,
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

  /// The full package: database plus every attachment body this device
  /// still holds. A row whose file is already gone is exported without
  /// bytes — restore leaves it fileless and the first open re-fetches it
  /// from the server, which is strictly better than failing the export.
  Future<Uint8List> exportZip() async {
    final archive = Archive();
    final json = utf8.encode(await exportJson());
    archive.addFile(ArchiveFile(dbEntryName, json.length, json));
    final attachments = await _db.select(_db.attachments).get();
    for (final a in attachments) {
      final bytes = await _files.read(a.filePath);
      if (bytes == null) continue;
      archive.addFile(
        ArchiveFile(
          attachmentEntryName(
            id: a.id,
            syncId: a.syncId,
            fileName: a.fileName,
          ),
          bytes.length,
          bytes,
        ),
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// Parses a zip package into its decoded data map and archive.
  static ({Map<String, dynamic> data, Archive archive}) decodeZip(
    List<int> bytes,
  ) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile(dbEntryName);
    final raw = entry?.readBytes();
    if (raw == null) {
      throw const FormatException('backup is missing $dbEntryName');
    }
    final dynamic decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup JSON payload');
    }
    return (data: decoded, archive: archive);
  }

  /// Inspects [data] against local database to find conflicting items.
  /// An item is in conflict when its local integer `id` exists locally but has
  /// a different `syncId` / `icsUid`.
  Future<List<BackupConflictItem>> inspectConflicts(
    Map<String, dynamic> data,
  ) async {
    final conflicts = <BackupConflictItem>[];

    // 1. Calendars
    final calendars =
        (data['calendars'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final c in calendars) {
      final remoteId = c['id'] as int?;
      if (remoteId == null) continue;
      final remoteSync = c['syncId'] as String?;
      final remoteName = c['name'] as String? ?? '';
      Calendar? local;
      if (remoteSync != null && remoteSync.isNotEmpty) {
        local = (await (_db.select(_db.calendars)
              ..where((tbl) => tbl.syncId.equals(remoteSync)))
            .get()).firstOrNull;
      }
      final localById = (await (_db.select(_db.calendars)
            ..where((tbl) => tbl.id.equals(remoteId)))
          .get()).firstOrNull;
      if (localById != null) {
        final syncDiffers = remoteSync != null &&
            localById.syncId != null &&
            remoteSync != localById.syncId;
        final nameDiffers = localById.name != remoteName;
        final hasIdCollision = (local == null || local.id != localById.id);
        if (syncDiffers || nameDiffers || hasIdCollision) {
          conflicts.add(
            BackupConflictItem(
              table: 'calendars',
              id: remoteId,
              title: remoteName.isNotEmpty ? remoteName : 'Calendar #$remoteId',
              localDescription: '${localById.name} (${localById.color})',
              remoteDescription: '$remoteName (${c['color']})',
            ),
          );
        }
      }
    }

    // 2. Tags
    final tags =
        (data['tags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final tg in tags) {
      final remoteId = tg['id'] as int?;
      if (remoteId == null) continue;
      final remoteSync = tg['syncId'] as String?;
      final remoteName = tg['name'] as String? ?? '';
      Tag? local;
      if (remoteSync != null && remoteSync.isNotEmpty) {
        local = (await (_db.select(_db.tags)
              ..where((tbl) => tbl.syncId.equals(remoteSync)))
            .get()).firstOrNull;
      }
      final localById = (await (_db.select(_db.tags)
            ..where((tbl) => tbl.id.equals(remoteId)))
          .get()).firstOrNull;
      if (localById != null) {
        final syncDiffers = remoteSync != null &&
            localById.syncId != null &&
            remoteSync != localById.syncId;
        final nameDiffers = localById.name != remoteName;
        final hasIdCollision = (local == null || local.id != localById.id);
        if (syncDiffers || nameDiffers || hasIdCollision) {
          conflicts.add(
            BackupConflictItem(
              table: 'tags',
              id: remoteId,
              title: remoteName.isNotEmpty ? remoteName : 'Tag #$remoteId',
              localDescription: localById.name,
              remoteDescription: remoteName,
            ),
          );
        }
      }
    }

    // 3. Events
    final events =
        (data['events'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final e in events) {
      final remoteId = e['id'] as int?;
      if (remoteId == null) continue;
      final localById = await (_db.select(_db.events)
            ..where((t) => t.id.equals(remoteId)))
          .getSingleOrNull();
      if (localById != null) {
        final remoteSync = e['syncId'] as String?;
        final remoteIcs = e['icsUid'] as String?;
        final isIdentical = localById.summary == e['summary'] &&
            localById.syncId == remoteSync &&
            localById.icsUid == remoteIcs;
        if (!isIdentical) {
          conflicts.add(
            BackupConflictItem(
              table: 'events',
              id: remoteId,
              title: e['summary'] as String? ?? 'Event #$remoteId',
              localDescription: localById.summary,
              remoteDescription: e['summary'] as String? ?? '',
            ),
          );
        }
      }
    }

    // 4. Todos
    final todos =
        (data['todos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final t in todos) {
      final remoteId = t['id'] as int?;
      if (remoteId == null) continue;
      final localById = await (_db.select(_db.todos)
            ..where((tbl) => tbl.id.equals(remoteId)))
          .getSingleOrNull();
      if (localById != null) {
        final remoteSync = t['syncId'] as String?;
        final remoteIcs = t['icsUid'] as String?;
        final isIdentical = localById.summary == t['summary'] &&
            localById.syncId == remoteSync &&
            localById.icsUid == remoteIcs;
        if (!isIdentical) {
          conflicts.add(
            BackupConflictItem(
              table: 'todos',
              id: remoteId,
              title: t['summary'] as String? ?? 'Task #$remoteId',
              localDescription: localById.summary,
              remoteDescription: t['summary'] as String? ?? '',
            ),
          );
        }
      }
    }

    // 5. Reminders
    final reminders =
        (data['reminders'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final r in reminders) {
      final remoteId = r['id'] as int?;
      if (remoteId == null) continue;
      final localById = await (_db.select(_db.reminders)
            ..where((tbl) => tbl.id.equals(remoteId)))
          .getSingleOrNull();
      if (localById != null) {
        final remoteSync = r['syncId'] as String?;
        final syncDiffers = remoteSync != null &&
            localById.syncId != null &&
            remoteSync != localById.syncId;
        final triggerDiffers = localById.triggerTime.toUtc() !=
            DateTime.parse(r['triggerTime'] as String).toUtc();
        final hasIdCollision = (remoteSync == null && localById.syncId != null) ||
            (remoteSync != null && localById.syncId == null) ||
            (remoteSync == null && localById.syncId == null) ||
            syncDiffers;
        if (hasIdCollision || triggerDiffers) {
          conflicts.add(
            BackupConflictItem(
              table: 'reminders',
              id: remoteId,
              title: 'Reminder #$remoteId',
              localDescription: '${localById.parentType} @ ${localById.triggerTime}',
              remoteDescription: '${r['parentType']} @ ${r['triggerTime']}',
            ),
          );
        }
      }
    }

    // 6. Attachments
    final attachments =
        (data['attachments'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final a in attachments) {
      final remoteId = a['id'] as int?;
      if (remoteId == null) continue;
      final localById = await (_db.select(_db.attachments)
            ..where((tbl) => tbl.id.equals(remoteId)))
          .getSingleOrNull();
      if (localById != null) {
        final remoteSync = a['syncId'] as String?;
        final remoteFileName = a['fileName'] as String? ?? '';
        final syncDiffers = remoteSync != null &&
            localById.syncId != null &&
            remoteSync != localById.syncId;
        final nameDiffers = localById.fileName != remoteFileName;
        final hasIdCollision = (remoteSync == null && localById.syncId != null) ||
            (remoteSync != null && localById.syncId == null) ||
            (remoteSync == null && localById.syncId == null) ||
            syncDiffers;
        if (hasIdCollision || nameDiffers) {
          conflicts.add(
            BackupConflictItem(
              table: 'attachments',
              id: remoteId,
              title: remoteFileName.isNotEmpty ? remoteFileName : 'Attachment #$remoteId',
              localDescription: '${localById.fileName} (${localById.fileSize} B)',
              remoteDescription: '$remoteFileName (${a['fileSize']} B)',
            ),
          );
        }
      }
    }

    return conflicts;
  }

  /// Restores a package produced by [exportZip], writing the attachment
  /// bodies back to local storage and repointing their rows at the files.
  Future<void> restoreZip(
    List<int> bytes, {
    Map<String, BackupConflictResolution>? resolutions,
  }) async {
    final decoded = decodeZip(bytes);
    await restoreData(
      decoded.data,
      archive: decoded.archive,
      resolutions: resolutions,
    );
  }

  /// Restores database state from a backup JSON string or decoded map.
  Future<void> restoreFromJson(
    String jsonString, {
    Map<String, BackupConflictResolution>? resolutions,
  }) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup JSON payload');
    }
    await restoreData(decoded, resolutions: resolutions);
  }

  /// Restores data from a parsed backup map inside RecordScope.
  /// Matches items by syncId/icsUid. Unresolved conflicts are skipped.
  Future<void> restoreData(
    Map<String, dynamic> data, {
    Archive? archive,
    Map<String, BackupConflictResolution>? resolutions,
  }) async {
    await RecordScope.run(_db, (tx) async {
      final skippedCalendarIds = <int>{};
      final skippedTagIds = <int>{};
      final skippedEventIds = <int>{};
      final skippedTodoIds = <int>{};

      // 1. Calendars: match by syncId or name
      final calendars =
          (data['calendars'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final calendarIdMap = <int, int>{}; // oldId -> newId

      for (final c in calendars) {
        final oldId = c['id'] as int;
        final syncId = c['syncId'] as String?;
        final name = c['name'] as String;
        final conflictKey = 'calendars:$oldId';

        Calendar? match;
        if (syncId != null && syncId.isNotEmpty) {
          match = (await (_db.select(_db.calendars)
                ..where((tbl) => tbl.syncId.equals(syncId)))
              .get()).firstOrNull;
        }
        final localById = (await (_db.select(_db.calendars)
              ..where((tbl) => tbl.id.equals(oldId)))
            .get()).firstOrNull;
        if (match == null && localById != null && localById.name == name && (localById.syncId == null || localById.syncId == syncId)) {
          match = localById;
        }
        if (match == null) {
          final matchesByName = await (_db.select(_db.calendars)
                ..where((tbl) => tbl.name.equals(name)))
              .get();
          if (matchesByName.isNotEmpty && matchesByName.first.syncId == null && syncId == null) {
            match = matchesByName.first;
          }
        }

        final isConflict = localById != null &&
            ((syncId != null && localById.syncId != null && syncId != localById.syncId) ||
                (localById.name != name));

        if (isConflict) {
          final res = resolutions?[conflictKey];
          if (res == null || res == BackupConflictResolution.keepLocal) {
            skippedCalendarIds.add(oldId);
            continue;
          }
        }

        final companion = CalendarsCompanion(
          name: Value(name),
          color: Value(c['color'] as String),
          timezone: Value(c['timezone'] as String? ?? 'UTC'),
          isActive: Value(c['isActive'] as bool? ?? true),
          sortOrder: Value(c['sortOrder'] as int? ?? 0),
          syncId: Value(syncId),
        );

        if (match != null) {
          calendarIdMap[oldId] = match.id;
          await (_db.update(_db.calendars)..where((tbl) => tbl.id.equals(match!.id)))
              .write(
            companion.copyWith(
              syncId: Value(syncId ?? match.syncId),
            ),
          );
        } else {
          final companionToInsert = (localById == null)
              ? companion.copyWith(id: Value(oldId))
              : companion;
          final newId = await _db.into(_db.calendars).insert(companionToInsert);
          calendarIdMap[oldId] = newId;
        }
      }

      // 2. Tags: match by syncId or name
      final tags = (data['tags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final tagIdMap = <int, int>{};

      for (final tg in tags) {
        final oldId = tg['id'] as int;
        final syncId = tg['syncId'] as String?;
        final name = tg['name'] as String;
        final conflictKey = 'tags:$oldId';

        Tag? match;
        if (syncId != null && syncId.isNotEmpty) {
          match = (await (_db.select(_db.tags)
                ..where((tbl) => tbl.syncId.equals(syncId)))
              .get()).firstOrNull;
        }
        final localById = (await (_db.select(_db.tags)
              ..where((tbl) => tbl.id.equals(oldId)))
            .get()).firstOrNull;
        if (match == null && localById != null && localById.name == name && (localById.syncId == null || localById.syncId == syncId)) {
          match = localById;
        }
        if (match == null) {
          final matchesByName = await (_db.select(_db.tags)
                ..where((tbl) => tbl.name.equals(name)))
              .get();
          if (matchesByName.isNotEmpty && matchesByName.first.syncId == null && syncId == null) {
            match = matchesByName.first;
          }
        }

        final isConflict = localById != null &&
            ((syncId != null && localById.syncId != null && syncId != localById.syncId) ||
                (localById.name != name));

        if (isConflict) {
          final res = resolutions?[conflictKey];
          if (res == null || res == BackupConflictResolution.keepLocal) {
            skippedTagIds.add(oldId);
            continue;
          }
        }

        final companion = TagsCompanion(
          name: Value(name),
          color: Value(tg['color'] as String),
          syncId: Value(syncId),
        );

        if (match != null) {
          tagIdMap[oldId] = match.id;
          await (_db.update(_db.tags)..where((tbl) => tbl.id.equals(match!.id)))
              .write(
            companion.copyWith(
              syncId: Value(syncId ?? match.syncId),
            ),
          );
        } else {
          final companionToInsert = (localById == null)
              ? companion.copyWith(id: Value(oldId))
              : companion;
          final newId = await _db.into(_db.tags).insert(companionToInsert);
          tagIdMap[oldId] = newId;
        }
      }

      // 3. Events: ONLY match by syncId / icsUid non-empty and matching (Rule 19)
      final events =
          (data['events'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final eventIdMap = <int, int>{};

      for (final e in events) {
        final oldId = e['id'] as int;
        final syncId = e['syncId'] as String?;
        final icsUid = e['icsUid'] as String?;
        final conflictKey = 'events:$oldId';

        final rawCalId = e['calendarId'] as int;
        if (skippedCalendarIds.contains(rawCalId)) {
          skippedEventIds.add(oldId);
          continue;
        }

        final localById = (await (_db.select(_db.events)
              ..where((tbl) => tbl.id.equals(oldId)))
            .get()).firstOrNull;

        Event? match;
        if (syncId != null && syncId.isNotEmpty) {
          match = (await (_db.select(_db.events)
                ..where((tbl) => tbl.syncId.equals(syncId)))
              .get()).firstOrNull;
        }
        if (match == null && icsUid != null && icsUid.isNotEmpty) {
          match = (await (_db.select(_db.events)
                ..where((tbl) => tbl.icsUid.equals(icsUid)))
              .get()).firstOrNull;
        }
        // Rule 19: NEVER match by localById!

        final isIdentical = localById != null &&
            localById.summary == e['summary'] &&
            localById.syncId == syncId &&
            localById.icsUid == icsUid;
        if (isIdentical) {
          eventIdMap[oldId] = localById.id;
          continue;
        }

        final hasIdCollision = localById != null && (match == null || match.id != localById.id);
        final isConflict = hasIdCollision ||
            (localById != null &&
                ((syncId != null && localById.syncId != null && syncId != localById.syncId) ||
                    (icsUid != null && localById.icsUid != null && icsUid != localById.icsUid) ||
                    (localById.syncId == null && syncId != null) ||
                    (localById.syncId != null && syncId == null))) ||
            (match != null && match.summary != e['summary']);

        if (isConflict) {
          final res = resolutions?[conflictKey];
          if (res == null || res == BackupConflictResolution.keepLocal) {
            skippedEventIds.add(oldId);
            continue;
          }
        }

        final targetCalId = calendarIdMap[rawCalId] ?? rawCalId;

        final companion = EventsCompanion(
          calendarId: Value(targetCalId),
          summary: Value(e['summary'] as String),
          description: Value(e['description'] as String?),
          startDt: Value(DateTime.parse(e['startDt'] as String).toUtc()),
          endDt: Value(DateTime.parse(e['endDt'] as String).toUtc()),
          isAllDay: Value(e['isAllDay'] as bool? ?? false),
          location: Value(e['location'] as String?),
          rrule: Value(e['rrule'] as String?),
          exdates: Value(e['exdates'] as String?),
          deletedAt: Value(
            e['deletedAt'] == null
                ? null
                : DateTime.parse(e['deletedAt'] as String).toUtc(),
          ),
          syncId: Value(syncId),
          icsUid: Value(icsUid),
        );

        if (match != null) {
          eventIdMap[oldId] = match.id;
          await (_db.update(_db.events)..where((tbl) => tbl.id.equals(match!.id)))
              .write(companion);
          tx.applied(RecordType.event, match.id);
        } else {
          final companionToInsert = (localById == null)
              ? companion.copyWith(id: Value(oldId))
              : companion;
          final newId = await _db.into(_db.events).insert(companionToInsert);
          eventIdMap[oldId] = newId;
          tx.applied(RecordType.event, newId);
        }
      }

      // 4. Todos: ONLY match by syncId / icsUid non-empty and matching (Rule 19)
      // Two-pass parentId restoration (Rule 23)
      final todos =
          (data['todos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final todoIdMap = <int, int>{};
      final pendingParentUpdates = <int, int>{}; // newTodoId -> backupParentId

      for (final t in todos) {
        final oldId = t['id'] as int;
        final syncId = t['syncId'] as String?;
        final icsUid = t['icsUid'] as String?;
        final conflictKey = 'todos:$oldId';

        final rawCalId = t['calendarId'] as int;
        if (skippedCalendarIds.contains(rawCalId)) {
          skippedTodoIds.add(oldId);
          continue;
        }

        final localById = (await (_db.select(_db.todos)
              ..where((tbl) => tbl.id.equals(oldId)))
            .get()).firstOrNull;

        Todo? match;
        if (syncId != null && syncId.isNotEmpty) {
          match = (await (_db.select(_db.todos)
                ..where((tbl) => tbl.syncId.equals(syncId)))
              .get()).firstOrNull;
        }
        if (match == null && icsUid != null && icsUid.isNotEmpty) {
          match = (await (_db.select(_db.todos)
                ..where((tbl) => tbl.icsUid.equals(icsUid)))
              .get()).firstOrNull;
        }
        // Rule 19: NEVER match by localById!

        final isIdentical = localById != null &&
            localById.summary == t['summary'] &&
            localById.syncId == syncId &&
            localById.icsUid == icsUid;
        if (isIdentical) {
          todoIdMap[oldId] = localById.id;
          continue;
        }

        final hasIdCollision = localById != null && (match == null || match.id != localById.id);
        final isConflict = hasIdCollision ||
            (localById != null &&
                ((syncId != null && localById.syncId != null && syncId != localById.syncId) ||
                    (icsUid != null && localById.icsUid != null && icsUid != localById.icsUid) ||
                    (localById.syncId == null && syncId != null) ||
                    (localById.syncId != null && syncId == null))) ||
            (match != null && match.summary != t['summary']);

        if (isConflict) {
          final res = resolutions?[conflictKey];
          if (res == null || res == BackupConflictResolution.keepLocal) {
            skippedTodoIds.add(oldId);
            continue;
          }
        }

        final targetCalId = calendarIdMap[rawCalId] ?? rawCalId;

        final companion = TodosCompanion(
          calendarId: Value(targetCalId),
          summary: Value(t['summary'] as String),
          description: Value(t['description'] as String?),
          dueDate: Value(
            t['dueDate'] == null
                ? null
                : DateTime.parse(t['dueDate'] as String).toUtc(),
          ),
          startDate: Value(
            t['startDate'] == null
                ? null
                : DateTime.parse(t['startDate'] as String).toUtc(),
          ),
          status: Value(t['status'] as String? ?? 'NEEDS-ACTION'),
          completedAt: Value(
            t['completedAt'] == null
                ? null
                : DateTime.parse(t['completedAt'] as String).toUtc(),
          ),
          priority: Value(t['priority'] as int? ?? 0),
          parentId: const Value(null), // Filled in Pass 2
          rrule: Value(t['rrule'] as String?),
          recurrenceAnchorSource: Value(t['recurrenceAnchorSource'] as String?),
          recurrenceValueType: Value(t['recurrenceValueType'] as String?),
          recurrenceAnchorValue: Value(t['recurrenceAnchorValue'] as String?),
          recurrenceTimeZone: Value(t['recurrenceTimeZone'] as String?),
          recurrenceRule: Value(t['recurrenceRule'] as String?),
          recurrenceLegacyState: Value(t['recurrenceLegacyState'] as String?),
          recurrenceEvidence: Value(t['recurrenceEvidence'] as String?),
          recurrenceRevision: Value(t['recurrenceRevision'] as int? ?? 0),
          percentComplete: Value(t['percentComplete'] as int? ?? 0),
          sortOrder: Value(t['sortOrder'] as int? ?? 0),
          deletedAt: Value(
            t['deletedAt'] == null
                ? null
                : DateTime.parse(t['deletedAt'] as String).toUtc(),
          ),
          syncId: Value(syncId),
          icsUid: Value(icsUid),
        );

        final int targetTodoId;
        if (match != null) {
          todoIdMap[oldId] = match.id;
          targetTodoId = match.id;
          await (_db.update(_db.todos)..where((tbl) => tbl.id.equals(match!.id)))
              .write(companion);
          tx.applied(RecordType.todo, match.id);
        } else {
          final companionToInsert = (localById == null)
              ? companion.copyWith(id: Value(oldId))
              : companion;
          final newId = await _db.into(_db.todos).insert(companionToInsert);
          todoIdMap[oldId] = newId;
          targetTodoId = newId;
          tx.applied(RecordType.todo, newId);
        }

        if (t['parentId'] != null) {
          pendingParentUpdates[targetTodoId] = t['parentId'] as int;
        }
      }

      // Pass 2: Backfill parentId (Item 23)
      for (final entry in pendingParentUpdates.entries) {
        final childId = entry.key;
        final rawParentId = entry.value;
        if (skippedTodoIds.contains(rawParentId)) continue;
        final resolvedParentId = todoIdMap[rawParentId];
        if (resolvedParentId != null) {
          await (_db.update(_db.todos)..where((tbl) => tbl.id.equals(childId)))
              .write(TodosCompanion(parentId: Value(resolvedParentId)));
        }
      }

      // 5. Reminders (Item 21: skip if parent was skipped)
      final reminders =
          (data['reminders'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final r in reminders) {
        final parentType = r['parentType'] as String;
        final rawParentId = r['parentId'] as int;
        if (parentType == 'event' && (skippedEventIds.contains(rawParentId) || !eventIdMap.containsKey(rawParentId))) {
          continue;
        }
        if (parentType == 'todo' && (skippedTodoIds.contains(rawParentId) || !todoIdMap.containsKey(rawParentId))) {
          continue;
        }

        final parentId = parentType == 'event'
            ? eventIdMap[rawParentId]!
            : todoIdMap[rawParentId]!;

        final oldId = r['id'] as int;
        final syncId = r['syncId'] as String?;
        final conflictKey = 'reminders:$oldId';

        Reminder? match;
        if (syncId != null && syncId.isNotEmpty) {
          match = await (_db.select(_db.reminders)
                ..where((tbl) => tbl.syncId.equals(syncId)))
              .getSingleOrNull();
        }

        final localById = await (_db.select(_db.reminders)
              ..where((tbl) => tbl.id.equals(oldId)))
            .getSingleOrNull();
        final hasIdCollision = localById != null && (match == null || match.id != localById.id);
        if (hasIdCollision) {
          final res = resolutions?[conflictKey];
          if (res == null || res == BackupConflictResolution.keepLocal) {
            continue;
          }
        }

        final companion = RemindersCompanion(
          parentType: Value(parentType),
          parentId: Value(parentId),
          triggerTime: Value(DateTime.parse(r['triggerTime'] as String).toUtc()),
          isTriggered: Value(r['isTriggered'] as bool? ?? false),
          syncId: Value(syncId),
          parentSyncId: Value(r['parentSyncId'] as String?),
        );

        if (match != null) {
          await (_db.update(_db.reminders)
                ..where((tbl) => tbl.id.equals(match!.id)))
              .write(companion);
        } else {
          final companionToInsert = (localById == null)
              ? companion.copyWith(id: Value(oldId))
              : companion;
          await _db.into(_db.reminders).insert(companionToInsert);
        }
      }

      // 6. EventTags & TodoTags (Item 21: skip if parent was skipped)
      final eventTags =
          (data['eventTags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final et in eventTags) {
        final rawEventId = et['eventId'] as int;
        final rawTagId = et['tagId'] as int;
        if (skippedEventIds.contains(rawEventId) || !eventIdMap.containsKey(rawEventId)) continue;
        if (skippedTagIds.contains(rawTagId) || !tagIdMap.containsKey(rawTagId)) continue;
        final eventId = eventIdMap[rawEventId]!;
        final tagId = tagIdMap[rawTagId]!;
        final syncId = et['syncId'] as String?;

        await _db.into(_db.eventTags).insertOnConflictUpdate(
          EventTagsCompanion(
            eventId: Value(eventId),
            tagId: Value(tagId),
            syncId: Value(syncId),
          ),
        );
      }

      final todoTags =
          (data['todoTags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final tt in todoTags) {
        final rawTodoId = tt['todoId'] as int;
        final rawTagId = tt['tagId'] as int;
        if (skippedTodoIds.contains(rawTodoId) || !todoIdMap.containsKey(rawTodoId)) continue;
        if (skippedTagIds.contains(rawTagId) || !tagIdMap.containsKey(rawTagId)) continue;
        final todoId = todoIdMap[rawTodoId]!;
        final tagId = tagIdMap[rawTagId]!;
        final syncId = tt['syncId'] as String?;

        await _db.into(_db.todoTags).insertOnConflictUpdate(
          TodoTagsCompanion(
            todoId: Value(todoId),
            tagId: Value(tagId),
            syncId: Value(syncId),
          ),
        );
      }

      // 7. Attachments (Item 20 & 21: match by syncId/parentSyncId, preserve local valid path, skip if parent skipped)
      final attachments =
          (data['attachments'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final a in attachments) {
        final id = a['id'] as int;
        final parentType = a['parentType'] as String;
        final rawParentId = a['parentId'] as int;
        if (parentType == 'event' && (skippedEventIds.contains(rawParentId) || !eventIdMap.containsKey(rawParentId))) {
          continue;
        }
        if (parentType == 'todo' && (skippedTodoIds.contains(rawParentId) || !todoIdMap.containsKey(rawParentId))) {
          continue;
        }

        final parentId = parentType == 'event'
            ? eventIdMap[rawParentId]!
            : todoIdMap[rawParentId]!;

        final syncId = a['syncId'] as String?;
        final parentSyncId = a['parentSyncId'] as String?;
        final fileName = a['fileName'] as String;
        final conflictKey = 'attachments:$id';

        Attachment? match;
        if (syncId != null && syncId.isNotEmpty) {
          match = await (_db.select(_db.attachments)
                ..where((tbl) => tbl.syncId.equals(syncId)))
              .getSingleOrNull();
        }
        if (match == null && parentSyncId != null && parentSyncId.isNotEmpty) {
          match = await (_db.select(_db.attachments)
                ..where((tbl) => tbl.parentSyncId.equals(parentSyncId) & tbl.fileName.equals(fileName)))
              .getSingleOrNull();
        }

        final localById = await (_db.select(_db.attachments)
              ..where((tbl) => tbl.id.equals(id)))
            .getSingleOrNull();
        final hasIdCollision = localById != null && (match == null || match.id != localById.id);
        if (hasIdCollision) {
          final res = resolutions?[conflictKey];
          if (res == null || res == BackupConflictResolution.keepLocal) {
            continue;
          }
        }

        final restored = await _restoreAttachmentFile(
          archive: archive,
          id: id,
          syncId: syncId,
          fileName: fileName,
          recordedPath: a['filePath'] as String? ?? '',
          localTargetKey: match != null ? attachmentFileKey(match.id) : null,
        );

        // Preserve local valid path if no body in backup (Item 20)
        final targetPath = restored?.path ??
            (match != null && match.filePath.isNotEmpty ? match.filePath : '');
        final targetSize = restored?.size ??
            (match != null && match.fileSize > 0
                ? match.fileSize
                : (a['fileSize'] as int? ?? 0));

        final companion = AttachmentsCompanion(
          parentType: Value(parentType),
          parentId: Value(parentId),
          filePath: Value(targetPath),
          fileName: Value(fileName),
          fileSize: Value(targetSize),
          mimeType: Value(a['mimeType'] as String?),
          syncId: Value(syncId),
          parentSyncId: Value(parentSyncId),
          serverFileRef: Value(a['serverFileRef'] as String?),
        );

        if (match != null) {
          await (_db.update(_db.attachments)
                ..where((tbl) => tbl.id.equals(match!.id)))
              .write(companion);
        } else {
          final companionToInsert = (localById == null)
              ? companion.copyWith(id: Value(id))
              : companion;
          await _db.into(_db.attachments).insert(companionToInsert);
        }
      }
    });
  }

  Future<({String path, int size})?> _restoreAttachmentFile({
    required Archive? archive,
    required int id,
    required String? syncId,
    required String fileName,
    required String recordedPath,
    String? localTargetKey,
  }) async {
    final entry = archive?.findFile(
      attachmentEntryName(id: id, syncId: syncId, fileName: fileName),
    );
    final bytes = entry?.readBytes();
    if (bytes != null) {
      if (!localFiles) return null;
      final key = localTargetKey ?? attachmentFileKey(id);
      final path = await _files.write(
        key: key,
        fileName: fileName,
        bytes: bytes,
      );
      return (path: path, size: bytes.length);
    }
    // No body in the package: keep the recorded path only when this device
    // really has that file (same-device restore). Otherwise leave the row
    // fileless — a dangling path looks like a working attachment until the
    // user opens it, while an empty one reads as "fetch it from the server".
    final local = await _files.read(recordedPath);
    if (local == null) return null;
    return (path: recordedPath, size: local.length);
  }
}
