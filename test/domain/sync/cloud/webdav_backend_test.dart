import 'dart:convert';
import 'dart:io';

import 'package:dayspark/domain/sync/cloud/cloud_sync_backend.dart';
import 'package:dayspark/domain/sync/cloud/webdav_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal WebDAV: the four verbs this backend uses, with the RFC 4918
/// conditional-write semantics it depends on.
class _FakeDav {
  _FakeDav(this.server);

  final HttpServer server;
  final Map<String, ({String body, String etag})> files = {};
  int etagCounter = 0;
  String? lastAuthorization;
  bool etagOnHeadOnly = false;
  bool exposeEtag = true;
  int mkcolStatus = 405;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  static Future<_FakeDav> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dav = _FakeDav(server);
    server.listen(dav._handle);
    return dav;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    lastAuthorization = request.headers.value('authorization');
    final path = request.uri.path;
    switch (request.method) {
      case 'MKCOL':
        response.statusCode = mkcolStatus;
      case 'GET':
        final file = files[path];
        if (file == null) {
          response.statusCode = 404;
        } else {
          response.statusCode = 200;
          if (exposeEtag) response.headers.set('etag', file.etag);
          response.write(file.body);
        }
      case 'HEAD':
        final file = files[path];
        if (file == null) {
          response.statusCode = 404;
        } else {
          response.statusCode = 200;
          if (exposeEtag) response.headers.set('etag', file.etag);
        }
      case 'PUT':
        final body = await utf8.decoder.bind(request).join();
        final ifMatch = request.headers.value('if-match');
        final ifNone = request.headers.value('if-none-match');
        final existing = files[path];
        if (ifNone == '*' && existing != null) {
          response.statusCode = 412;
        } else if (ifMatch != null &&
            (existing == null || existing.etag != ifMatch)) {
          response.statusCode = 412;
        } else {
          final etag = 'v${++etagCounter}';
          files[path] = (body: body, etag: etag);
          response.statusCode = 201;
          if (!etagOnHeadOnly) response.headers.set('etag', etag);
        }
      default:
        response.statusCode = 405;
    }
    await response.close();
  }
}

void main() {
  late _FakeDav dav;

  setUp(() async {
    dav = await _FakeDav.start();
  });

  tearDown(() async {
    await dav.close();
  });

  WebDavBackend backend({
    Map<String, String> headers = const {},
    String? username,
    String? password,
  }) => WebDavBackend(
    baseUrl: dav.baseUrl,
    documentPath: '/dayspark/sync.json',
    username: username,
    password: password,
    extraHeaders: headers,
  );

  test('a missing document reads as null rather than an error', () async {
    expect(await backend().read(), isNull);
  });

  test('a write creates the document and returns its validator', () async {
    final davBackend = backend();
    await davBackend.ensureReady();
    final etag = await davBackend.write(body: '{"a":1}', ifMatch: null);

    expect(etag, 'v1');
    expect(dav.files['/dayspark/sync.json']!.body, '{"a":1}');
    final snapshot = await davBackend.read();
    expect(snapshot!.etag, 'v1');
    expect(snapshot.body, '{"a":1}');
  });

  test('creating over an existing document is refused, not overwritten', () async {
    dav.files['/dayspark/sync.json'] = (body: 'peer', etag: 'v9');
    expect(
      () => backend().write(body: 'mine', ifMatch: null),
      throwsA(isA<CloudPreconditionFailed>()),
    );
    expect(dav.files['/dayspark/sync.json']!.body, 'peer');
  });

  test('a stale validator is refused, not overwritten', () async {
    dav.files['/dayspark/sync.json'] = (body: 'peer', etag: 'v9');
    expect(
      () => backend().write(body: 'mine', ifMatch: 'v1'),
      throwsA(isA<CloudPreconditionFailed>()),
    );
    expect(dav.files['/dayspark/sync.json']!.body, 'peer');
  });

  test('a current validator is accepted and rotated', () async {
    dav.files['/dayspark/sync.json'] = (body: 'old', etag: 'v0');
    final etag = await backend().write(body: 'new', ifMatch: 'v0');
    expect(etag, 'v1');
    expect(dav.files['/dayspark/sync.json']!.body, 'new');
  });

  test('a server that only exposes ETag on HEAD still works', () async {
    final davBackend = WebDavBackend(
      baseUrl: dav.baseUrl,
      documentPath: '/dayspark/sync.json',
    );
    dav.etagOnHeadOnly = true;
    expect(await davBackend.write(body: 'x', ifMatch: null), 'v1');
  });

  test('a server with no ETag at all is rejected: sync would be unsafe', () async {
    dav.exposeEtag = false;
    dav.files['/dayspark/sync.json'] = (body: 'x', etag: 'v1');
    expect(
      () => backend().read(),
      throwsA(isA<CloudBackendException>()),
    );
  });

  test('an existing collection is not an error', () async {
    dav.mkcolStatus = 405;
    await backend().ensureReady();
  });

  test('credentials travel as basic auth', () async {
    await backend(username: 'me', password: 'secret').read();
    expect(
      dav.lastAuthorization,
      'Basic ${base64Encode(utf8.encode('me:secret'))}',
    );
  });
}
