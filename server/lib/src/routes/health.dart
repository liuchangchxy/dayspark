import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../http.dart';

void registerHealthRoutes(Router router) {
  Response health(Request request) =>
      jsonResponse(200, {'ok': true, 'version': serverVersion});

  router.get('/health', health);
  router.post('/health', health);
}
