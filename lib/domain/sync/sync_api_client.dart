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

  /// Binary request body (attachment upload). Kept off [send] because a
  /// JSON-envelope transport would base64 it and burn a third of the
  /// payload budget on top of the server's size cap.
  Future<SyncHttpResponse> sendBytes({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    required List<int> body,
  });

  Future<List<int>> fetchBytes({
    required String path,
    Map<String, String> headers = const {},
  });

  Future<Stream<List<int>>> openStream({
    required String path,
    Map<String, String> headers = const {},
  });
}

class DioSyncTransport implements SyncTransport {
  DioSyncTransport({required String baseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
            ),
          );

  final Dio _dio;

  @override
  Future<SyncHttpResponse> send({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final options = Options(
      headers: {...headers},
      responseType: ResponseType.plain,
    );
    try {
      final Response<dynamic> response;
      if (method == 'GET') {
        response = await _dio.get<dynamic>(path, options: options);
      } else if (method == 'DELETE') {
        response = await _dio.delete<dynamic>(path, options: options);
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
  Future<SyncHttpResponse> sendBytes({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    required List<int> body,
  }) async {
    final options = Options(
      headers: {...headers, 'content-type': 'application/octet-stream'},
      responseType: ResponseType.plain,
      // Uploads are user files, not control messages: the 15s connect /
      // 30s receive defaults are for sync rounds and would abort a large
      // attachment on a slow link.
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 5),
    );
    try {
      final Response<dynamic> response;
      if (method == 'GET') {
        response = await _dio.get<dynamic>(path, options: options);
      } else if (method == 'DELETE') {
        response = await _dio.delete<dynamic>(path, options: options);
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
  Future<List<int>> fetchBytes({
    required String path,
    Map<String, String> headers = const {},
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(
          headers: {...headers},
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw SyncTransportException(e.response?.statusCode ?? 0);
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
  Future<SyncCapabilitiesResponse> fetchServerCapabilities();

  Future<PushResponse> push(PushRequest request);

  Future<PullResponse> pull(int cursor, {int limit});

  /// One SSE connection: emits `{"cursor":N}` signals until the server
  /// closes it or it errors (reconnection belongs to SseListener).
  Stream<int> openCursorStream();
}

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;
}

/// Credential endpoints (T6 UI codes against this so tests fake auth
/// without dio). Both server responses carry the full token pair —
/// register issues tokens itself, so a successful register is logged in.
/// Device registration + listing. Separate from [SyncApiClient] so the sync
/// fakes in tests are not forced to grow device methods they never call.
abstract class DeviceApi {
  /// Idempotent: the client reports on every cold start, and a repeat report
  /// must not create a second row or wipe a name the user set.
  Future<DeviceDto> registerDevice({required String deviceId, String? name});

  Future<List<DeviceDto>> fetchDevices();
}

/// Attachment blob endpoints. Separate from [SyncApiClient] for the same
/// reason as [DeviceApi]: the sync fakes in tests must not grow methods they
/// never call.
abstract class AttachmentApi {
  Future<AttachmentUploadResponse> uploadAttachment({required List<int> bytes});

  Future<List<int>> downloadAttachment(String serverFileRef);

  /// Idempotent — deleting an already-gone blob is a success, so a retried
  /// delete after a flaky response does not surface as an error.
  Future<void> deleteAttachment(String serverFileRef);
}

abstract class AuthApi {
  Future<AuthSession> login({required String email, required String password});

  Future<AuthSession> register({
    required String email,
    required String password,
  });
}

/// Bearer-token auth with single-flight refresh: on 401 the original
/// request is retried exactly once after POST /auth/refresh rotates the
/// token pair (T2 contract).
class AuthSyncApiClient
    implements SyncApiClient, AuthApi, DeviceApi, AttachmentApi {
  AuthSyncApiClient({
    required this.transport,
    required this.tokens,
    this.deviceId = '',
  });

  final SyncTransport transport;
  final SyncTokenStore tokens;

  /// This install's id. Sent as `x-device-id` on every authed request so the
  /// server can bind `AuthContext.deviceId` — the push body carries it too,
  /// but the header is what covers non-push endpoints.
  final String deviceId;

  Future<void>? _refreshInFlight;

  Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final access = await tokens.readAccessToken();
    return {
      if (access != null) 'authorization': 'Bearer $access',
      if (deviceId.isNotEmpty) 'x-device-id': deviceId,
      if (json) 'content-type': 'application/json',
    };
  }

  /// Single-flight refresh + one retry, shared by every authenticated call
  /// shape (JSON, binary upload, binary download).
  Future<SyncHttpResponse> _withRefresh(
    Future<SyncHttpResponse> Function() attempt,
  ) async {
    final response = await attempt();
    if (response.statusCode != 401) return response;
    await _refresh();
    return attempt();
  }

  Future<SyncHttpResponse> _send({
    required String method,
    required String path,
    Object? body,
  }) => _withRefresh(
    () async => transport.send(
      method: method,
      path: path,
      headers: await _authHeaders(),
      body: body,
    ),
  );

  @override
  Future<AttachmentUploadResponse> uploadAttachment({
    required List<int> bytes,
  }) async {
    final response = await _withRefresh(
      () async => transport.sendBytes(
        method: 'POST',
        path: '/attachments/upload',
        headers: await _authHeaders(json: false),
        body: bytes,
      ),
    );
    if (response.statusCode != 200) throw _toException(response);
    return AttachmentUploadResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<int>> downloadAttachment(String serverFileRef) async {
    Future<List<int>> attempt() async => transport.fetchBytes(
      path: '/attachments/${Uri.encodeComponent(serverFileRef)}',
      headers: await _authHeaders(json: false),
    );
    try {
      return await attempt();
    } on SyncTransportException catch (e) {
      if (e.statusCode != 401) {
        throw SyncApiException(
          e.statusCode,
          'transport',
          'attachment download failed (${e.statusCode})',
        );
      }
      await _refresh();
      return attempt();
    }
  }

  @override
  Future<void> deleteAttachment(String serverFileRef) async {
    final response = await _withRefresh(
      () async => transport.send(
        method: 'DELETE',
        path: '/attachments/${Uri.encodeComponent(serverFileRef)}',
        headers: await _authHeaders(json: false),
      ),
    );
    if (response.statusCode != 200) throw _toException(response);
  }

  @override
  Future<DeviceDto> registerDevice({
    required String deviceId,
    String? name,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/devices/register',
      body: jsonEncode({'deviceId': deviceId, if (name != null) 'name': name}),
    );
    if (response.statusCode != 200) throw _toException(response);
    return DeviceDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<DeviceDto>> fetchDevices() async {
    final response = await _send(method: 'GET', path: '/devices');
    if (response.statusCode != 200) throw _toException(response);
    return DeviceListResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    ).devices;
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
    return SyncApiException(
      response.statusCode,
      'error',
      'HTTP ${response.statusCode}',
    );
  }

  T _decode<T>(
    SyncHttpResponse response,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (response.statusCode != 200) throw _toException(response);
    return parse(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) => _authCall(
    path: '/auth/login',
    email: email,
    password: password,
    okStatuses: const [200],
  );

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
  }) => _authCall(
    path: '/auth/register',
    email: email,
    password: password,
    okStatuses: const [200, 201],
  );

  Future<AuthSession> _authCall({
    required String path,
    required String email,
    required String password,
    required List<int> okStatuses,
  }) async {
    final response = await transport.send(
      method: 'POST',
      path: path,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (!okStatuses.contains(response.statusCode)) {
      throw _toException(response);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final userId = json['userId'];
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    if (userId is! String || access is! String || refresh is! String) {
      throw SyncApiException(
        response.statusCode,
        'validation',
        'malformed auth response',
      );
    }
    return AuthSession(
      userId: userId,
      accessToken: access,
      refreshToken: refresh,
    );
  }

  @override
  Future<SyncCapabilitiesResponse> fetchServerCapabilities() async {
    final response = await _send(method: 'GET', path: '/sync/capabilities');
    if (response.statusCode == 404) {
      return const SyncCapabilitiesResponse(capabilities: []);
    }
    return _decode(response, SyncCapabilitiesResponse.fromJson);
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
      path:
          '/sync/pull?cursor=$cursor&limit=$limit&capabilities=${Uri.encodeQueryComponent('${SyncCapability.taskAllocationV1},${SyncCapability.todoRecurrenceV1},${SyncCapability.taskInstanceStateV1},${SyncCapability.reminderTagAttachmentV1}')}',
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
        final lines = utf8.decoder.bind(bytes).transform(const LineSplitter());
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
