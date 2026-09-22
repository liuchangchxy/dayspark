import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import 'sync_payload.dart';

/// Writes server truth onto local rows (P2 scope: event + todo).
///
/// Protocol: applies unconditionally — push rounds run before pull, so
/// pending local ops were already resolved against the server; pull never
/// consults the outbox (records whose push result was `conflict` were
/// overwritten here and dropped from the outbox during the push step).
class SyncApplier {
  SyncApplier(this.db);

  final AppDatabase db;

  /// Returns false when the record is malformed or is a tombstone with no
  /// local row (nothing to soft-delete); such records are skipped instead
  /// of failing the whole round.
  Future<bool> apply(SyncRecord record) async {
    try {
      return switch (record.type) {
        RecordType.event => await _applyEvent(record),
        RecordType.todo => await _applyTodo(record),
      };
    } on FormatException catch (e) {
      debugPrint('sync applier: skip ${record.id}: $e');
      return false;
    }
  }

  Future<bool> _applyEvent(SyncRecord record) async {
    final payload = record.payload;
    final existing = await (db.select(db.events)
          ..where((t) => t.syncId.equals(record.id)))
        .getSingleOrNull();

    if (record.deleted) {
      if (existing == null) return false;
      if (existing.deletedAt != null) {
        await _bumpEventRev(existing.id, record.rev);
      } else {
        // Local trash mirrors the server tombstone; the row itself stays
        // so the recycle-bin restore path keeps working.
        await (db.update(db.events)..where((t) => t.id.equals(existing.id)))
            .write(EventsCompanion(
          deletedAt: Value(record.serverTs),
          updatedAt: Value(record.serverTs),
          serverRev: Value(record.rev),
        ));
      }
      return true;
    }

    final companion = EventsCompanion(
      calendarId: Value(await resolveCalendarId(db, payload['calendarId'])),
      summary: Value(requireString(payload, 'summary')),
      startDt: Value(requireDateTime(payload, 'startDt')),
      endDt: Value(requireDateTime(payload, 'endDt')),
      isAllDay: Value(optionalBool(payload['isAllDay']) ?? false),
      description: Value(optionalString(payload['description'])),
      location: Value(optionalString(payload['location'])),
      rrule: Value(optionalString(payload['rrule'])),
      deletedAt: Value(parseIso(payload['deletedAt'])),
      createdAt: Value(parseIso(payload['createdAt']) ?? DateTime.now()),
      updatedAt: Value(parseIso(payload['updatedAt']) ?? record.serverTs),
      syncId: Value(record.id),
      serverRev: Value(record.rev),
    );
    if (existing == null) {
      await db.into(db.events).insert(companion);
    } else {
      await (db.update(db.events)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
    return true;
  }

  Future<bool> _applyTodo(SyncRecord record) async {
    final payload = record.payload;
    final existing = await (db.select(db.todos)
          ..where((t) => t.syncId.equals(record.id)))
        .getSingleOrNull();

    if (record.deleted) {
      if (existing == null) return false;
      if (existing.deletedAt != null) {
        await _bumpTodoRev(existing.id, record.rev);
      } else {
        await (db.update(db.todos)..where((t) => t.id.equals(existing.id)))
            .write(TodosCompanion(
          deletedAt: Value(record.serverTs),
          updatedAt: Value(record.serverTs),
          serverRev: Value(record.rev),
        ));
      }
      return true;
    }

    int? parentId;
    if (payload.containsKey('parentSyncId')) {
      final raw = payload['parentSyncId'];
      if (raw is String) {
        final parent = await (db.select(db.todos)
              ..where((t) => t.syncId.equals(raw)))
            .getSingleOrNull();
        // Parent not on this device yet → keep the child top-level rather
        // than dangling a local integer id that means nothing here.
        parentId = parent?.id;
      }
    }

    final companion = TodosCompanion(
      calendarId: Value(await resolveCalendarId(db, payload['calendarId'])),
      summary: Value(requireString(payload, 'summary')),
      dueDate: Value(parseIso(payload['dueDate'])),
      startDate: Value(parseIso(payload['startDate'])),
      priority: Value(optionalInt(payload['priority']) ?? 0),
      status: Value(optionalString(payload['status']) ?? 'NEEDS-ACTION'),
      description: Value(optionalString(payload['description'])),
      rrule: Value(optionalString(payload['rrule'])),
      completedAt: Value(parseIso(payload['completedAt'])),
      percentComplete: Value(optionalInt(payload['percentComplete']) ?? 0),
      deletedAt: Value(parseIso(payload['deletedAt'])),
      createdAt: Value(parseIso(payload['createdAt']) ?? DateTime.now()),
      updatedAt: Value(parseIso(payload['updatedAt']) ?? record.serverTs),
      sortOrder: Value(optionalInt(payload['sortOrder']) ?? 0),
      parentId: Value(parentId),
      syncId: Value(record.id),
      serverRev: Value(record.rev),
    );
    if (existing == null) {
      await db.into(db.todos).insert(companion);
    } else {
      await (db.update(db.todos)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
    return true;
  }

  Future<void> _bumpEventRev(int id, int rev) async {
    await (db.update(db.events)..where((t) => t.id.equals(id)))
        .write(EventsCompanion(serverRev: Value(rev)));
  }

  Future<void> _bumpTodoRev(int id, int rev) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id)))
        .write(TodosCompanion(serverRev: Value(rev)));
  }
}
