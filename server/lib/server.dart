import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'src/auth.dart';
import 'src/config.dart';
import 'src/db.dart';
import 'src/http.dart';
import 'src/routes/auth.dart';
import 'src/routes/health.dart';

export 'package:shelf/shelf.dart' show Handler, Request, Response;

export 'src/auth.dart';
export 'src/config.dart';
export 'src/db.dart';
export 'src/http.dart';

class AppServer {
  AppServer(this.config, {AppDatabase? database})
    : db = database ?? AppDatabase(openDatabase(config.dbPath)) {
    auth = Auth(config, db);
  }

  final Config config;
  final AppDatabase db;
  late final Auth auth;

  // Notify seam for SSE (Task 4): Task 3 must call this after a push
  // transaction commits and has advanced the per-user seq. Null = inert.
  void Function(String userId, int seq)? onSeqAdvanced;

  late final Handler handler = _buildHandler();

  Handler _buildHandler() {
    final router = Router();
    registerHealthRoutes(router);
    registerAuthRoutes(router, db: db, auth: auth);
    return const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(catchApiErrors())
        .addHandler(router.call);
  }

  Future<HttpServer> serve() async {
    final server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      config.port,
    );
    stdout.writeln(
      'dayspark server listening on :${server.port} (db: ${config.dbPath})',
    );
    return server;
  }

  Future<void> close() => db.close();
}
