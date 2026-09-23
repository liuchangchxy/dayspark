import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'src/auth.dart';
import 'src/config.dart';
import 'src/db.dart';
import 'src/http.dart';
import 'src/mcp/endpoint.dart';
import 'src/routes/auth.dart';
import 'src/routes/health.dart';
import 'src/routes/stream.dart';
import 'src/routes/sync.dart';

export 'package:shelf/shelf.dart' show Handler, Request, Response;

export 'src/auth.dart';
export 'src/config.dart';
export 'src/data/record_query.dart';
export 'src/data/record_writer.dart';
export 'src/data/rrule_window.dart';
export 'src/db.dart';
export 'src/http.dart';
export 'src/mcp/endpoint.dart';
export 'src/mcp/resources.dart';
export 'src/mcp/schemas.dart';
export 'src/mcp/tools.dart';
export 'src/sync/lww.dart';

class AppServer {
  AppServer(this.config, {AppDatabase? database})
    : db = database ?? AppDatabase(openDatabase(config.dbPath)) {
    auth = Auth(config, db);
    mcp = McpEndpoint(db: db, auth: auth, notifySeq: _notifySeq);
  }

  final Config config;
  final AppDatabase db;
  late final Auth auth;

  // MCP endpoint (POST /mcp). Exposed so Task 3 can inject the OAuth scope
  // gate: app.mcp.scopeChecker = myChecker before the first request.
  late final McpEndpoint mcp;

  // Per-user registry of open GET /sync/stream connections (SSE invalidation).
  final StreamHub streamHub = StreamHub();

  // Optional external observer seam for seq advances; the SSE streamHub is
  // always wired regardless of whether this is set.
  void Function(String userId, int seq)? onSeqAdvanced;

  void _notifySeq(String userId, int seq) {
    streamHub.broadcast(userId, seq);
    onSeqAdvanced?.call(userId, seq);
  }

  late final Handler handler = _buildHandler();

  Handler _buildHandler() {
    final router = Router();
    registerHealthRoutes(router);
    registerAuthRoutes(router, db: db, auth: auth);
    registerSyncRoutes(router, db: db, auth: auth, notifySeq: _notifySeq);
    registerStreamRoutes(
      router,
      db: db,
      auth: auth,
      hub: streamHub,
      heartbeat: config.sseHeartbeat,
    );
    router.post('/mcp', mcp.handle);
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

  Future<void> close() {
    streamHub.closeAll();
    return db.close();
  }
}
