import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

Future<Response> _request(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
  String? deviceId,
}) async {
  return await handler(
    Request(
      method,
      _uri(path),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
        if (deviceId != null) 'x-device-id': deviceId,
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

Future<String> _register(AppServer app, String email) async {
  final response = await _request(
    app.handler,
    'POST',
    '/auth/register',
    body: {'email': email, 'password': 'password123'},
  );
  expect(response.statusCode, 201);
  return (await _json(response))['accessToken'] as String;
}

Future<String> _userId(AppServer app, String email) async {
  final row = await (app.db.select(app.db.users)
        ..where((t) => t.email.equals(email)))
      .getSingle();
  return row.id;
}

void main() {
  late AppServer app;

  setUp(() {
    app = AppServer(
      const Config(dbPath: ':memory:', port: 0, jwtSecret: 'test-secret'),
    );
  });

  tearDown(() async => app.close());

  group('POST /devices/register', () {
    test('首次注册建行，lastSeen 有值', () async {
      final token = await _register(app, 'a@example.com');
      final response = await _request(
        app.handler,
        'POST',
        '/devices/register',
        token: token,
        body: {'deviceId': 'dev-1', 'name': 'Pixel'},
      );
      expect(response.statusCode, 200);
      expect((await _json(response))['deviceId'], 'dev-1');

      final rows = await app.db.select(app.db.devices).get();
      expect(rows, hasLength(1));
      expect(rows.single.deviceId, 'dev-1');
      expect(rows.single.name, 'Pixel');
    });

    test('重复注册是幂等的：不建第二行', () async {
      final token = await _register(app, 'a@example.com');
      for (var i = 0; i < 3; i++) {
        final response = await _request(
          app.handler,
          'POST',
          '/devices/register',
          token: token,
          body: {'deviceId': 'dev-1', 'name': 'Pixel'},
        );
        expect(response.statusCode, 200);
      }
      expect(await app.db.select(app.db.devices).get(), hasLength(1));
    });

    test('二次注册不带 name 时保留原名（冷启动重复上报不得抹掉用户设的名字）', () async {
      final token = await _register(app, 'a@example.com');
      await _request(
        app.handler,
        'POST',
        '/devices/register',
        token: token,
        body: {'deviceId': 'dev-1', 'name': '我的手机'},
      );
      await _request(
        app.handler,
        'POST',
        '/devices/register',
        token: token,
        body: {'deviceId': 'dev-1'},
      );
      final rows = await app.db.select(app.db.devices).get();
      expect(rows.single.name, '我的手机');
    });

    test('同一 deviceId 被另一账号注册 → 409，且不改归属', () async {
      final tokenA = await _register(app, 'a@example.com');
      final tokenB = await _register(app, 'b@example.com');
      await _request(
        app.handler,
        'POST',
        '/devices/register',
        token: tokenA,
        body: {'deviceId': 'dev-1'},
      );

      final response = await _request(
        app.handler,
        'POST',
        '/devices/register',
        token: tokenB,
        body: {'deviceId': 'dev-1'},
      );
      expect(response.statusCode, 409);
      expect((await _json(response))['error']['code'], errConflict);

      final rows = await app.db.select(app.db.devices).get();
      expect(rows, hasLength(1), reason: '不得为第二个账号再建一行');
      expect(
        rows.single.userId,
        await _userId(app, 'a@example.com'),
        reason: '归属必须仍是原账号',
      );
    });

    test('缺 deviceId / 空串 → 400', () async {
      final token = await _register(app, 'a@example.com');
      for (final body in <Map<String, Object?>>[{}, {'deviceId': ''}]) {
        final response = await _request(
          app.handler,
          'POST',
          '/devices/register',
          token: token,
          body: body,
        );
        expect(response.statusCode, 400, reason: 'body=$body');
      }
    });

    test('未认证 → 401', () async {
      final response = await _request(
        app.handler,
        'POST',
        '/devices/register',
        body: {'deviceId': 'dev-1'},
      );
      expect(response.statusCode, 401);
    });
  });

  group('GET /devices', () {
    test('只列本账号的设备，按 lastSeen 倒序', () async {
      final tokenA = await _register(app, 'a@example.com');
      final tokenB = await _register(app, 'b@example.com');
      await _request(app.handler, 'POST', '/devices/register',
          token: tokenB, body: {'deviceId': 'other'});
      await _request(app.handler, 'POST', '/devices/register',
          token: tokenA, body: {'deviceId': 'old'});
      await _request(app.handler, 'POST', '/devices/register',
          token: tokenA, body: {'deviceId': 'new'});
      // drift 的 DateTime 落库精度是整秒，两次注册必然落在同一秒；
      // 要让"按 lastSeen 倒序"可判定，只能手工把 old 拨到过去。
      await (app.db.update(app.db.devices)
            ..where((t) => t.deviceId.equals('old')))
          .write(DevicesCompanion(lastSeen: Value(DateTime.utc(2020))));

      final response = await _request(app.handler, 'GET', '/devices', token: tokenA);
      expect(response.statusCode, 200);
      final devices = (await _json(response))['devices'] as List;
      expect(devices.map((d) => d['deviceId']), ['new', 'old']);
    });

    test('未认证 → 401', () async {
      expect((await _request(app.handler, 'GET', '/devices')).statusCode, 401);
    });
  });

  group('/sync/push 的设备归属', () {
    Map<String, Object?> op(String id) => {
          'opId': 'op-$id',
          'op': 'upsert',
          'recordId': 'rec-$id',
          'type': 'todo',
          'fields': {'summary': 'x'},
        };

    test('deviceId 落到 SyncOps：优先取 x-device-id 头', () async {
      final token = await _register(app, 'a@example.com');
      final response = await _request(
        app.handler,
        'POST',
        '/sync/push',
        token: token,
        deviceId: 'from-header',
        body: {'deviceId': 'from-body', 'ops': [op('1')]},
      );
      expect(response.statusCode, 200);
      final rows = await app.db.select(app.db.syncOps).get();
      expect(rows.single.deviceId, 'from-header');
    });

    test('无头时回退到 body 的 deviceId（客户端一直这么发）', () async {
      final token = await _register(app, 'a@example.com');
      await _request(
        app.handler,
        'POST',
        '/sync/push',
        token: token,
        body: {'deviceId': 'from-body', 'ops': [op('2')]},
      );
      final rows = await app.db.select(app.db.syncOps).get();
      expect(rows.single.deviceId, 'from-body');
    });

    test('push 会 touch 已注册设备的 lastSeen', () async {
      final token = await _register(app, 'a@example.com');
      await _request(app.handler, 'POST', '/devices/register',
          token: token, body: {'deviceId': 'dev-1'});
      // 手工把 lastSeen 拨回过去，才能观察 touch 是否真的发生。
      await (app.db.update(app.db.devices)
            ..where((t) => t.deviceId.equals('dev-1')))
          .write(DevicesCompanion(lastSeen: Value(DateTime.utc(2020))));

      await _request(
        app.handler,
        'POST',
        '/sync/push',
        token: token,
        deviceId: 'dev-1',
        body: {'deviceId': 'dev-1', 'ops': [op('3')]},
      );

      final row = (await app.db.select(app.db.devices).get()).single;
      expect(row.lastSeen.isAfter(DateTime.utc(2020)), isTrue);
    });

    test('未注册设备也能 push（注册不是同步的前置条件）', () async {
      final token = await _register(app, 'a@example.com');
      final response = await _request(
        app.handler,
        'POST',
        '/sync/push',
        token: token,
        deviceId: 'never-registered',
        body: {'deviceId': 'never-registered', 'ops': [op('4')]},
      );
      expect(response.statusCode, 200);
      expect(await app.db.select(app.db.devices).get(), isEmpty);
    });
  });
}
