import 'dart:async';

import 'package:drift/drift.dart';

import '../../local/database/app_database.dart';
import 'caldav_client.dart';
import 'ical_converter.dart';

/// Sync status reported to the UI.
enum SyncStatus { idle, syncing, success, error }

/// Coordinates two-way sync between local Drift database and CalDAV server.
/// Conflict resolution: server wins.
class SyncService {
  final AppDatabase _db;
  final CalDavClient _client;
  final IcalConverter _converter = IcalConverter();

  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  DateTime? _lastSyncTime;
  Completer<void>? _syncLock;

  bool _tryAcquireLock() {
    if (_syncLock != null) return false;
    _syncLock = Completer<void>();
    return true;
  }

  void _releaseLock() {
    _syncLock?.complete();
    _syncLock = null;
  }

  /// Optional callback for status changes.
  void Function(SyncStatus)? onStatusChanged;

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;

  SyncService({
    required AppDatabase db,
    required CalDavClient client,
    this.onStatusChanged,
  }) : _db = db,
       _client = client;

  // ── Full Sync ──────────────────────────────────────────────────

  /// Run a full sync for all active calendars:
  /// 1. Discover calendars from server
  /// 2. For each calendar: pull remote → upsert local, push dirty local → server
  Future<void> fullSync() async {
    if (!_tryAcquireLock()) return;
    try {
    _setStatus(SyncStatus.syncing);
    _lastError = null;

    try {
      // 1. Discover calendars
      final remoteCalendars = await _client.discoverCalendars();

      for (final remoteCal in remoteCalendars) {
        // Upsert calendar into local DB
        final localCalId = await _upsertCalendar(remoteCal);

        // 2. Pull events
        if (remoteCal.supportsVEVENT) {
          await _pullEvents(localCalId, remoteCal.href);
        }

        // 3. Pull todos
        if (remoteCal.supportsVTODO) {
          await _pullTodos(localCalId, remoteCal.href);
        }
      }

      // 4. Push dirty events
      await _pushDirtyEvents();

      // 5. Push dirty todos
      await _pushDirtyTodos();

      // Update sync metadata
      _lastSyncTime = DateTime.now();
      _setStatus(SyncStatus.success);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SyncStatus.error);
    }
    } finally {
      _releaseLock();
    }
  }

  // ── Incremental Sync ───────────────────────────────────────────

  // TODO(wire-up): Will be wired up to UI/settings for automatic periodic sync.
  /// Run incremental sync using sync-token for calendars that have one.
  Future<void> incrementalSync() async {
    if (!_tryAcquireLock()) return;
    try {
    _setStatus(SyncStatus.syncing);
    _lastError = null;

    try {
      final calendars = await _db.select(_db.calendars).get();

      for (final cal in calendars) {
        if (!cal.isActive) continue;
        if (cal.syncToken == null) {
          // No sync token — fall back to full sync for this calendar
          await _fullSyncCalendar(cal);
          continue;
        }

        try {
          final changes = await _client.getChanges(
            cal.caldavHref,
            cal.syncToken!,
          );

          for (final obj in changes) {
            final type = _converter.detectComponentType(obj.icalData);
            if (type == 'VEVENT') {
              await _upsertEventFromRemote(obj, cal.id);
            } else if (type == 'VTODO') {
              await _upsertTodoFromRemote(obj, cal.id);
            }
          }

          // Update sync token
          final meta = await _client.getCalendarMeta(cal.caldavHref);
          await (_db.update(
            _db.calendars,
          )..where((t) => t.id.equals(cal.id))).write(
            CalendarsCompanion(
              syncToken: Value(meta.syncToken),
              lastSyncedAt: Value(DateTime.now()),
            ),
          );
        } catch (e) {
          // If incremental fails for one calendar, try full sync
          await _fullSyncCalendar(cal);
        }
      }

      await _pushDirtyEvents();
      await _pushDirtyTodos();

      _lastSyncTime = DateTime.now();
      _setStatus(SyncStatus.success);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SyncStatus.error);
    }
    } finally {
      _releaseLock();
    }
  }

  // ── Internal: Calendar Upsert ──────────────────────────────────

  Future<int> _upsertCalendar(CalDavCalendarInfo remoteCal) async {
    // Check if calendar already exists by caldavHref
    final existing = await (_db.select(
      _db.calendars,
    )..where((t) => t.caldavHref.equals(remoteCal.href))).getSingleOrNull();

    if (existing != null) {
      await (_db.update(
        _db.calendars,
      )..where((t) => t.id.equals(existing.id))).write(
        CalendarsCompanion(
          name: Value(remoteCal.name),
          color: Value(remoteCal.color ?? '#2563EB'),
          syncToken: Value(remoteCal.syncToken),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );
      return existing.id;
    }

    return _db
        .into(_db.calendars)
        .insert(
          CalendarsCompanion.insert(
            caldavHref: remoteCal.href,
            name: remoteCal.name,
            color: Value(remoteCal.color ?? '#2563EB'),
            syncToken: Value(remoteCal.syncToken),
            lastSyncedAt: Value(DateTime.now()),
          ),
        );
  }

  // ── Internal: Pull Events ──────────────────────────────────────

  Future<void> _pullEvents(int calendarId, String calendarHref) async {
    final remoteObjects = await _client.getEvents(calendarHref);

    for (final obj in remoteObjects) {
      await _upsertEventFromRemote(obj, calendarId);
    }
  }

  Future<void> _upsertEventFromRemote(CalDavObject obj, int calendarId) async {
    try {
      final companion = _converter.icalToEventCompanion(
        obj.icalData,
        calendarId,
        obj.href,
        obj.etag,
      );

      // Check if event with same UID exists
      final existing =
          await (_db.select(_db.events)..where(
                (t) =>
                    t.calendarId.equals(calendarId) &
                    t.uid.equals(companion.uid.value),
              ))
              .getSingleOrNull();

      if (existing != null) {
        // Server wins: overwrite local even if dirty
        await (_db.update(
          _db.events,
        )..where((t) => t.id.equals(existing.id))).write(
          EventsCompanion(
            summary: companion.summary,
            startDt: companion.startDt,
            endDt: companion.endDt,
            isAllDay: companion.isAllDay,
            description: companion.description,
            location: companion.location,
            rrule: companion.rrule,
            etag: companion.etag,
            isDirty: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await _db.into(_db.events).insert(companion);
      }
    } catch (_) {
      // Skip malformed iCalendar data
    }
  }

  // ── Internal: Pull Todos ───────────────────────────────────────

  Future<void> _pullTodos(int calendarId, String calendarHref) async {
    final remoteObjects = await _client.getTodos(calendarHref);

    for (final obj in remoteObjects) {
      await _upsertTodoFromRemote(obj, calendarId);
    }
  }

  Future<void> _upsertTodoFromRemote(CalDavObject obj, int calendarId) async {
    try {
      final companion = _converter.icalToTodoCompanion(
        obj.icalData,
        calendarId,
        obj.href,
        obj.etag,
      );

      final existing =
          await (_db.select(_db.todos)..where(
                (t) =>
                    t.calendarId.equals(calendarId) &
                    t.uid.equals(companion.uid.value),
              ))
              .getSingleOrNull();

      if (existing != null) {
        await (_db.update(
          _db.todos,
        )..where((t) => t.id.equals(existing.id))).write(
          TodosCompanion(
            summary: companion.summary,
            dueDate: companion.dueDate,
            startDate: companion.startDate,
            priority: companion.priority,
            status: companion.status,
            description: companion.description,
            rrule: companion.rrule,
            completedAt: companion.completedAt,
            percentComplete: companion.percentComplete,
            etag: companion.etag,
            isDirty: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await _db.into(_db.todos).insert(companion);
      }
    } catch (_) {
      // Skip malformed iCalendar data
    }
  }

  // ── Internal: Push Dirty ───────────────────────────────────────

  Future<void> _pushDirtyEvents() async {
    final dirtyEvents = await (_db.select(
      _db.events,
    )..where((t) => t.isDirty.equals(true))).get();

    for (final event in dirtyEvents) {
      try {
        final calendar = await (_db.select(
          _db.calendars,
        )..where((t) => t.id.equals(event.calendarId))).getSingleOrNull();
        if (calendar == null) continue;

        final icalData = _converter.eventToIcal(event);

        String? newEtag;
        if (event.etag != null) {
          final href = '${calendar.caldavHref}${event.uid}.ics';
          newEtag = await _client.updateObject(href, icalData, event.etag!);
        } else {
          newEtag = await _client.createObject(
            calendar.caldavHref,
            event.uid,
            icalData,
          );
        }

        await (_db.update(
          _db.events,
        )..where((t) => t.id.equals(event.id))).write(
          EventsCompanion(
            etag: Value(newEtag),
            isDirty: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } catch (_) {
        // Will be retried on next sync cycle (isDirty stays true)
      }
    }
  }

  Future<void> _pushDirtyTodos() async {
    final dirtyTodos = await (_db.select(
      _db.todos,
    )..where((t) => t.isDirty.equals(true))).get();

    for (final todo in dirtyTodos) {
      try {
        final calendar = await (_db.select(
          _db.calendars,
        )..where((t) => t.id.equals(todo.calendarId))).getSingleOrNull();
        if (calendar == null) continue;

        final icalData = _converter.todoToIcal(todo);

        String? newEtag;
        if (todo.etag != null) {
          final href = '${calendar.caldavHref}${todo.uid}.ics';
          newEtag = await _client.updateObject(href, icalData, todo.etag!);
        } else {
          newEtag = await _client.createObject(
            calendar.caldavHref,
            todo.uid,
            icalData,
          );
        }

        await (_db.update(_db.todos)..where((t) => t.id.equals(todo.id))).write(
          TodosCompanion(
            etag: Value(newEtag),
            isDirty: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } catch (_) {
        // Will be retried on next sync cycle (isDirty stays true)
      }
    }
  }

  // ── Internal: Full Sync Single Calendar ────────────────────────

  Future<void> _fullSyncCalendar(Calendar cal) async {
    final meta = await _client.getCalendarMeta(cal.caldavHref);

    await _pullEvents(cal.id, cal.caldavHref);
    await _pullTodos(cal.id, cal.caldavHref);

    await (_db.update(_db.calendars)..where((t) => t.id.equals(cal.id))).write(
      CalendarsCompanion(
        syncToken: Value(meta.syncToken),
        etag: Value(meta.ctag),
        lastSyncedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Status Helper ──────────────────────────────────────────────

  void _setStatus(SyncStatus status) {
    _status = status;
    onStatusChanged?.call(status);
  }

  /// Dispose resources.
  void dispose() {
    _client.dispose();
  }
}
