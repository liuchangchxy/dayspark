import 'dart:convert';
import 'dart:io';

// MCP stdio transport is newline-delimited JSON (one JSON-RPC message per
// line) — NOT LSP-style Content-Length framing. Codex/Claude clients speak
// NDJSON on stdio, so the bridge reads lines and writes lines.
//
// initialize is proxied like any other message (no local serverInfo cache):
// the Streamable HTTP endpoint is stateless, so one POST per message keeps
// the bridge dumb and can never serve a stale serverInfo.

const int exitConfig = 78;

// JSON-RPC application-defined error: transport/HTTP failures are wrapped
// in this shape so clients render a proper error instead of hanging on a
// request that will never get a response.
const int rpcInternalError = -32002;

class HttpPostResult {
  const HttpPostResult(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

typedef HttpPoster = Future<HttpPostResult> Function(String body);

String? envError(Map<String, String> env) {
  final url = env['DAYSPARK_MCP_URL'];
  if (url == null || url.isEmpty) {
    return 'DAYSPARK_MCP_URL is required (full /mcp endpoint URL)';
  }
  final token = env['DAYSPARK_MCP_TOKEN'];
  if (token == null || token.isEmpty) {
    return 'DAYSPARK_MCP_TOKEN is required (bearer token for the endpoint)';
  }
  return null;
}

Map<String, Object?>? _tryDecode(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Map<String, Object?> _rpcError(Object? id, String message, [Object? data]) =>
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{
        'code': rpcInternalError,
        'message': message,
        if (data != null) 'data': data,
      },
    };

bool _isJsonRpcEnvelope(Map<String, Object?> body) =>
    body['jsonrpc'] == '2.0';

Future<void> runBridge({
  required Stream<String> lines,
  required void Function(String line) writeLine,
  required HttpPoster post,
}) async {
  await for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final decoded = _tryDecode(line);
    if (decoded == null) {
      // Without a parseable id there is no request to answer; surfacing the
      // garbage on stderr keeps stdout a pure JSON-RPC channel.
      stderr.writeln('mcp_stdio_wrapper: dropped non-JSON stdin line');
      continue;
    }
    final id = decoded['id'];
    final isRequest = id is String || id is int;

    HttpPostResult result;
    try {
      result = await post(line);
    } on Object catch (e) {
      if (isRequest) {
        writeLine(
          jsonEncode(_rpcError(id, 'internal error: ${e.runtimeType}: $e')),
        );
      } else {
        stderr.writeln('mcp_stdio_wrapper: notification failed: $e');
      }
      continue;
    }

    // Notifications (no id) expect 202/empty — never emit a response line.
    if (!isRequest) continue;

    final body = result.body.trim();
    final envelope = body.isEmpty ? null : _tryDecode(body);
    if (envelope != null && _isJsonRpcEnvelope(envelope)) {
      writeLine(body);
      continue;
    }
    if (result.statusCode >= 200 && result.statusCode < 300 && body.isEmpty) {
      writeLine(
        jsonEncode(_rpcError(id, 'internal error: empty response to request')),
      );
      continue;
    }
    writeLine(
      jsonEncode(
        _rpcError(
          id,
          'internal error: HTTP ${result.statusCode}',
          <String, Object?>{
            'status': result.statusCode,
            'body': body.length > 512 ? '${body.substring(0, 512)}…' : body,
          },
        ),
      ),
    );
  }
}
