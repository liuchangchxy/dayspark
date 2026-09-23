import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:shelf/shelf.dart';

import '../auth.dart';
import '../db.dart';
import '../http.dart';
import 'resources.dart';
import 'schemas.dart';
import 'tools.dart';

// Stateless Streamable HTTP profile: one JSON-RPC message per POST → one
// JSON response (202 empty body for notifications). Auth is a local bearer
// check against the T2 JWT helpers; unauthenticated requests get 401 +
// WWW-Authenticate pointing at the OAuth protected-resource metadata that
// Task 3 serves at /.well-known/oauth-protected-resource.
//
// Scope enforcement is a pluggable seam (T3): replace [scopeChecker] to
// gate tools by token scope — the default allows everything until T3 wires
// real mcp:read/mcp:write scopes.

class McpScopeRequest {
  const McpScopeRequest({
    required this.userId,
    required this.tool,
    required this.readOnly,
    required this.destructive,
  });

  final String userId;
  final String tool;
  final bool readOnly;
  final bool destructive;

  @override
  String toString() =>
      'McpScopeRequest($userId, $tool, readOnly: $readOnly, destructive: $destructive)';
}

class ScopeDecision {
  const ScopeDecision(this.code, this.message, this.hint);

  final String code;
  final String message;
  final String hint;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'message': message,
        'hint': hint,
      };
}

typedef ScopeChecker = ScopeDecision? Function(McpScopeRequest request);

// Default until Task 3 injects the real OAuth scope gate.
ScopeDecision? allowAllScopes(McpScopeRequest request) => null;

class _JsonRpcError implements Exception {
  _JsonRpcError(this.code, this.message, [this.data]);

  final int code;
  final String message;
  final Object? data;
}

class McpEndpoint {
  McpEndpoint({
    required this.db,
    required this.auth,
    required this.notifySeq,
  });

  final AppDatabase db;
  final Auth auth;
  final void Function(String userId, int seq) notifySeq;

  // T3 seam: swap this for a checker that reads `scope` from the JWT and
  // returns ScopeDecision(code: FORBIDDEN_SCOPE, ...) when the token may
  // not run the tool. Consulted before schema validation on every
  // tools/call, with the tool's annotation flags attached.
  ScopeChecker scopeChecker = allowAllScopes;

  final IdempotencyRegistry idempotency = IdempotencyRegistry();

  late final List<McpTool> tools = mcpTools;
  late final Map<String, McpTool> _toolsByName = {
    for (final tool in tools) tool.name: tool,
  };

  Future<Response> handle(Request request) async {
    final userId = _authenticatedUserId(request);
    if (userId == null) {
      return _unauthorized(request, existingToken: false);
    }
    final contentType = request.headers['content-type'];
    if (contentType != null && !contentType.contains('application/json')) {
      return jsonError(
        415,
        errValidation,
        'content-type must be application/json',
      );
    }

    final raw = await request.readAsString();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _protocolError(null, -32700, 'Parse error', status: 400);
    }
    if (decoded is List) {
      return _protocolError(
        null,
        -32600,
        'Invalid Request: send one JSON-RPC message per request '
            '(batch arrays are not part of this subset)',
        status: 400,
      );
    }
    if (decoded is! Map) {
      return _protocolError(
        null,
        -32600,
        'Invalid Request: body must be a JSON-RPC object',
        status: 400,
      );
    }
    final message = Map<String, dynamic>.from(decoded);
    if (message['jsonrpc'] != '2.0') {
      return _protocolError(
        null,
        -32600,
        'Invalid Request: jsonrpc must be "2.0"',
        status: 400,
      );
    }
    final id = message['id'];
    final isRequest = id is String || id is int;
    final method = message['method'];
    if (method is! String) {
      if (!isRequest) {
        return Response(202);
      }
      return _protocolError(
        id,
        -32600,
        'Invalid Request: method must be a string',
        status: 400,
      );
    }

    try {
      final result = await _dispatch(userId, method, message['params']);
      if (!isRequest) {
        return Response(202);
      }
      return jsonResponse(200, <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });
    } on _JsonRpcError catch (e) {
      if (!isRequest) {
        return Response(202);
      }
      return jsonResponse(200, <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{
          'code': e.code,
          'message': e.message,
          if (e.data != null) 'data': e.data,
        },
      });
    }
  }

  String? _authenticatedUserId(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) {
      return null;
    }
    return auth.verifyAccessToken(header.substring(7));
  }

  Response _unauthorized(Request request, {required bool existingToken}) {
    final origin = _origin(request);
    final challenge =
        'Bearer resource_metadata="$origin/.well-known/oauth-protected-resource"';
    final body = jsonError(
      401,
      errUnauthorized,
      existingToken
          ? 'invalid or expired access token'
          : 'missing bearer token',
    );
    return body.change(headers: {'www-authenticate': challenge});
  }

  String _origin(Request request) {
    final requested = request.requestedUri;
    if (requested.hasScheme && requested.host.isNotEmpty) {
      return requested.origin;
    }
    final host = request.headers['host'];
    return host == null || host.isEmpty ? 'http://localhost' : 'http://$host';
  }

  Response _protocolError(
    Object? id,
    int code,
    String message, {
    required int status,
  }) {
    return jsonResponse(status, <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });
  }

  Future<Map<String, Object?>> _dispatch(
    String userId,
    String method,
    Object? params,
  ) async {
    switch (method) {
      case 'initialize':
        return _initialize(params);
      case 'ping':
        return <String, Object?>{};
      case 'tools/list':
        return <String, Object?>{
          'tools': tools.map((t) => t.toJson()).toList(),
        };
      case 'tools/call':
        return _toolsCall(userId, params);
      case 'resources/list':
        return <String, Object?>{
          'resources': mcpResources.map((r) => r.toJson()).toList(),
        };
      case 'resources/read':
        return _resourcesRead(userId, params);
      default:
        throw _JsonRpcError(-32601, 'Method not found: $method');
    }
  }

  Map<String, Object?> _initialize(Object? params) {
    var requested = mcpLatestProtocolVersion;
    if (params is Map && params['protocolVersion'] is String) {
      final clientVersion = params['protocolVersion'] as String;
      requested = mcpSupportedProtocolVersions.contains(clientVersion)
          ? clientVersion
          : mcpLatestProtocolVersion;
    } else if (params is! Map && params != null) {
      throw _JsonRpcError(-32602, 'initialize params must be an object');
    }
    return <String, Object?>{
      'protocolVersion': requested,
      'capabilities': <String, Object?>{
        'tools': {'listChanged': false},
        'resources': {'listChanged': false},
      },
      'serverInfo': <String, Object?>{
        'name': 'dayspark',
        'version': mcpServerVersion,
      },
      'instructions':
          'DaySpark calendar and task tools. Send datetimes as ISO 8601 with '
          'an explicit timezone offset or Z; responses are canonical UTC. '
          'Recurrence is a structured object, never an RFC string. Business '
          'failures arrive as isError tool results carrying code/message/hint.',
    };
  }

  Future<Map<String, Object?>> _toolsCall(
    String userId,
    Object? params,
  ) async {
    if (params is! Map) {
      throw _JsonRpcError(
        -32602,
        'tools/call params must be an object with a tool name',
      );
    }
    final name = params['name'];
    if (name is! String || name.isEmpty) {
      throw _JsonRpcError(-32602, 'tools/call requires a non-empty name');
    }
    final tool = _toolsByName[name];
    if (tool == null) {
      return _toolErrorResult(<String, Object?>{
        'code': mcpCodeUnknownTool,
        'message': 'unknown tool: $name',
        'hint': hintUnknownTool,
      });
    }

    final decision = scopeChecker(McpScopeRequest(
      userId: userId,
      tool: name,
      readOnly: tool.readOnly,
      destructive: tool.destructive,
    ));
    if (decision != null) {
      return _toolErrorResult(decision.toJson());
    }

    final rawArgs = params['arguments'];
    if (rawArgs != null && rawArgs is! Map) {
      return _toolErrorResult(<String, Object?>{
        'code': mcpCodeValidation,
        'message': 'arguments must be a JSON object',
        'hint': hintValidation,
      });
    }
    final args = rawArgs == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(rawArgs as Map);
    try {
      validateAgainstSchema(tool.inputSchema, args);
    } on McpToolException catch (e) {
      return _toolErrorResult(e.toJson());
    }

    final ctx = McpToolContext(
      db: db,
      userId: userId,
      notifySeq: notifySeq,
      idempotency: idempotency,
      now: DateTime.now().toUtc(),
    );
    try {
      final result = await tool.handler(ctx, args);
      final asError = result.remove('_isError');
      if (asError == true) {
        return _toolSuccessResult(result, isError: true);
      }
      return _toolSuccessResult(result);
    } on McpToolException catch (e) {
      return _toolErrorResult(e.toJson());
    } catch (e) {
      return _toolErrorResult(<String, Object?>{
        'code': mcpCodeInternal,
        'message': 'tool "$name" failed: $e',
        'hint': 'Retry once; if it persists, check the server logs for the '
            'underlying exception.',
      });
    }
  }

  Future<Map<String, Object?>> _resourcesRead(
    String userId,
    Object? params,
  ) async {
    if (params is! Map) {
      throw _JsonRpcError(-32602, 'resources/read params must be an object');
    }
    final uri = params['uri'];
    if (uri is! String || uri.isEmpty) {
      throw _JsonRpcError(-32602, 'resources/read requires a uri');
    }
    final ctx = McpToolContext(
      db: db,
      userId: userId,
      notifySeq: notifySeq,
      idempotency: idempotency,
      now: DateTime.now().toUtc(),
    );
    try {
      final snapshot = await readMcpResource(ctx, uri);
      return <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'uri': uri,
            'mimeType': 'application/json',
            'text': jsonEncode(snapshot),
          },
        ],
      };
    } on McpToolException catch (e) {
      // MCP has no isError envelope for resources — the spec's channel for
      // an unreadable URI is JSON-RPC -32002 (resource not found).
      throw _JsonRpcError(
        -32002,
        'Resource not found: $uri',
        e.toJson(),
      );
    }
  }

  Map<String, Object?> _toolSuccessResult(
    Map<String, Object?> payload, {
    bool isError = false,
  }) {
    return <String, Object?>{
      'content': <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': jsonEncode(payload),
        },
      ],
      if (isError) 'isError': true,
    };
  }

  Map<String, Object?> _toolErrorResult(Map<String, Object?> error) {
    return <String, Object?>{
      'content': <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': jsonEncode(error),
        },
      ],
      'isError': true,
    };
  }
}
