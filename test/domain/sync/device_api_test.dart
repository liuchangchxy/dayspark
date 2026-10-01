// 设备注册/列表的客户端契约。
//
// 这一层最容易悄悄坏：请求发出去了但头没带、响应形状改了但解析没跟上——
// 两种都不会在编译期报错。所以断言落在"发出去的请求长什么样"和
// "解析出来的对象是什么"上。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/sync/sync_api_client.dart';

import 'sync_test_support.dart';

class _RecordingTransport implements SyncTransport {
  _RecordingTransport(this.handler);

  final SyncHttpResponse Function(String method, String path, Object? body)
      handler;
  final List<({String method, String path, Map<String, String> headers})> calls =
      [];
  final List<Object?> bodies = [];

  @override
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    calls.add((method: method, path: path, headers: headers));
    bodies.add(body);
    return handler(method, path, body);
  }

  @override
  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  }) async =>
      const Stream<List<int>>.empty();
}

void main() {
  late MemoryTokenStore tokens;

  setUp(() {
    tokens = MemoryTokenStore(access: 'access-1', refresh: 'refresh-1');
  });

  AuthSyncApiClient clientFor(
    SyncHttpResponse Function(String, String, Object?) handler, {
    String deviceId = 'dev-1',
  }) =>
      AuthSyncApiClient(
        transport: _RecordingTransport(handler),
        tokens: tokens,
        deviceId: deviceId,
      );

  group('x-device-id 头', () {
    test('deviceId 非空时随每个认证请求发出', () async {
      final transport = _RecordingTransport(
        (_, __, ___) => SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({'devices': <Object?>[]}),
        ),
      );
      final client = AuthSyncApiClient(
        transport: transport,
        tokens: tokens,
        deviceId: 'dev-1',
      );

      await client.fetchDevices();

      expect(transport.calls.single.headers['x-device-id'], 'dev-1');
    });

    test('deviceId 为空时干脆不发这个头（而不是发空串）', () async {
      final transport = _RecordingTransport(
        (_, __, ___) => SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({'devices': <Object?>[]}),
        ),
      );
      final client = AuthSyncApiClient(
        transport: transport,
        tokens: tokens,
        deviceId: '',
      );

      await client.fetchDevices();

      expect(transport.calls.single.headers.containsKey('x-device-id'), isFalse);
    });
  });

  group('registerDevice', () {
    test('POST /devices/register，body 带 deviceId 与 name', () async {
      final transport = _RecordingTransport(
        (_, __, ___) => SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'deviceId': 'dev-1',
            'name': 'Android',
            'lastSeen': '2026-10-01T10:00:00.000Z',
          }),
        ),
      );
      final client = AuthSyncApiClient(
        transport: transport,
        tokens: tokens,
        deviceId: 'dev-1',
      );

      final dto = await client.registerDevice(
        deviceId: 'dev-1',
        name: 'Android',
      );

      expect(transport.calls.single.method, 'POST');
      expect(transport.calls.single.path, '/devices/register');
      final sent = jsonDecode(transport.bodies.single! as String) as Map;
      expect(sent['deviceId'], 'dev-1');
      expect(sent['name'], 'Android');
      expect(dto.deviceId, 'dev-1');
      expect(dto.lastSeen, DateTime.utc(2026, 10, 1, 10));
    });

    test('name 为空时不塞进 body（服务端据此保留原名）', () async {
      final transport = _RecordingTransport(
        (_, __, ___) => SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'deviceId': 'dev-1',
            'name': null,
            'lastSeen': '2026-10-01T10:00:00.000Z',
          }),
        ),
      );
      final client = AuthSyncApiClient(
        transport: transport,
        tokens: tokens,
        deviceId: 'dev-1',
      );

      await client.registerDevice(deviceId: 'dev-1');

      final sent = jsonDecode(transport.bodies.single! as String) as Map;
      expect(sent.containsKey('name'), isFalse);
    });

    test('非 200 抛 SyncApiException 并带上服务端 code', () async {
      final client = clientFor(
        (_, __, ___) => SyncHttpResponse(
          statusCode: 409,
          body: jsonEncode({
            'error': {'code': 'conflict', 'message': 'bound elsewhere'},
          }),
        ),
      );

      await expectLater(
        client.registerDevice(deviceId: 'dev-1'),
        throwsA(
          isA<SyncApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.code, 'code', 'conflict'),
        ),
      );
    });
  });

  group('fetchDevices', () {
    test('GET /devices 并解析列表', () async {
      final client = clientFor(
        (_, __, ___) => SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'devices': [
              {
                'deviceId': 'a',
                'name': 'Pixel',
                'lastSeen': '2026-10-01T09:00:00.000Z',
              },
              {
                'deviceId': 'b',
                'name': null,
                'lastSeen': '2026-09-30T09:00:00.000Z',
              },
            ],
          }),
        ),
      );

      final devices = await client.fetchDevices();

      expect(devices.map((d) => d.deviceId), ['a', 'b']);
      expect(devices.first.name, 'Pixel');
      expect(devices.last.name, isNull);
      expect(devices.first.lastSeen.isUtc, isTrue);
    });

    test('空列表是合法状态（新账号还没有设备）', () async {
      final client = clientFor(
        (_, __, ___) =>
            SyncHttpResponse(statusCode: 200, body: jsonEncode({'devices': []})),
      );
      expect(await client.fetchDevices(), isEmpty);
    });
  });
}
