import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dio/dio.dart';

import 'sync_config.dart';

class SyncApiException implements Exception {
  SyncApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'SyncApiException($statusCode, $code, $message)';
}

class SyncHttpResponse {
  const SyncHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// Transport-level failure (non-2xx while opening a stream, or status 0
/// for connection-level errors where no response exists).
class SyncTransportException implements Exception {
  const SyncTransportException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'SyncTransportException($statusCode)';
}

/// Raw HTTP seam: the real implementation uses dio, tests substitute a
/// fake without touching the network.
abstract class SyncTransport {
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  });

  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  });
}

class DioSyncTransport implements SyncTransport {
  DioSyncTransport({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  @override
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final options = Options(headers: {...headers}, responseType: ResponseType.plain);
    try {
      final Response<dynamic> response;
      if (method == 'GET') {
        response = await _dio.get<dynamic>(path, options: options);
      } else {
        response = await _dio.post<dynamic>(path, data: body, options: options);
      }
      return SyncHttpResponse(
        statusCode: response.statusCode ?? 0,
        body: response.data is String ? response.data! as String : '',
      );
    } on DioException catch (e) {
      final resp = e.response;
      if (resp == null) rethrow;
      final data = resp.data;
      return SyncHttpResponse(
        statusCode: resp.statusCode ?? 0,
        body: data is String ? data : '',
      );
    }
  }

  @override
  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  }) async {
    try {
      final response = await _dio.get<ResponseBody>(
        path,
        options: Options(
          headers: {...headers},
          responseType: ResponseType.stream,
          receiveTimeout: null,
        ),
      );
      final body = response.data;
      if (body == null) throw const SyncTransportException(0);
      return body.stream;
    } on DioException catch (e) {
      throw SyncTransportException(e.response?.statusCode ?? 0);
    }
  }
}

/// The seam the engine codes against: push / pull / SSE cursor signals.
abstract class SyncApiClient {
  Future<PushResponse> push(PushRequest request);

  Future<PullResponse> pull(int cursor, {int limit});

  /// One SSE connection: emits `{"cursor":N}` signals until the server
  /// closes it or it errors (reconnection belongs to SseListener).
  Stream<int> openCursorStream();
}

/// Bearer-token auth with single-flight refresh: on 401 the original
/// request is retried exactly once after POST /auth/refresh rotates the
/// token pair (T2 contract).
class AuthSyncApiClient implements SyncApiClient {
  AuthSyncApiClient({required this.transport, required this.tokens});

  final SyncTransport transport;
  final SyncTokenStore tokens;

  Future<void>? _refreshInFlight;

  Future<Map<String, String>> _authHeaders() async {
    final access = await tokens.readAccessToken();
    return {
      if (access != null) 'authorization': 'Bearer $access',
      'content-type': 'application/json',
    };
  }

  Future<SyncHttpResponse> _send({
    required String method,
    required String path,
    Object? body,
  }) async {
    var response = await transport.send(
      method: method,
      path: path,
      headers: await _authHeaders(),
      body: body,
    );
    if (response.statusCode == 401) {
      await _refresh();
      response = await transport.send(
        method: method,
        path: path,
        headers: await _authHeaders(),
        body: body,
      );
    }
    return response;
  }

  Future<void> _refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _doRefresh().whenComplete(() => _refreshInFlight = null);
    _refreshInFlight = future;
    return future;
  }

  Future<void> _doRefresh() async {
    final refresh = await tokens.readRefreshToken();
    if (refresh == null) {
      throw SyncApiException(401, 'unauthorized', 'not authenticated');
    }
    final response = await transport.send(
      method: 'POST',
      path: '/auth/refresh',
      headers: {'content-type': 'application/json'},
      body: {'refreshToken': refresh},
    );
    if (response.statusCode != 200) throw _toException(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final access = json['accessToken'];
    final nextRefresh = json['refreshToken'];
    if (access is! String || nextRefresh is! String) {
      throw SyncApiException(500, 'validation', 'malformed refresh response');
    }
    await tokens.saveTokens(accessToken: access, refreshToken: nextRefresh);
  }

  SyncApiException _toException(SyncHttpResponse response) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          return SyncApiException(
            response.statusCode,
            '${error['code'] ?? 'error'}',
            '${error['message'] ?? ''}',
          );
        }
      }
    } on FormatException {
      // Fall through to the generic envelope below.
    }
    return SyncApiException(response.statusCode, 'error', 'HTTP ${response.statusCode}');
  }

  T _decode<T>(SyncHttpResponse response, T Function(Map<String, dynamic>) parse) {
    if (response.statusCode != 200) throw _toException(response);
    return parse(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<PushResponse> push(PushRequest request) async {
    final response = await _send(
      method: 'POST',
      path: '/sync/push',
      body: request.toJson(),
    );
    return _decode(response, PushResponse.fromJson);
  }

  @override
  Future<PullResponse> pull(int cursor, {int limit = 100}) async {
    final response = await _send(
      method: 'GET',
      path: '/sync/pull?cursor=$cursor&limit=$limit',
    );
    return _decode(response, PullResponse.fromJson);
  }

  @override
  Stream<int> openCursorStream() => _openCursorStream();

  Stream<int> _openCursorStream() async* {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final bytes = await transport.openStream(
          path: '/sync/stream',
          headers: await _authHeaders(),
        );
        final lines = utf8
            .decoder
            .bind(bytes)
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          try {
            final json = jsonDecode(line.substring(6));
            if (json is Map<String, dynamic> && json['cursor'] is int) {
              yield json['cursor'] as int;
            }
          } on FormatException {
            // Ignore malformed frames; pings and unknown events too.
          }
        }
        return;
      } on SyncTransportException catch (e) {
        if (e.statusCode == 401 && attempt == 0) {
          await _refresh();
          continue;
        }
        rethrow;
      }
    }
  }
}
