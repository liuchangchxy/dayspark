import 'dart:convert';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_engine.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_settings.dart';
import 'package:dayspark/domain/sync/cloud/cloud_sync_state.dart';
import 'package:dayspark/domain/sync/sync_config.dart';
import 'package:dayspark/domain/sync/sync_outbox.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sync_test_support.dart';
import 'cloud_test_support.dart';

class _Device {
  _Device(this.db, this.snapshots, this.states, this.backend);

  factory _Device.open(MemoryCloudBackend backend) => _Device(
    AppDatabase.forTesting(NativeDatabase.memory()),
    MemorySnapshotStore(),
    MemoryCloudStateStore(),
    backend,
  );

  final AppDatabase db;
  final MemorySnapshotStore snapshots;
  final MemoryCloudStateStore states;
  final MemoryCloudBackend backend;
  late final CloudSyncEngine engine = CloudSyncEngine(
    db: db,
    backend: backend,
    snapshots: snapshots,
    stateStore: states,
    clock: () => DateTime.utc(2026, 11, 14, 10),
  );

  Future<void> close() => db.close();

  Future<int> seedTodo(String summary) async {
    final calendarId = (await (db.select(
      db.calendars,
    )..limit(1)).getSingle()).id;
    return db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: summary,
            status: const Value('NEEDS-ACTION'),
          ),
        );
  }

  Future<void> editSummary(int id, String summary) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(summary: Value(summary)),
    );
    await RecordScope.run(db, (_) async {
      await SyncOutbox.enqueueUpsert(db, RecordType.todo, id);
    });
  }

  Future<void> softDelete(int id) async {
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(
      TodosCompanion(deletedAt: Value(DateTime.utc(2026, 11, 14, 9))),
    );
    await RecordScope.run(db, (_) async {
      await SyncOutbox.enqueueDelete(db, RecordType.todo, id);
    });
  }

  Future<Todo?> todoBySummary(String summary) =>
      (db.select(db.todos)..where((t) => t.summary.equals(summary)))
          .getSingleOrNull();
}

void main() {
  late MemoryCloudBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = MemoryCloudBackend();
  });

  test('the first round sends every existing row and drains the outbox', () async {
    final a = _Device.open(backend);
    addTearDown(a.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('buy milk');
    await a.seedTodo('call mum');

    expect(await a.engine.syncNow(), isTrue);

    final document = CloudSyncState.fromJson(
      jsonDecode(backend.body!) as Map<String, dynamic>,
    );
    expect(document.records, hasLength(2));
    expect(
      document.records.values.every((e) => e.record.type == RecordType.todo),
      isTrue,
    );
    expect(await (a.db.select(a.db.syncOutbox)).get(), isEmpty);
    expect(a.states.provisioned, isTrue);
    expect(a.states.etag, backend.etag);
  });

  test('a round with nothing to send does not rewrite the document', () async {
    final a = _Device.open(backend);
    addTearDown(a.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('buy milk');
    await a.engine.syncNow();
    final writes = backend.writes;

    expect(await a.engine.syncNow(), isTrue);
    expect(backend.writes, writes);
  });

  test('a second device restores everything and its edit flows back', () async {
    final a = _Device.open(backend);
    final b = _Device.open(backend);
    addTearDown(a.close);
    addTearDown(b.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('buy milk');
    await a.engine.syncNow();

    await b.db.into(b.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await b.engine.syncNow();
    final restored = await b.todoBySummary('buy milk');
    expect(restored, isNotNull);
    expect(restored!.syncId, isNotNull);

    await b.editSummary(restored.id, 'buy oat milk');
    await b.engine.syncNow();
    await a.engine.syncNow();

    expect(await a.todoBySummary('buy milk'), isNull);
    expect((await a.todoBySummary('buy oat milk'))!.syncId, restored.syncId);
  });

  test('a deletion on one device deletes it on the other', () async {
    final a = _Device.open(backend);
    final b = _Device.open(backend);
    addTearDown(a.close);
    addTearDown(b.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    final id = await a.seedTodo('buy milk');
    await a.engine.syncNow();

    await b.db.into(b.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await b.engine.syncNow();
    expect(await b.todoBySummary('buy milk'), isNotNull);

    await a.softDelete(id);
    await a.engine.syncNow();
    await b.engine.syncNow();

    final onB = await b.todoBySummary('buy milk');
    expect(onB, isNotNull);
    expect(onB!.deletedAt, isNotNull);
  });

  test('repeating a round never duplicates records', () async {
    final a = _Device.open(backend);
    addTearDown(a.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('buy milk');
    for (var i = 0; i < 4; i++) {
      expect(await a.engine.syncNow(), isTrue);
    }
    final document = CloudSyncState.fromJson(
      jsonDecode(backend.body!) as Map<String, dynamic>,
    );
    expect(document.records, hasLength(1));
  });

  test('a lost race re-reads and merges instead of overwriting the peer', () async {
    final a = _Device.open(backend);
    addTearDown(a.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('mine');

    final peerState = mergeCloudOps(
      state: CloudSyncState.empty(),
      ops: [
        const CloudOp(
          opId: 'op-peer',
          recordId: 'peer-todo',
          type: RecordType.todo,
          op: OpType.upsert,
          fields: {'summary': 'theirs'},
          baseRev: 0,
        ),
      ],
      now: DateTime.utc(2026, 11, 14, 9),
    ).state;
    backend.dropNextWrites = 1;
    backend.peerBody = jsonEncode(peerState.toJson());

    expect(await a.engine.syncNow(), isTrue);

    final document = CloudSyncState.fromJson(
      jsonDecode(backend.body!) as Map<String, dynamic>,
    );
    expect(document.records.keys, contains('peer-todo'));
    expect(document.records, hasLength(2));
    expect(
      document.records.values.where((e) => e.record.payload['summary'] == 'theirs'),
      hasLength(1),
    );
    expect(backend.writes, 2);
  });

  test('a switched source starts from a clean diff base', () async {
    final a = _Device.open(backend);
    addTearDown(a.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('buy milk');
    await a.engine.syncNow();
    expect(a.snapshots.values, isNotEmpty);

    final prefs = await SharedPreferences.getInstance();
    final sources = PrefsCloudSyncSourceStore(prefs);
    final cursors = PrefsSyncCursorStore(prefs);
    await cursors.write(12);
    final switcher = CloudSourceSwitch(
      sources: sources,
      stateStore: a.states,
      cursorStore: cursors,
      snapshots: a.snapshots,
    );
    await switcher.switchTo(CloudSyncSource.webdav);

    expect(sources.read(), CloudSyncSource.webdav);
    expect(a.snapshots.values, isEmpty);
    expect(a.states.etag, isNull);
    expect(a.states.provisioned, isFalse);
    expect(await cursors.read(), isNull);
  });

  test('a source switch re-sends rows that already had a syncId', () async {
    final a = _Device.open(backend);
    addTearDown(a.close);
    await a.db.into(a.db.calendars).insert(CalendarsCompanion.insert(name: 'Personal'));
    await a.seedTodo('buy milk');
    await a.engine.syncNow();
    final syncId = a.snapshots.values.keys.single;
    expect(syncId, isNotEmpty);

    // What a switch leaves behind: valid rows, no diff base, no validator.
    await a.states.clear();
    await a.snapshots.clear();

    final freshDestination = MemoryCloudBackend();
    final afterSwitch = CloudSyncEngine(
      db: a.db,
      backend: freshDestination,
      snapshots: a.snapshots,
      stateStore: a.states,
      clock: () => DateTime.utc(2026, 11, 14, 11),
    );
    expect(await afterSwitch.syncNow(), isTrue);

    final document = CloudSyncState.fromJson(
      jsonDecode(freshDestination.body!) as Map<String, dynamic>,
    );
    expect(document.records.keys, [syncId]);
    expect(document.records[syncId]!.record.payload['summary'], 'buy milk');
  });

  test('a source without a registered client ID cannot be selected', () async {
    final prefs = await SharedPreferences.getInstance();
    final switcher = CloudSourceSwitch(
      sources: PrefsCloudSyncSourceStore(prefs),
      stateStore: MemoryCloudStateStore(),
      cursorStore: MemoryCursorStore(),
      snapshots: MemorySnapshotStore(),
    );
    expect(
      () => switcher.switchTo(CloudSyncSource.quark),
      throwsArgumentError,
    );
  });
}
