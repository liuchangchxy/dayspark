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
    final decoded = jsonDecode(await request.readAsString());
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
String requestOrigin(Request request) {
  final requested = request.requestedUri;
  if (requested.hasScheme && requested.host.isNotEmpty) {
    return requested.origin;
  }
  final host = request.headers['host'];
  return host == null || host.isEmpty ? 'http://localhost' : 'http://$host';
}
