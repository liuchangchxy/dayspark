import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:shelf/shelf.dart';

Response jsonResponse(int status, Map<String, Object?> body) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Response jsonError(int status, String code, String message) {
  return jsonResponse(status, {
    'error': {'code': code, 'message': message},
  });
}

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;
}

Future<Map<String, dynamic>> readJsonObject(Request request) async {
  try {
    // Route through the shared cap (readBodyBytes) so /auth/* and
    // /sync/push get the same 413 ceiling as the OAuth POSTs — two of
    // these callers are unauthenticated.
    final decoded = jsonDecode(utf8.decode(await readBodyBytes(request)));
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(400, errValidation, 'body must be a JSON object');
    }
    return decoded;
  } on ApiException {
    rethrow;
  } on FormatException {
    throw ApiException(400, errValidation, 'invalid JSON body');
  }
}

// Shared request-body ceiling for every endpoint that reads a body (POST
// /mcp, all four OAuth POSTs, and every readJsonObject caller —
// /auth/register, /auth/login, /auth/refresh, /sync/push): content-length
// fast path plus streaming accumulation with early abort, so an oversized
// upload is never buffered whole. Over-cap throws ApiException(413) →
// catchApiErrors renders the standard {"error":{"code":"validation",...}}
// envelope.
const int maxRequestBodyBytes = 256 * 1024;

Future<List<int>> readBodyBytes(Request request) async {
  final declared = int.tryParse(request.headers['content-length'] ?? '');
  if (declared != null && declared > maxRequestBodyBytes) {
    throw _bodyTooLarge();
  }
  final buffer = <int>[];
  await for (final chunk in request.read()) {
    if (buffer.length + chunk.length > maxRequestBodyBytes) {
      throw _bodyTooLarge();
    }
    buffer.addAll(chunk);
  }
  return buffer;
}

ApiException _bodyTooLarge() =>
    ApiException(413, errValidation, 'request body exceeds the 256KB limit');

Middleware catchApiErrors() {
  return (inner) => (request) async {
    try {
      final response = await inner(request);
      // Shelf's router-miss 404 is plain text; wrap it in the envelope.
      // Contracts has no not-found code, so errValidation is the closest
      // existing constant (adding a 404 code would be a contracts change).
      if (response.statusCode == 404 &&
          !(response.headers['content-type'] ?? '').contains('json')) {
        return jsonError(404, errValidation, 'not found');
      }
      return response;
    } on ApiException catch (e) {
      return jsonError(e.status, e.code, e.message);
    }
  };
}

// Absolute origin (scheme://host[:port]) of the incoming request, falling
// back to the Host header for handlers invoked with a relative URI. OAuth
// discovery documents and the /mcp WWW-Authenticate challenge all build
// their URLs from this one shape.
//
// Behind a TLS-terminating reverse proxy the connection scheme is http even
// for https clients, which would advertise http:// origins the client cannot
// follow. When the proxy sets X-Forwarded-Proto (nginx:
// `proxy_set_header X-Forwarded-Proto $scheme;`) its first value wins;
// without the header (direct exposure) the connection scheme is kept — the
// header is only trusted when present, behind-proxy deployments only.
String requestOrigin(Request request) {
  final requested = request.requestedUri;
  final String origin;
  if (requested.hasScheme && requested.host.isNotEmpty) {
    origin = requested.origin;
  } else {
    final host = request.headers['host'];
    origin = host == null || host.isEmpty ? 'http://localhost' : 'http://$host';
  }
  final forwardedProto = request.headers['x-forwarded-proto'];
  if (forwardedProto == null || forwardedProto.isEmpty) {
    return origin;
  }
  final scheme = forwardedProto.split(',').first.trim().toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return origin;
  }
  final uri = Uri.parse(origin);
  return uri.scheme == scheme ? origin : uri.replace(scheme: scheme).origin;
}
