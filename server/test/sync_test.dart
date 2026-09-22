import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

Future<Response> _request(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
}) async {
  return await handler(
    Request(
      method,
      _uri(path),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
}

Future<Map<String, dynamic>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

Future<Map<String, String>> _register(AppServer app, String email) async {
  final response = await _request(app.handler, 'POST', '/auth/register', body: {
    'email': email,
    'password': 'password123',
  });
  expect(response.statusCode, 201, reason: 'register must succeed');
  final body = await _json(response);
  return {
    'userId': body['userId'] as String,
    'token': body['accessToken'] as String,
  };
}

Map<String, Object?> _upsertOp({
  required String opId,
  required String recordId,
  Map<String, Object?>? fields,
  int? baseRev,
  String type = 'todo',
}) => {
      'opId': opId,
      'op': 'upsert',
      'recordId': recordId,
      'type': type,
      'fields': fields,
      'baseRev': baseRev,
    };

Map<String, Object?> _deleteOp({
  required String opId,
  required String recordId,
  String type = 'todo',
}) => {
      'opId': opId,
      'op': 'delete',
      'recordId': recordId,
      'type': type,
    };

Future<Map<String, dynamic>> _push(
  AppServer app,
  String token, {
  required List<Map<String, Object?>> ops,
  int? cursor,
  String deviceId = 'device-1',
}) async {
  final response = await _request(app.handler, 'POST', '/sync/push', token: token, body: {
    'deviceId': deviceId,
    'ops': ops,
    if (cursor != null) 'cursor': cursor,
  });
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _pull(
  AppServer app,
  String token, {
  int? cursor,
  int? limit,
}) async {
  final query = <String, String>{
    if (cursor != null) 'cursor': '$cursor',
    if (limit != null) 'limit': '$limit',
  };
  final path = query.isEmpty
      ? '/sync/pull'
      : '/sync/pull?${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';
  final response = await _request(app.handler, 'GET', path, token: token);
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

List<dynamic> _results(Map<String, dynamic> push) =>
    push['results'] as List<dynamic>;

Future<void> _awaitNextSecond(DateTime after) async {
  final target = after.toUtc().add(const Duration(seconds: 1));
  while (DateTime.now().toUtc().isBefore(target)) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

String _errorCode(Map<String, dynamic> body) {
  final error = body['error'] as Map<String, dynamic>;
  return error['code'] as String;
}

void main() {
  late AppServer app;

  setUp(() {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
  });

  tearDown(() async {
    await app.close();
  });

  test(
      'push replay with same opId returns stored result verbatim, no state change',
      () async {
    final account = await _register(app, 'idem@example.com');
    final token = account['token']!;
    final userId = account['userId']!;
    final seqCalls = <(String, int)>[];
    app.onSeqAdvanced = (id, seq) => seqCalls.add((id, seq));

    final op = _upsertOp(
      opId: 'op-idem-1',
      recordId: 'rec-1',
      fields: {'title': 'hello'},
    );
    final first = await _push(app, token, ops: [op]);
    final firstResult = _results(first).single as Map<String, dynamic>;
    expect(firstResult['status'], 'applied');
    expect(first['cursor'], 1);
    expect(seqCalls, [(userId, 1)]);

    final second = await _push(app, token, ops: [op]);
    final secondResult = _results(second).single as Map<String, dynamic>;
    // Original stored status is replayed as-is; the client retry sees the
    // exact same answer it got the first time.
    expect(secondResult['status'], 'applied');
    expect(secondResult, firstResult);
    expect(second['cursor'], 1);

    final pull = await _pull(app, token, cursor: 0);
    final changes = pull['changes'] as List<dynamic>;
    expect(changes, hasLength(1));
    final record = changes.single as Map<String, dynamic>;
    expect(record['rev'], 1);
    expect(record['payload'], {'title': 'hello'});

    // No mutation happened on replay, so the SSE seam must not fire again.
    expect(seqCalls, [(userId, 1)]);
    final storedOps = await app.db.select(app.db.syncOps).get();
    expect(storedOps, hasLength(1));
  });

  test(
      'stale baseRev upsert merges fields: set fields win, unset fields kept',
      () async {
    final token = (await _register(app, 'merge@example.com'))['token']!;

    final create = await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-m-create',
        recordId: 'rec-m',
        fields: {'title': 'base title', 'start': 'base start'},
      ),
    ]);
    expect(_results(create).single['status'], 'applied');

    // Device A bumps rev to 2 with a title change.
    final deviceA = await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-m-a',
        recordId: 'rec-m',
        fields: {'title': 'from A'},
        baseRev: 1,
      ),
    ]);
    final aResult = _results(deviceA).single as Map<String, dynamic>;
    expect(aResult['status'], 'applied');
    expect((aResult['serverRecord'] as Map<String, dynamic>)['rev'], 2);

    // Device B still holds baseRev 1 and only touches start — stale baseRev
    // must not clobber A's title (field-level LWW, arrival order wins).
    final deviceB = await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-m-b',
        recordId: 'rec-m',
        fields: {'start': 'from B'},
        baseRev: 1,
      ),
    ]);
    final bResult = _results(deviceB).single as Map<String, dynamic>;
    expect(bResult['status'], 'applied');
    final merged = bResult['serverRecord'] as Map<String, dynamic>;
    expect(merged['rev'], 3);
    expect(merged['payload'], {'title': 'from A', 'start': 'from B'});

    final pull = await _pull(app, token, cursor: 0);
    final changes = pull['changes'] as List<dynamic>;
    expect(changes, hasLength(1));
    expect(
      (changes.single as Map<String, dynamic>)['payload'],
      {'title': 'from A', 'start': 'from B'},
    );
  });

  test(
      'delete vs update: delete wins by arrival, later upsert resurrects tombstone',
      () async {
    final token = (await _register(app, 'race@example.com'))['token']!;

    await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-r-create',
        recordId: 'rec-r',
        fields: {'title': 't0', 'start': 's0'},
      ),
    ]);
    await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-r-update',
        recordId: 'rec-r',
        fields: {'title': 't1'},
        baseRev: 1,
      ),
    ]);

    final deleted = await _push(app, token, ops: [
      _deleteOp(opId: 'op-r-delete', recordId: 'rec-r'),
    ]);
    final deleteResult = _results(deleted).single as Map<String, dynamic>;
    expect(deleteResult['status'], 'applied');
    final tombstone = deleteResult['serverRecord'] as Map<String, dynamic>;
    expect(tombstone['deleted'], true);
    expect(tombstone['rev'], 3);

    // Arrival order rule: an update whose server receive time falls in a
    // later second than the tombstone applies (server clock only).
    await _awaitNextSecond(DateTime.parse(tombstone['serverTs'] as String));
    final resurrect = await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-r-resurrect',
        recordId: 'rec-r',
        fields: {'title': 't2', 'start': 's1'},
        baseRev: 2,
      ),
    ]);
    final resurrectResult = _results(resurrect).single as Map<String, dynamic>;
    expect(resurrectResult['status'], 'applied');
    final revived = resurrectResult['serverRecord'] as Map<String, dynamic>;
    expect(revived['deleted'], false);
    expect(revived['rev'], 4);
    expect(revived['payload'], {'title': 't2', 'start': 's1'});

    final pull = await _pull(app, token, cursor: 0);
    final changes = pull['changes'] as List<dynamic>;
    expect(changes, hasLength(1));
    expect((changes.single as Map<String, dynamic>)['deleted'], false);
  });

  test('partial failure: middle op rejected, neighbors applied and persisted',
      () async {
    final account = await _register(app, 'partial@example.com');
    final token = account['token']!;
    final seqCalls = <(String, int)>[];
    app.onSeqAdvanced = (id, seq) => seqCalls.add((id, seq));

    final ops = [
      _upsertOp(opId: 'op-p-1', recordId: 'rec-p1', fields: {'title': 'one'}),
      // Invalid: upsert carries no fields to apply.
      _upsertOp(opId: 'op-p-2', recordId: 'rec-p2', fields: null),
      _upsertOp(opId: 'op-p-3', recordId: 'rec-p3', fields: {'title': 'three'}),
    ];
    final push = await _push(app, token, ops: ops);
    final results = _results(push);
    expect(results, hasLength(3));
    expect(results[0]['opId'], 'op-p-1');
    expect(results[0]['status'], 'applied');
    expect(results[1]['opId'], 'op-p-2');
    expect(results[1]['status'], 'rejected');
    expect(results[1]['code'], errValidation);
    expect(results[2]['opId'], 'op-p-3');
    expect(results[2]['status'], 'applied');
    expect(push['cursor'], 2);

    final pull = await _pull(app, token, cursor: 0);
    final changes = pull['changes'] as List<dynamic>;
    expect(changes, hasLength(2));
    final ids = changes.map((c) => (c as Map<String, dynamic>)['id']).toSet();
    expect(ids, {'rec-p1', 'rec-p3'});

    // Replaying the whole batch keeps every stored verdict and mutates nothing.
    final seqCallsAfterFirst = [...seqCalls];
    final replay = await _push(app, token, ops: ops, cursor: 2);
    final replayResults = _results(replay);
    expect(replayResults[0]['status'], 'applied');
    expect(replayResults[1]['status'], 'rejected');
    expect(replayResults[2]['status'], 'applied');
    expect(replay['cursor'], 2);
    expect(seqCalls, seqCallsAfterFirst);
  });

  test('push piggyback carries other-device changes and reports current cursor',
      () async {
    final token = (await _register(app, 'piggy@example.com'))['token']!;

    final first = await _push(app, token, ops: [
      _upsertOp(opId: 'op-pig-1', recordId: 'rec-pig-1', fields: {'title': '1'}),
    ]);
    expect(first['cursor'], 1);

    // Another device writes while device-1 still holds cursor 1.
    await _push(
      app,
      token,
      deviceId: 'device-2',
      ops: [
        _upsertOp(
          opId: 'op-pig-2',
          recordId: 'rec-pig-2',
          fields: {'title': '2'},
        ),
      ],
    );

    final push = await _push(
      app,
      token,
      cursor: 1,
      ops: [
        _upsertOp(
          opId: 'op-pig-3',
          recordId: 'rec-pig-3',
          fields: {'title': '3'},
        ),
      ],
    );
    final piggyback = push['piggyback'] as List<dynamic>;
    final piggyIds = piggyback
        .map((r) => (r as Map<String, dynamic>)['id'] as String)
        .toSet();
    expect(piggyIds, {'rec-pig-2', 'rec-pig-3'});
    expect(push['cursor'], 3);

    // Piggyback is capped at 100 changes while cursor still jumps to head.
    final bulk = List.generate(
      100,
      (i) => _upsertOp(
        opId: 'op-bulk-$i',
        recordId: 'rec-bulk-$i',
        fields: {'title': 'b$i'},
      ),
    );
    await _push(app, token, ops: bulk);
    final capped = await _push(
      app,
      token,
      cursor: 0,
      ops: [
        _upsertOp(opId: 'op-tail', recordId: 'rec-tail', fields: {'title': 'x'}),
      ],
    );
    expect((capped['piggyback'] as List<dynamic>), hasLength(100));
    expect(capped['cursor'], 104);
  });

  test('pull paginates with hasMore and advances cursor', () async {
    final token = (await _register(app, 'page@example.com'))['token']!;

    final ops = List.generate(
      5,
      (i) => _upsertOp(
        opId: 'op-page-$i',
        recordId: 'rec-page-$i',
        fields: {'title': 'p$i'},
      ),
    );
    await _push(app, token, ops: ops);

    final seen = <String>[];
    var cursor = 0;
    var pages = 0;
    while (true) {
      final page = await _pull(app, token, cursor: cursor, limit: 2);
      final changes = page['changes'] as List<dynamic>;
      final hasMore = page['hasMore'] as bool;
      expect(page['nextCursor'], isA<int>());
      if (changes.isEmpty) {
        expect(hasMore, isFalse);
        break;
      }
      final seqs =
          changes.map((c) => (c as Map<String, dynamic>)['id'] as String);
      seen.addAll(seqs);
      cursor = page['nextCursor'] as int;
      pages++;
      if (!hasMore) {
        break;
      }
      expect(pages, lessThan(10), reason: 'pagination must terminate');
    }
    expect(pages, 3);
    expect(seen, hasLength(5));
    expect(seen.toSet(), hasLength(5));

    final empty = await _pull(app, token, cursor: cursor, limit: 2);
    expect(empty['changes'], isEmpty);
    expect(empty['hasMore'], isFalse);
    expect(empty['nextCursor'], cursor);

    final bad = await _request(
      app.handler,
      'GET',
      '/sync/pull?cursor=0&limit=abc',
      token: token,
    );
    expect(bad.statusCode, 400);
    expect(_errorCode(await _json(bad)), errValidation);
  });

  test('tombstone propagates through pull', () async {
    final token = (await _register(app, 'tomb@example.com'))['token']!;

    await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-t-create',
        recordId: 'rec-t',
        fields: {'title': 'keep me'},
      ),
    ]);
    final before = await _pull(app, token, cursor: 0);
    final live = (before['changes'] as List<dynamic>).single as Map<String, dynamic>;
    expect(live['deleted'], false);
    expect(live['rev'], 1);
    final cursorBeforeDelete = before['nextCursor'] as int;

    await _push(app, token, ops: [
      _deleteOp(opId: 'op-t-delete', recordId: 'rec-t'),
    ]);

    final after = await _pull(app, token, cursor: cursorBeforeDelete);
    final changes = after['changes'] as List<dynamic>;
    expect(changes, hasLength(1));
    final tombstone = changes.single as Map<String, dynamic>;
    expect(tombstone['deleted'], true);
    expect(tombstone['rev'], 2);
    expect(tombstone['payload'], {'title': 'keep me'});
    expect(after['hasMore'], isFalse);
  });

  test('same-second tie-break: lower incoming opId loses to tombstone',
      () async {
    final token = (await _register(app, 'tie@example.com'))['token']!;

    // The second boundary can fall between the delete write and the upsert
    // receive; retry with fresh records until both land in the same second.
    // Crossing chance per attempt is ~1% of a 10ms gap, so 8 attempts is
    // effectively certain to pin the tie-break branch at least once.
    var pinned = false;
    for (var attempt = 0; attempt < 8 && !pinned; attempt++) {
      final recordId = 'rec-tie-$attempt';
      await _push(app, token, ops: [
        _upsertOp(
          opId: 'op-tie-create-$attempt',
          recordId: recordId,
          fields: {'title': 'tie'},
        ),
      ]);
      final deleted = await _push(app, token, ops: [
        _deleteOp(opId: 'zzzzzzzzzzzzzzzzzz-$attempt', recordId: recordId),
      ]);
      final tombstone =
          _results(deleted).single['serverRecord'] as Map<String, dynamic>;
      expect(tombstone['deleted'], true);

      final upserted = await _push(app, token, ops: [
        _upsertOp(
          opId: 'aaaaaaaaaaaaaaaaaa-$attempt',
          recordId: recordId,
          fields: {'title': 'late'},
          baseRev: 2,
        ),
      ]);
      final result = _results(upserted).single as Map<String, dynamic>;
      if (result['status'] == 'conflict') {
        final returned = result['serverRecord'] as Map<String, dynamic>;
        expect(returned['deleted'], true);
        expect(returned['rev'], tombstone['rev']);
        expect(result['code'], errConflict);
        pinned = true;
      } else {
        // Applied only means the upsert landed in a later second.
        expect(result['status'], 'applied');
      }
    }
    expect(pinned, isTrue,
        reason: 'never landed delete+upsert in the same second');

    final pull = await _pull(app, token, cursor: 0);
    final stillDeleted = (pull['changes'] as List<dynamic>)
        .where((c) => (c as Map<String, dynamic>)['deleted'] == true);
    expect(stillDeleted, isNotEmpty);
  });

  group('lww decideTombstoneVsUpsert', () {
    final sameSecond = DateTime.utc(2026, 9, 23, 10, 0, 0);

    test('same second: higher incoming opId wins', () {
      expect(
        decideTombstoneVsUpsert(
          recordServerTs: sameSecond,
          opTs: sameSecond,
          recordLastOpId: 'op-del',
          incomingOpId: 'op-upsert',
        ),
        TombstoneUpsertDecision.apply,
      );
    });

    test('same second: lower incoming opId loses', () {
      expect(
        decideTombstoneVsUpsert(
          recordServerTs: sameSecond,
          opTs: sameSecond,
          recordLastOpId: 'op-upsert',
          incomingOpId: 'op-del',
        ),
        TombstoneUpsertDecision.conflict,
      );
    });

    test('same second: equal opId keeps the tombstone', () {
      expect(
        decideTombstoneVsUpsert(
          recordServerTs: sameSecond,
          opTs: sameSecond,
          recordLastOpId: 'same',
          incomingOpId: 'same',
        ),
        TombstoneUpsertDecision.conflict,
      );
    });

    test('tombstone in a later second than the op always conflicts', () {
      expect(
        decideTombstoneVsUpsert(
          recordServerTs: sameSecond,
          opTs: sameSecond.subtract(const Duration(seconds: 1)),
          recordLastOpId: 'a',
          incomingOpId: 'z',
        ),
        TombstoneUpsertDecision.conflict,
      );
    });

    test('tombstone in an earlier second than the op always applies', () {
      expect(
        decideTombstoneVsUpsert(
          recordServerTs: sameSecond,
          opTs: sameSecond.add(const Duration(seconds: 1)),
          recordLastOpId: 'z',
          incomingOpId: 'a',
        ),
        TombstoneUpsertDecision.apply,
      );
    });
  });

  test('upsert for unknown record with positive baseRev is rejected', () async {
    final token = (await _register(app, 'unknown@example.com'))['token']!;

    final push = await _push(app, token, ops: [
      _upsertOp(
        opId: 'op-ghost',
        recordId: 'rec-ghost',
        fields: {'title': 'ghost'},
        baseRev: 5,
      ),
    ]);
    final result = _results(push).single as Map<String, dynamic>;
    expect(result['status'], 'rejected');
    expect(result['code'], errValidation);
    expect(push['cursor'], 0);

    final pull = await _pull(app, token, cursor: 0);
    expect(pull['changes'], isEmpty);
  });

  test('sync routes are auth-gated and reject malformed envelope', () async {
    final anonymousPush = await _request(app.handler, 'POST', '/sync/push', body: {
      'deviceId': 'device-1',
      'ops': <Object>[],
    });
    expect(anonymousPush.statusCode, 401);
    expect(_errorCode(await _json(anonymousPush)), errUnauthorized);

    final anonymousPull = await _request(app.handler, 'GET', '/sync/pull');
    expect(anonymousPull.statusCode, 401);
    expect(_errorCode(await _json(anonymousPull)), errUnauthorized);

    final account = await _register(app, 'envelope@example.com');
    final bad = await _request(
      app.handler,
      'POST',
      '/sync/push',
      token: account['token'],
      body: {'ops': <Object>[]},
    );
    expect(bad.statusCode, 400);
    expect(_errorCode(await _json(bad)), errValidation);
  });
}
