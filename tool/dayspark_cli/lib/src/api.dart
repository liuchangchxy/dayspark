import 'dart:convert';
import 'dart:io';

import 'package:dayspark_cli/src/args.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

class ToolFailure implements Exception {
  ToolFailure(this.message);

  final String message;

  @override
  String toString() => 'ToolFailure: $message';
}

class Credentials {
  Credentials({
    required this.server,
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });

  final String server;
  final String userId;
  final String accessToken;
  final String refreshToken;

  factory Credentials.fromJson(Map<String, dynamic> json) {
    final server = json['server'];
    final userId = json['userId'];
    final accessToken = json['accessToken'];
    final refreshToken = json['refreshToken'];
    if (server is! String ||
        userId is! String ||
        accessToken is! String ||
        refreshToken is! String) {
      throw AuthFailure('malformed credentials file — run dayspark login');
    }
    return Credentials(
      server: server,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'server': server,
        'userId': userId,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };
}

// DAYSPARK_HOME overrides ~/.dayspark so tests (and sandboxes) never touch
// the user's real credentials.
String credentialsPath(Map<String, String> environment) {
  final home = environment['DAYSPARK_HOME'];
  if (home != null && home.isNotEmpty) return '$home/credentials.json';
  final userHome = environment['HOME'];
  if (userHome == null || userHome.isEmpty) {
    throw AuthFailure('HOME is not set — cannot locate credentials');
  }
  return '$userHome/.dayspark/credentials.json';
}

Future<Credentials?> loadCredentials(Map<String, String> environment) async {
  final file = File(credentialsPath(environment));
  if (!await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    return Credentials.fromJson(decoded);
  } on FormatException {
    throw AuthFailure('malformed credentials file — run dayspark login');
  }
}

Future<void> saveCredentials(
  Credentials credentials,
  Map<String, String> environment,
) async {
  final file = File(credentialsPath(environment));
  await file.parent.create(recursive: true);
  // Create + chmod BEFORE writing tokens so the secret never lands on disk
  // world-readable, even for the window between create and chmod.
  await file.writeAsString('');
  final chmod = await Process.run('chmod', <String>['600', file.path]);
  if (chmod.exitCode != 0) {
    throw AuthFailure('failed to restrict permissions on ${file.path}');
  }
  await file.writeAsString(jsonEncode(credentials.toJson()));
}

Future<void> deleteCredentials(Map<String, String> environment) async {
  final file = File(credentialsPath(environment));
  if (await file.exists()) await file.delete();
}

class ToolResult {
  ToolResult({required this.isError, required this.payload});

  final bool isError;
  final Map<String, dynamic> payload;
}

String? _envelopeMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (decoded['message'] is String) return decoded['message'] as String;
    }
  } on FormatException {
    return null;
  }
  return null;
}

class Api {
  Api({
    required this.server,
    required this.httpClient,
    required this.credentials,
    required this.onRotated,
  });

  final Uri server;
  final HttpClient httpClient;
  Credentials credentials;
  final Future<void> Function(Credentials updated) onRotated;

  int _nextId = 1;

  static Uri normalizeServer(String raw) {
    final trimmed = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw UsageException('--server must be an absolute http(s) URL');
    }
    return uri;
  }

  static Future<Credentials> login({
    required Uri server,
    required String email,
    required String password,
    required HttpClient httpClient,
  }) async {
    final response = await _send(
      httpClient,
      'POST',
      Uri.parse('$server/auth/login'),
      body: jsonEncode(<String, Object?>{'email': email, 'password': password}),
    );
    if (response.status != 200) {
      throw AuthFailure(
        _envelopeMessage(response.body) ?? 'login failed (HTTP ${response.status})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw AuthFailure('malformed login response');
    }
    final userId = decoded['userId'];
    final accessToken = decoded['accessToken'];
    final refreshToken = decoded['refreshToken'];
    if (userId is! String || accessToken is! String || refreshToken is! String) {
      throw AuthFailure('malformed login response');
    }
    return Credentials(
      server: server.toString(),
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<({int status, String body})> me() async {
    var response = await _authed(
      'GET',
      Uri.parse('$server/auth/me'),
    );
    if (response.status == 401) {
      await _refresh();
      response = await _authed('GET', Uri.parse('$server/auth/me'));
    }
    if (response.status != 200) {
      throw AuthFailure(
        _envelopeMessage(response.body) ?? 'auth check failed (HTTP ${response.status})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw AuthFailure('malformed /auth/me response');
    }
    return (status: response.status, body: response.body);
  }

  // All data operations go through POST /mcp tools/call with the frozen T2
  // tool names — the CLI never talks to the sync HTTP API directly.
  Future<ToolResult> toolsCall(String name, Map<String, Object?> arguments) async {
    var response = await _mcpCall(name, arguments);
    if (response.status == 401) {
      await _refresh();
      response = await _mcpCall(name, arguments);
    }
    if (response.status != 200) {
      throw ToolFailure(
        _envelopeMessage(response.body) ?? 'MCP call failed (HTTP ${response.status})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ToolFailure('malformed MCP response');
    }
    final rpcError = decoded['error'];
    if (rpcError is Map) {
      throw ToolFailure('${rpcError['message'] ?? 'jsonrpc error'}');
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw ToolFailure('MCP response missing result');
    }
    final content = result['content'];
    var payload = <String, dynamic>{};
    if (content is List && content.isNotEmpty && content.first is Map) {
      final text = (content.first as Map)['text'];
      if (text is String) {
        try {
          final decodedPayload = jsonDecode(text);
          if (decodedPayload is Map<String, dynamic>) payload = decodedPayload;
        } on FormatException {
          throw ToolFailure('tool returned non-JSON payload');
        }
      }
    }
    return ToolResult(isError: result['isError'] == true, payload: payload);
  }

  Future<({int status, String body})> _mcpCall(
    String name,
    Map<String, Object?> arguments,
  ) {
    return _authed(
      'POST',
      Uri.parse('$server/mcp'),
      body: jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': <String, Object?>{'name': name, 'arguments': arguments},
      }),
    );
  }

  // Refresh-on-401 exactly once per call (same pattern as the app's
  // AuthSyncApiClient): rotate via /auth/refresh, persist, retry caller.
  Future<void> _refresh() async {
    final response = await _send(
      httpClient,
      'POST',
      Uri.parse('$server/auth/refresh'),
      body: jsonEncode(<String, Object?>{'refreshToken': credentials.refreshToken}),
    );
    if (response.status != 200) {
      throw AuthFailure('session expired — run dayspark login');
    }
    final decoded = jsonDecode(response.body);
    final accessToken = decoded is Map ? decoded['accessToken'] : null;
    final refreshToken = decoded is Map ? decoded['refreshToken'] : null;
    if (accessToken is! String || refreshToken is! String) {
      throw AuthFailure('malformed refresh response');
    }
    credentials = Credentials(
      server: credentials.server,
      userId: credentials.userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await onRotated(credentials);
  }

  Future<({int status, String body})> _authed(
    String method,
    Uri uri, {
    String? body,
  }) {
    return _send(
      httpClient,
      method,
      uri,
      bearer: credentials.accessToken,
      body: body,
    );
  }

  static Future<({int status, String body})> _send(
    HttpClient httpClient,
    String method,
    Uri uri, {
    String? bearer,
    String? body,
  }) async {
    try {
      final request = await httpClient.openUrl(method, uri);
      // Headers must be set BEFORE the body: dart:io freezes them on the
      // first written byte.
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: text);
    } on IOException catch (e) {
      throw ToolFailure('cannot reach ${uri.host}: $e');
    }
  }
}
