import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_engine.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart' as srv;

import '../domain/sync/sync_test_support.dart';

/// Two-device e2e matrix against a REAL server:
///
/// * the server is `srv.AppServer` booted in-process on an ephemeral port
///   with a temp-file SQLite db (real shelf HTTP, real auth, real LWW);
/// * each "device" is its own engine stack — private in-memory Drift db,
///   private outbox/cursor/token stores, private Dio transport — driving
///   rounds explicitly via `requestRound()` (no sleep-based sync).
///
/// Architecture choice (see task-7 report): two engine instances rather
/// than two ProviderContainers — the provider graph pulls in platform
/// channels (secure storage, connectivity, prefs singletons) that the
/// container would only need mocked, while the engine instances exercise
/// the exact production sync path end to end.
class _Device {
  _Device(this.name, String baseUrl) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = _GatedTransport(DioSyncTransport(baseUrl: baseUrl));
    tokens = MemoryTokenStore();
    cursors = MemoryCursorStore();
    snapshots = MemorySnapshotStore();
    api = AuthSyncApiClient(transport: transport, tokens: tokens);
    engine = SyncEngine(
      db: db,
      api: api,
      cursorStore: cursors,
      tokenStore: tokens,
      snapshots: snapshots,
      deviceId: 'device-$name',
    );
  }

  final String name;
  late final AppDatabase db;
  late final _GatedTransport transport;
  late final MemoryTokenStore tokens;
  late final MemoryCursorStore cursors;
  late final MemorySnapshotStore snapshots;
  late final AuthSyncApiClient api;
  late final SyncEngine engine;
  late int calendarId;

  Future<void> dispose() async {
    await engine.stop();
    await db.close();
  }
}

/// Blocks every request while "offline" — the engine round then fails with
/// a transport error exactly like a dead network would.
class _GatedTransport implements SyncTransport {
  _GatedTransport(this._inner);

  final SyncTransport _inner;
  bool online = true;

  @override
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  }) {
    if (!online) return Future.error(const SyncTransportException(0));
    return _inner.send(
      method: method,
      path: path,
      headers: headers,
      body: body,
    );
  }

  @override
  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  }) {
    if (!online) return Future.error(const SyncTransportException(0));
    return _inner.openStream(path: path, headers: headers);
  }
}

/// Explicit round driver: requestRound() + wait until the engine is
/// stably idle (several consecutive polls) so a coalesced follow-up round
/// cannot still be in flight when assertions run. Also pins cursor
/// monotonicity on every driven round.
Future<void> _round(_Device d, {Duration timeout = const Duration(seconds: 10)}) async {
  final before = d.cursors.value ?? 0;
  await d.engine.requestRound();
  var stable = 0;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = d.engine.status;
    final idle = status.phase == SyncPhase.idle && status.lastError == null;
    stable = idle ? stable + 1 : 0;
    if (stable >= 4) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final status = d.engine.status;
  expect(
    status.phase == SyncPhase.idle && status.lastError == null,
    isTrue,
    reason: '${d.name} round must settle idle (phase=${status.phase}, '
        'error=${status.lastError})',
  );
  expect(
    d.cursors.value ?? 0,
    greaterThanOrEqualTo(before),
    reason: '${d.name} cursor must be monotonic',
  );
}

Future<int> _seedCalendar(AppDatabase db) =>
    db.into(db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));

Future<int> _createEvent(
  _Device d, {
  required String summary,
  required DateTime start,
  required DateTime end,
  String? description,
}) {
  return d.db.transaction(() async {
    final id = await d.db.into(d.db.events).insert(
          EventsCompanion.insert(
            calendarId: d.calendarId,
            summary: summary,
            startDt: start,
            endDt: end,
            description: Value(description),
          ),
        );
    await SyncOutbox.enqueueUpsert(d.db, RecordType.event, id);
    return id;
  });
}

Future<void> _editEvent(
  _Device d,
  int localId, {
  String? summary,
  DateTime? start,
  DateTime? end,
  String? description,
}) {
  return d.db.transaction(() async {
    await (d.db.update(d.db.events)..where((t) => t.id.equals(localId))).write(
      EventsCompanion(
        summary: summary == null ? const Value.absent() : Value(summary),
        startDt: start == null ? const Value.absent() : Value(start),
        endDt: end == null ? const Value.absent() : Value(end),
        description:
            description == null ? const Value.absent() : Value(description),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await SyncOutbox.enqueueUpsert(d.db, RecordType.event, localId);
  });
}

Future<void> _deleteEvent(_Device d, int localId) {
  return d.db.transaction(() async {
    final now = DateTime.now();
    await (d.db.update(d.db.events)..where((t) => t.id.equals(localId)))
        .write(EventsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await SyncOutbox.enqueueDelete(d.db, RecordType.event, localId);
  });
}

Future<Event> _eventBySyncId(AppDatabase db, String syncId) async {
  final row = await (db.select(db.events)
        ..where((t) => t.syncId.equals(syncId)))
      .getSingleOrNull();
  expect(row, isNotNull, reason: 'record $syncId must exist');
  return row!;
}

Future<String> _syncIdOf(AppDatabase db, int localId) async {
  final row =
      await (db.select(db.events)..where((t) => t.id.equals(localId)))
          .getSingle();
  expect(row.syncId, isNotNull, reason: 'row must be enqueued at least once');
  return row.syncId!;
}

void _expectConverged(Event x, Event y, {required String reason}) {
  expect(y.summary, x.summary, reason: '$reason: summary');
  expect(y.startDt, x.startDt, reason: '$reason: startDt');
  expect(y.endDt, x.endDt, reason: '$reason: endDt');
  expect(y.description, x.description, reason: '$reason: description');
  expect(y.location, x.location, reason: '$reason: location');
  expect(y.isAllDay, x.isAllDay, reason: '$reason: isAllDay');
  expect(y.rrule, x.rrule, reason: '$reason: rrule');
  expect(y.deletedAt, x.deletedAt, reason: '$reason: deletedAt');
  expect(y.createdAt, x.createdAt, reason: '$reason: createdAt');
  expect(y.updatedAt, x.updatedAt, reason: '$reason: updatedAt');
  expect(y.serverRev, x.serverRev, reason: '$reason: serverRev');
  expect(y.syncId, x.syncId, reason: '$reason: syncId');
  expect(y.calendarId, x.calendarId, reason: '$reason: calendarId');
}

void main() {
  // Two devices = two intentional AppDatabase instances per test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late srv.AppServer app;
  late HttpServer http;
  late Directory tempDir;
  late String baseUrl;
  late _Device a;
  late _Device b;
  var registerSeq = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dayspark_e2e_');
    app = srv.AppServer(
      srv.Config(
        dbPath: '${tempDir.path}/server.db',
        port: 0,
        jwtSecret: 'e2e-secret',
      ),
    );
    http = await app.serve();
    baseUrl = 'http://127.0.0.1:${http.port}';

    a = _Device('A', baseUrl);
    b = _Device('B', baseUrl);
    a.calendarId = await _seedCalendar(a.db);
    b.calendarId = await _seedCalendar(b.db);

    // Same user, two devices: register once on A, hand the token pair to
    // both token stores (protocol is per-user; each device keeps its own
    // stores/engine/cursor).
    final session = await a.api.register(
      email: 'e2e-${registerSeq++}@dayspark.test',
      password: 'password123',
    );
    await a.tokens.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await b.tokens.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    await a.engine.start();
    await b.engine.start();
    await _round(a);
    await _round(b);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await http.close(force: true);
    await app.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('create on A appears on B after both rounds', () async {
    final localId = await _createEvent(
      a,
      summary: 'standup',
      start: DateTime(2026, 9, 24, 10),
      end: DateTime(2026, 9, 24, 11),
      description: 'daily sync',
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);
    expect(onB.summary, 'standup');
    expect(onB.startDt, DateTime(2026, 9, 24, 10));
    expect(onB.serverRev, 1);
    expect(onA.serverRev, 1);
    _expectConverged(onA, onB, reason: 'case 1 create');
  });

  test('edit title+time on A converges to the same merged truth on B',
      () async {
    final localId = await _createEvent(
      a,
      summary: 'planning',
      start: DateTime(2026, 9, 25, 9),
      end: DateTime(2026, 9, 25, 10),
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);

    await _editEvent(
      a,
      localId,
      summary: 'planning (moved)',
      start: DateTime(2026, 9, 25, 14),
      end: DateTime(2026, 9, 25, 15, 30),
    );
    await _round(a);
    await _round(b);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);
    expect(onB.summary, 'planning (moved)');
    expect(onB.startDt, DateTime(2026, 9, 25, 14));
    expect(onB.endDt, DateTime(2026, 9, 25, 15, 30));
    expect(onB.serverRev, 2, reason: 'edit bumps rev once');
    _expectConverged(onA, onB, reason: 'case 2 edit');
  });

  test('delete on A tombstones the record on B', () async {
    final localId = await _createEvent(
      a,
      summary: 'cancelled meeting',
      start: DateTime(2026, 9, 26, 13),
      end: DateTime(2026, 9, 26, 14),
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);

    await _deleteEvent(a, localId);
    await _round(a);
    await _round(b);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);
    expect(onA.deletedAt, isNotNull, reason: 'A trashes locally');
    expect(onB.deletedAt, isNotNull, reason: 'B mirrors the tombstone');
    expect(onB.serverRev, 2);
    _expectConverged(onA, onB, reason: 'case 3 delete');
  });

  test('offline edit on B + concurrent edit on A → server truth wins, '
      'both devices converge', () async {
    final localId = await _createEvent(
      a,
      summary: 'shared note',
      start: DateTime(2026, 9, 27, 9),
      end: DateTime(2026, 9, 27, 10),
      description: 'original',
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);
    final localB = (await _eventBySyncId(b.db, syncId)).id;

    // --- B goes offline: every transport call is refused. ---
    b.transport.online = false;
    await _editEvent(
      b,
      localB,
      summary: 'B offline title',
      start: DateTime(2026, 9, 27, 11),
      end: DateTime(2026, 9, 27, 12),
    );
    // A edits the same record meanwhile (disjoint field: description).
    await _editEvent(a, localId, description: 'A online description');
    await _round(a);

    // A round while offline must fail cleanly and keep the pending op.
    await b.engine.requestRound();
    expect(b.engine.status.phase, SyncPhase.error,
        reason: 'offline round surfaces a transport error');
    expect(await (b.db.select(b.db.syncOutbox)).get(), isNotEmpty,
        reason: 'failed round must not drop the pending op');

    // --- B comes back online. ---
    b.transport.online = true;
    await _round(b);
    await _round(a);

    final onA = await _eventBySyncId(a.db, syncId);
    final onB = await _eventBySyncId(b.db, syncId);

    // Documented LWW (server/lib/src/sync/lww.dart): keys each op SET win
    // in op arrival order. B's offline push reached the server last, so it
    // owns summary/start/end; A set description only, so that key keeps
    // A's value — field-level merge, no lost update on either side.
    expect(onB.summary, 'B offline title');
    expect(onB.startDt, DateTime(2026, 9, 27, 11));
    expect(onB.description, 'A online description');
    expect(onB.serverRev, 3, reason: 'create + A edit + B edit = rev 3');
    _expectConverged(onA, onB, reason: 'case 4 offline conflict');
    expect(a.engine.status.lastRejected, isEmpty);
    expect(b.engine.status.lastRejected, isEmpty);
    expect(await (b.db.select(b.db.syncOutbox)).get(), isEmpty,
        reason: 'B outbox drained after reconnect');
  });

  test('two rounds of alternating edits converge; cursors stay monotonic',
      () async {
    final localId = await _createEvent(
      a,
      summary: 'round 0',
      start: DateTime(2026, 9, 28, 8),
      end: DateTime(2026, 9, 28, 9),
    );
    await _round(a);
    final syncId = await _syncIdOf(a.db, localId);
    await _round(b);
    final localB = (await _eventBySyncId(b.db, syncId)).id;

    final trace = <String, List<int>>{
      'A': [a.cursors.value ?? 0],
      'B': [b.cursors.value ?? 0],
    };

    // Round 1: A edits, B follows.
    await _editEvent(a, localId, summary: 'round 1 (A)');
    await _round(a);
    trace['A']!.add(a.cursors.value ?? 0);
    await _round(b);
    trace['B']!.add(b.cursors.value ?? 0);
    var onA = await _eventBySyncId(a.db, syncId);
    var onB = await _eventBySyncId(b.db, syncId);
    expect(onB.summary, 'round 1 (A)');
    _expectConverged(onA, onB, reason: 'alternating round 1');

    // Round 2: B edits back, A follows.
    await _editEvent(
      b,
      localB,
      summary: 'round 2 (B)',
      start: DateTime(2026, 9, 28, 18),
      end: DateTime(2026, 9, 28, 19),
    );
    await _round(b);
    trace['B']!.add(b.cursors.value ?? 0);
    await _round(a);
    trace['A']!.add(a.cursors.value ?? 0);
    onA = await _eventBySyncId(a.db, syncId);
    onB = await _eventBySyncId(b.db, syncId);
    expect(onA.summary, 'round 2 (B)');
    expect(onB.startDt, DateTime(2026, 9, 28, 18));
    _expectConverged(onA, onB, reason: 'alternating round 2');
    expect(onA.serverRev, 3);

    for (final entry in trace.entries) {
      final values = entry.value;
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]),
            reason: '${entry.key} cursor must never go backwards: $values');
      }
      expect(values.last, greaterThan(values.first),
          reason: '${entry.key} cursor must advance across the rounds: '
              '$values');
    }
  });
}
