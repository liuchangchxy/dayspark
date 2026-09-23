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
// Scope enforcement runs through the [scopeChecker] seam on every tools/call
// AND resources/list+read. AppServer wires the real mcp:read/mcp:write gate
// (oauth/middleware.dart); the fail-closed default denies everything so a
// forgotten wiring can never ship an open MCP.

const int mcpMaxBodyBytes = 256 * 1024;

class McpScopeRequest {
  const McpScopeRequest({
    required this.userId,
    required this.tool,
    required this.readOnly,
    required this.destructive,
    this.scope,
  });

  final String userId;
  final String tool;
  final bool readOnly;
  final bool destructive;
  final String? scope;

  @override
  String toString() =>
      'McpScopeRequest($userId, $tool, readOnly: $readOnly, '
      'destructive: $destructive, scope: $scope)';
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

// Fail-closed default: without a configured checker nothing runs. AppServer
// swaps in oauth/middleware.dart's mcpScopeGate at construction.
ScopeDecision? denyAllScopes(McpScopeRequest request) => const ScopeDecision(
  mcpCodeForbiddenScope,
  'no scope checker configured',
  hintForbiddenScope,
);

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

  // T3 seam: AppServer assigns oauth/middleware.dart's mcpScopeGate here.
  // Consulted before schema validation on every tools/call and on every
  // resources/list + resources/read, with the tool's annotation flags and
  // the token's scope claim attached.
  ScopeChecker scopeChecker = denyAllScopes;

  final IdempotencyRegistry idempotency = IdempotencyRegistry();

  late final List<McpTool> tools = mcpTools;
  late final Map<String, McpTool> _toolsByName = {
    for (final tool in tools) tool.name: tool,
  };

  Future<Response> handle(Request request) async {
    final header = request.headers['authorization'];
    final hasBearer = header != null && header.startsWith('Bearer ');
    final claims = hasBearer
        ? auth.verifyAccessTokenClaims(header.substring(7))
        : null;
    if (claims == null) {
      return _unauthorized(request, existingToken: hasBearer);
    }
    final userId = claims.userId;
    final scope = claims.scope;
    final contentType = request.headers['content-type'];
    if (contentType != null && !contentType.contains('application/json')) {
      return jsonError(
        415,
        errValidation,
        'content-type must be application/json',
      );
    }

    final declared = int.tryParse(request.headers['content-length'] ?? '');
    if (declared != null && declared > mcpMaxBodyBytes) {
      return _payloadTooLarge();
    }
    final buffer = <int>[];
    await for (final chunk in request.read()) {
      if (buffer.length + chunk.length > mcpMaxBodyBytes) {
        return _payloadTooLarge();
      }
      buffer.addAll(chunk);
    }
    String raw;
    try {
      raw = utf8.decode(buffer);
    } on FormatException {
      return _protocolError(null, -32700, 'Parse error', status: 400);
    }
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
      final result = await _dispatch(userId, scope, method, message['params']);
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

  Response _unauthorized(Request request, {required bool existingToken}) {
    final origin = requestOrigin(request);
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

  Response _payloadTooLarge() => jsonError(
    413,
    errValidation,
    'request body exceeds the 256KB limit',
  );

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
    String? scope,
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
        return _toolsCall(userId, scope, params);
      case 'resources/list':
        _requireScope(
          userId,
          scope,
          tool: 'resources/list',
          readOnly: true,
        );
        return <String, Object?>{
          'resources': mcpResources.map((r) => r.toJson()).toList(),
        };
      case 'resources/read':
        return _resourcesRead(userId, scope, params);
      default:
        throw _JsonRpcError(-32601, 'Method not found: $method');
    }
  }

  void _requireScope(
    String userId,
    String? scope, {
    required String tool,
    required bool readOnly,
  }) {
    final decision = scopeChecker(
      McpScopeRequest(
        userId: userId,
        tool: tool,
        readOnly: readOnly,
        destructive: false,
        scope: scope,
      ),
    );
    if (decision != null) {
      // Resources have no isError tool-result envelope, so a denied
      // resources/* call surfaces as a JSON-RPC error in the server range
      // with the FORBIDDEN_SCOPE payload attached as data.
      throw _JsonRpcError(-32000, decision.message, decision.toJson());
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
    String? scope,
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
      scope: scope,
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
    String? scope,
    Object? params,
  ) async {
    _requireScope(userId, scope, tool: 'resources/read', readOnly: true);
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
