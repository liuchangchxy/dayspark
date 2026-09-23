import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';

PushOp _upsert(
  String opId, {
  required String recordId,
  Map<String, dynamic>? fields,
  int? baseRev,
  RecordType type = RecordType.todo,
}) =>
    PushOp(
      opId: opId,
      op: OpType.upsert,
      recordId: recordId,
      type: type,
      fields: fields,
      baseRev: baseRev,
    );

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
      'applyInternalOp advances seq, stores sync_ops, notifies once post-commit',
      () async {
    final notifies = <(String, int)>[];
    final result = await applyInternalOp(
      db: app.db,
      userId: 'user-w1',
      op: _upsert(
        'op-w-1',
        recordId: 'rec-w-1',
        fields: {'summary': 'hello'},
      ),
      notify: (id, seq) => notifies.add((id, seq)),
    );

    expect(result.status, OpStatus.applied);
    expect(result.serverRecord!.rev, 1);
    expect(result.serverRecord!.payload, {'summary': 'hello'});

    expect(notifies, [('user-w1', 1)]);

    final revision = await (app.db.select(app.db.revisions)
          ..where((t) => t.userId.equals('user-w1')))
        .getSingle();
    expect(revision.seq, 1);

    final row = await (app.db.select(app.db.records)
          ..where((t) => t.userId.equals('user-w1') & t.id.equals('rec-w-1')))
        .getSingle();
    expect(row.seq, 1);
    expect(row.rev, 1);
    expect(row.deleted, isFalse);

    final stored = await (app.db.select(app.db.syncOps)
          ..where((t) => t.opId.equals('op-w-1')))
        .getSingle();
    expect(stored.userId, 'user-w1');
    expect(
      jsonDecode(stored.resultJson),
      jsonDecode(jsonEncode(result.toJson())),
    );
  });

  test(
      'idempotent opId replay returns the stored result with no state change or re-notify',
      () async {
    final notifies = <(String, int)>[];
    Future<OpResult> run(PushOp op) => applyInternalOp(
          db: app.db,
          userId: 'user-w2',
          op: op,
          notify: (id, seq) => notifies.add((id, seq)),
        );

    final first = await run(_upsert(
      'op-w-idem',
      recordId: 'rec-w-idem',
      fields: {'summary': 'first'},
    ));
    expect(first.status, OpStatus.applied);
    expect(notifies, [('user-w2', 1)]);

    final replay = await run(_upsert(
      'op-w-idem',
      recordId: 'rec-w-idem',
      fields: {'summary': 'different replay payload'},
    ));
    expect(replay.status, first.status);
    expect(replay.serverRecord!.rev, first.serverRecord!.rev);
    expect(replay.serverRecord!.payload, {'summary': 'first'});
    expect(jsonDecode(jsonEncode(replay.toJson())),
        jsonDecode(jsonEncode(first.toJson())));
    expect(notifies, [('user-w2', 1)],
        reason: 'replay must not re-fire the seq-advanced seam');

    final row = await (app.db.select(app.db.records)
          ..where((t) => t.id.equals('rec-w-idem')))
        .getSingle();
    expect(row.rev, 1);
    expect(row.seq, 1);

    final opRows = await (app.db.select(app.db.syncOps)
          ..where((t) => t.opId.equals('op-w-idem')))
        .get();
    expect(opRows, hasLength(1));
  });

  test('rejected op stores its verdict without advancing seq or notifying',
      () async {
    final notifies = <(String, int)>[];
    final result = await applyInternalOp(
      db: app.db,
      userId: 'user-w3',
      op: _upsert('op-w-rej', recordId: 'rec-w-rej', fields: null),
      notify: (id, seq) => notifies.add((id, seq)),
    );

    expect(result.status, OpStatus.rejected);
    expect(result.code, errValidation);
    expect(notifies, isEmpty);

    final revision = await (app.db.select(app.db.revisions)
          ..where((t) => t.userId.equals('user-w3')))
        .getSingleOrNull();
    expect(revision, isNull, reason: 'a rejected op never touches the feed');

    final stored = await (app.db.select(app.db.syncOps)
          ..where((t) => t.opId.equals('op-w-rej')))
        .getSingle();
    expect(
      jsonDecode(stored.resultJson),
      jsonDecode(jsonEncode(result.toJson())),
    );

    final replay = await applyInternalOp(
      db: app.db,
      userId: 'user-w3',
      op: _upsert('op-w-rej', recordId: 'rec-w-rej', fields: null),
      notify: (id, seq) => notifies.add((id, seq)),
    );
    expect(replay.status, OpStatus.rejected);
    expect(notifies, isEmpty);
  });

  group('LWW merge semantics identical to HTTP push', () {
    test('internal stale-baseRev merge matches the push field-merge ruling',
        () async {
      final account = await _register(app, 'lww-internal@example.com');
      final userId = account['userId']!;
      final token = account['token']!;

      await _push(app, token, op: {
        'opId': 'op-http-create',
        'op': 'upsert',
        'recordId': 'rec-lww',
        'type': 'todo',
        'fields': {'summary': 'base', 'start': 's0'},
      });

      final result = await applyInternalOp(
        db: app.db,
        userId: userId,
        op: _upsert(
          'op-ai-merge',
          recordId: 'rec-lww',
          baseRev: 1,
          fields: {'start': 'from AI'},
        ),
        notify: (id, seq) {},
      );

      expect(result.status, OpStatus.applied);
      // Same ruling as the stale device-B case in the HTTP push suite:
      // keys the op sets win, keys it does not set keep server values.
      expect(result.serverRecord!.rev, 2);
      expect(result.serverRecord!.payload, {'summary': 'base', 'start': 'from AI'});
    });

    test('HTTP push stale-baseRev merge onto an internally created record',
        () async {
      final account = await _register(app, 'lww-http@example.com');
      final userId = account['userId']!;
      final token = account['token']!;

      final created = await applyInternalOp(
        db: app.db,
        userId: userId,
        op: _upsert(
          'op-ai-create',
          recordId: 'rec-lww-2',
          fields: {'summary': 'from AI', 'start': 'ai-start'},
        ),
        notify: (id, seq) {},
      );
      expect(created.status, OpStatus.applied);
      expect(created.serverRecord!.rev, 1);

      final push = await _push(app, token, op: {
        'opId': 'op-http-merge',
        'op': 'upsert',
        'recordId': 'rec-lww-2',
        'type': 'todo',
        'baseRev': 1,
        'fields': {'start': 'from device'},
      });
      final pushed = (push['results'] as List).single as Map<String, dynamic>;
      expect(pushed['status'], 'applied');
      final record = pushed['serverRecord'] as Map<String, dynamic>;
      expect(record['rev'], 2);
      expect(record['payload'], {'summary': 'from AI', 'start': 'from device'});
    });

    test('internal write is visible to a device pull', () async {
      final account = await _register(app, 'lww-pull@example.com');
      final token = account['token']!;

      await applyInternalOp(
        db: app.db,
        userId: account['userId']!,
        op: _upsert(
          'op-ai-visible',
          recordId: 'rec-visible',
          fields: {'summary': 'written by AI'},
        ),
        notify: (id, seq) {},
      );

      final pull = await _pull(app, token);
      final changes = pull['changes'] as List<dynamic>;
      expect(changes, hasLength(1));
      final record = changes.single as Map<String, dynamic>;
      expect(record['id'], 'rec-visible');
      expect(record['payload'], {'summary': 'written by AI'});
      expect(record['rev'], 1);
    });
  });
}

Future<Map<String, String>> _register(AppServer app, String email) async {
  final response = await _request(app.handler, 'POST', '/auth/register', body: {
    'email': email,
    'password': 'password123',
  });
  if (response.statusCode != 201) {
    fail('register must succeed: ${await response.readAsString()}');
  }
  final body = await _json(response);
  return {
    'userId': body['userId'] as String,
    'token': body['accessToken'] as String,
  };
}

Future<Map<String, dynamic>> _push(
  AppServer app,
  String token, {
  required Map<String, Object?> op,
}) async {
  final response = await _request(app.handler, 'POST', '/sync/push',
      token: token,
      body: {
        'deviceId': 'device-1',
        'ops': [op],
      });
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _pull(AppServer app, String token) async {
  final response =
      await _request(app.handler, 'GET', '/sync/pull?cursor=0', token: token);
  final text = await response.readAsString();
  expect(response.statusCode, 200, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

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
