import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/sync/sync_api_client.dart';
import 'package:dayspark/domain/sync/sync_config.dart';
import 'package:dayspark_contracts/dayspark_contracts.dart';

class MemoryCursorStore implements SyncCursorStore {
  int? value;

  MemoryCursorStore([this.value]);

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int cursor) async {
    value = cursor;
  }
}

class MemoryTokenStore implements SyncTokenStore {
  MemoryTokenStore({this.access, this.refresh});

  String? access;
  String? refresh;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

/// Scriptable SyncApiClient — the engine's fake server. Push and pull
/// responses default to benign no-ops; tests override via [onPush]/[onPull].
class FakeSyncApiClient implements SyncApiClient {
  final List<PushRequest> pushCalls = [];
  final List<int> pullCalls = [];
  PushResponse Function(PushRequest request)? onPush;
  PullResponse Function(int cursor)? onPull;
  final StreamController<int> cursorController =
      StreamController<int>.broadcast();

  @override
  Future<PushResponse> push(PushRequest request) async {
    pushCalls.add(request);
    final handler = onPush;
    if (handler != null) return handler(request);
    return PushResponse(
      results: [
        for (final op in request.ops)
          OpResult(opId: op.opId, status: OpStatus.applied),
      ],
      piggyback: const [],
      cursor: request.cursor ?? 0,
    );
  }

  @override
  Future<PullResponse> pull(int cursor, {int limit = 100}) async {
    pullCalls.add(cursor);
    final handler = onPull;
    if (handler != null) return handler(cursor);
    return PullResponse(
      changes: const [],
      nextCursor: cursor,
      hasMore: false,
    );
  }

  @override
  Stream<int> openCursorStream() => cursorController.stream;
}

class FakeTransport implements SyncTransport {
  int pushCalls = 0;
  int refreshCalls = 0;
  final List<String> authorizationHeaders = [];

  /// When true every /sync/push response is 401 (even after refresh).
  bool alwaysPush401 = false;

  @override
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    if (path.startsWith('/auth/refresh')) {
      refreshCalls++;
      final decoded = body is String
          ? jsonDecode(body) as Map<String, dynamic>
          : body! as Map<String, dynamic>;
      if (decoded['refreshToken'] == 'refresh-1') {
        return SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'tokenType': 'Bearer',
            'expiresIn': 900,
          }),
        );
      }
      return SyncHttpResponse(
        statusCode: 401,
        body: jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'invalid refresh token'},
        }),
      );
    }
    if (path.startsWith('/sync/push')) {
      pushCalls++;
      final auth = headers['authorization'];
      authorizationHeaders.add(auth ?? '');
      if (!alwaysPush401 && auth == 'Bearer access-2') {
        return SyncHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'results': <Object>[],
            'piggyback': <Object>[],
            'cursor': 0,
          }),
        );
      }
      return SyncHttpResponse(
        statusCode: 401,
        body: jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'expired'},
        }),
      );
    }
    throw StateError('unexpected path: $path');
  }

  @override
  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  }) async {
    throw StateError('SSE not under test here');
  }
}

PushResponse appliedPush(PushRequest request, {SyncRecord? serverRecord}) {
  return PushResponse(
    results: [
      for (final op in request.ops)
        OpResult(
          opId: op.opId,
          status: OpStatus.applied,
          serverRecord: serverRecord,
        ),
    ],
    piggyback: const [],
    cursor: request.cursor ?? 0,
  );
}

Future<void> waitUntil(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(reason ?? 'condition not met in time');
}
