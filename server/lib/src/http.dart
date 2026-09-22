import 'dart:convert';

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

Middleware catchApiErrors() {
  return (inner) => (request) async {
    try {
      return await inner(request);
    } on ApiException catch (e) {
      return jsonError(e.status, e.code, e.message);
    }
  };
}
