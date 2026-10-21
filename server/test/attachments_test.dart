import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

Uri _uri(String path) => Uri.parse('http://localhost$path');

Future<Response> _request(
  Handler handler,
  String method,
  String path, {
  List<int>? bytes,
  Map<String, Object?>? body,
  String? token,
}) async {
  return await handler(
    Request(
      method,
      _uri(path),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (bytes != null) 'content-type': 'application/octet-stream',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: bytes ?? (body == null ? null : jsonEncode(body)),
    ),
  );
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

Future<({String token, String userId})> _register(
  AppServer app,
  String email,
) async {
  final response = await _request(
    app.handler,
    'POST',
    '/auth/register',
    body: {'email': email, 'password': 'password123'},
  );
  expect(response.statusCode, 201);
  final json = await _json(response);
  return (
    token: json['accessToken'] as String,
    userId: json['userId'] as String,
  );
}

Future<String> _upload(
  AppServer app,
  String token,
  List<int> bytes,
) async {
  final response = await _request(
    app.handler,
    'POST',
    '/attachments/upload',
    token: token,
    bytes: bytes,
  );
  expect(response.statusCode, 200);
  return (await _json(response))['serverFileRef'] as String;
}

void main() {
  late AppServer app;
  late Directory storage;
  late String token;
  late String userId;

  setUp(() async {
    storage = Directory.systemTemp.createTempSync('dayspark_att_test');
    app = AppServer(
      Config(
        dbPath: ':memory:',
        port: 0,
        jwtSecret: 'test-secret',
        attachmentDir: storage.path,
      ),
    );
    final account = await _register(app, 'a@example.com');
    token = account.token;
    userId = account.userId;
  });

  tearDown(() async {
    await app.close();
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  test('upload returns a ref and the byte count, download returns the bytes',
      () async {
    final payload = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
    final ref = await _upload(app, token, payload);

    final response = await _request(
      app.handler,
      'GET',
      '/attachments/$ref',
      token: token,
    );
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'application/octet-stream');
    expect(await response.read().expand((c) => c).toList(), payload);
  });

  test('upload of an empty body is rejected', () async {
    final response = await _request(
      app.handler,
      'POST',
      '/attachments/upload',
      token: token,
      bytes: const <int>[],
    );
    expect(response.statusCode, 400);
  });

  test('upload above the attachment cap returns the 413 envelope', () async {
    final response = await _request(
      app.handler,
      'POST',
      '/attachments/upload',
      token: token,
      bytes: Uint8List(maxAttachmentBytes + 1),
    );
    expect(response.statusCode, 413);
    expect((await _json(response))['error'], isA<Map<String, dynamic>>());
  });

  test('unauthenticated upload and download are rejected', () async {
    final upload = await _request(
      app.handler,
      'POST',
      '/attachments/upload',
      bytes: const <int>[1, 2, 3],
    );
    expect(upload.statusCode, 401);

    final ref = await _upload(app, token, const <int>[1, 2, 3]);
    final download = await _request(
      app.handler,
      'GET',
      '/attachments/$ref',
    );
    expect(download.statusCode, 401);
  });

  test('download of an unknown ref is 404', () async {
    final response = await _request(
      app.handler,
      'GET',
      '/attachments/does-not-exist',
      token: token,
    );
    expect(response.statusCode, 404);
  });

  test('delete removes the blob and is idempotent', () async {
    final ref = await _upload(app, token, const <int>[7, 7, 7]);
    final path = '${storage.path}/$userId/$ref';
    expect(File(path).existsSync(), isTrue);

    final first = await _request(
      app.handler,
      'DELETE',
      '/attachments/$ref',
      token: token,
    );
    expect(first.statusCode, 200);
    expect(File(path).existsSync(), isFalse);

    final second = await _request(
      app.handler,
      'DELETE',
      '/attachments/$ref',
      token: token,
    );
    expect(second.statusCode, 200);

    final download = await _request(
      app.handler,
      'GET',
      '/attachments/$ref',
      token: token,
    );
    expect(download.statusCode, 404);
  });

  test('a blob is only visible inside its owner namespace', () async {
    final payload = Uint8List.fromList(const [1, 2, 3, 4, 5, 6]);
    final refA = await _upload(app, token, payload);
    final accountB = await _register(app, 'b@example.com');

    final aDownload = await _request(
      app.handler,
      'GET',
      '/attachments/$refA',
      token: token,
    );
    expect(aDownload.statusCode, 200);
    expect(await aDownload.read().expand((c) => c).toList(), payload);

    final bDownload = await _request(
      app.handler,
      'GET',
      '/attachments/$refA',
      token: accountB.token,
    );
    expect(
      bDownload.statusCode,
      404,
      reason: "B must not resolve A's ref",
    );

    final bDelete = await _request(
      app.handler,
      'DELETE',
      '/attachments/$refA',
      token: accountB.token,
    );
    expect(bDelete.statusCode, 200, reason: 'delete stays idempotent');
    expect(
      File('${storage.path}/$userId/$refA').existsSync(),
      isTrue,
      reason: "B's delete must not touch A's file",
    );

    final aReDownload = await _request(
      app.handler,
      'GET',
      '/attachments/$refA',
      token: token,
    );
    expect(aReDownload.statusCode, 200);
    expect(await aReDownload.read().expand((c) => c).toList(), payload);

    final aDelete = await _request(
      app.handler,
      'DELETE',
      '/attachments/$refA',
      token: token,
    );
    expect(aDelete.statusCode, 200);
    expect(File('${storage.path}/$userId/$refA').existsSync(), isFalse);

    final afterDelete = await _request(
      app.handler,
      'GET',
      '/attachments/$refA',
      token: token,
    );
    expect(afterDelete.statusCode, 404);
  });

  test('a ref that tries to escape the storage directory is rejected', () async {
    // A sibling of the storage dir the traversal would reach.
    final victim = File('${storage.parent.path}/escaped.txt')
      ..writeAsStringSync('must survive');

    for (final ref in <String>[
      '..%2Fescaped.txt',
      '%2E%2E%2Fescaped.txt',
      '..',
      '.',
    ]) {
      final response = await _request(
        app.handler,
        'DELETE',
        '/attachments/$ref',
        token: token,
      );
      // 400 (rejected by the ref check) or 404 (the URL never reached the
      // route) both mean refused; what matters is that none of them act on
      // a path outside the storage directory.
      expect(
        response.statusCode,
        anyOf(400, 404),
        reason: 'ref "$ref" must not be accepted',
      );
    }
    expect(victim.existsSync(), isTrue);
    expect(victim.readAsStringSync(), 'must survive');
  });
}
