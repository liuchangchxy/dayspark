import 'dart:convert';

import 'package:dio/dio.dart';

import 'cloud_sync_backend.dart';

/// WebDAV has no app registration and the protocol itself supplies the
/// conditional write (`If-Match` / `If-None-Match` + `ETag`, RFC 4918 §10.4),
/// which makes it the one cloud target that can be exercised end to end
/// without a developer account.
class WebDavBackend implements CloudSyncBackend {
  WebDavBackend({
    required String baseUrl,
    required String documentPath,
    String? username,
    String? password,
    Map<String, String> extraHeaders = const {},
    Dio? client,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _documentPath = documentPath.startsWith('/')
           ? documentPath
           : '/$documentPath',
       _extraHeaders = Map<String, String>.from(extraHeaders),
       _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
               sendTimeout: const Duration(seconds: 60),
               followRedirects: false,
             ),
           ) {
    if (username != null && username.isNotEmpty) {
      final token = base64Encode(utf8.encode('$username:${password ?? ''}'));
      _extraHeaders['Authorization'] = 'Basic $token';
    }
  }

  final String _baseUrl;
  final String _documentPath;
  final Map<String, String> _extraHeaders;
  final Dio _client;

  String get _documentUrl => '$_baseUrl$_documentPath';

  String get _parentUrl {
    final index = _documentPath.lastIndexOf('/');
    if (index <= 0) return '$_baseUrl/';
    return '$_baseUrl${_documentPath.substring(0, index + 1)}';
  }

  @override
  String get displayTarget => _documentUrl;

  @override
  Future<void> ensureReady() async {
    final response = await _client.request<void>(
      _parentUrl,
      options: Options(
        method: 'MKCOL',
        headers: _extraHeaders,
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
    final status = response.statusCode ?? 0;
    // 201 created; 405 already exists (RFC 4918 §9.3.1); 301/302 a server
    // that insists on the trailing-slash form; some servers answer 200.
    if (status == 201 || status == 200 || status == 405 || status == 301) {
      return;
    }
    if (status >= 200 && status < 300) return;
    throw CloudBackendException(
      'MKCOL failed for $_parentUrl',
      statusCode: status,
    );
  }

  @override
  Future<CloudFileSnapshot?> read() async {
    final response = await _client.get<String>(
      _documentUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: _extraHeaders,
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 404 || status == 410) return null;
    if (status < 200 || status >= 300) {
      throw CloudBackendException(
        'GET $_documentUrl failed',
        statusCode: status,
      );
    }
    final etag = _etagOf(response.headers);
    if (etag == null) {
      // Without a validator the next write could only overwrite blindly.
      throw const CloudBackendException(
        'server returned no ETag; WebDAV sync needs conditional writes',
      );
    }
    return CloudFileSnapshot(body: response.data ?? '', etag: etag);
  }

  @override
  Future<String> write({
    required String body,
    required String? ifMatch,
  }) async {
    final headers = <String, String>{
      ..._extraHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      if (ifMatch != null) 'If-Match': ifMatch else 'If-None-Match': '*',
    };
    final response = await _client.put<String>(
      _documentUrl,
      data: body,
      options: Options(
        headers: headers,
        contentType: 'application/json; charset=utf-8',
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 412) throw const CloudPreconditionFailed();
    if (status < 200 || status >= 300) {
      throw CloudBackendException(
        'PUT $_documentUrl failed',
        statusCode: status,
      );
    }
    final fromResponse = _etagOf(response.headers);
    if (fromResponse != null) return fromResponse;
    // Many servers only hand the validator out on a subsequent HEAD.
    final head = await _client.head<void>(
      _documentUrl,
      options: Options(
        headers: _extraHeaders,
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
    final fromHead = _etagOf(head.headers);
    if (fromHead != null) return fromHead;
    throw CloudBackendException(
      'PUT succeeded but no ETag is exposed; cannot sync safely',
      statusCode: status,
    );
  }

  String? _etagOf(Headers headers) {
    final raw = headers.value('etag');
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }
}
