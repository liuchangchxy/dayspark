import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth.dart';
import '../db.dart';

class StreamHub {
  final Map<String, List<_SseConnection>> _byUser = {};

  int get totalConnections =>
      _byUser.values.fold(0, (total, list) => total + list.length);

  int connectionsFor(String userId) => _byUser[userId]?.length ?? 0;

  void broadcast(String userId, int seq) {
    final list = _byUser[userId];
    if (list == null) {
      return;
    }
    for (final connection in List<_SseConnection>.of(list)) {
      connection.sendCursor(seq);
    }
  }

  void _attach(_SseConnection connection) {
    (_byUser[connection.userId] ??= []).add(connection);
  }

  void _detach(_SseConnection connection) {
    final list = _byUser[connection.userId];
    if (list == null) {
      return;
    }
    list.remove(connection);
    if (list.isEmpty) {
      _byUser.remove(connection.userId);
    }
  }

  void closeAll() {
    final open = _byUser.values
        .expand((list) => List<_SseConnection>.of(list))
        .toList();
    for (final connection in open) {
      connection.dispose();
    }
    _byUser.clear();
  }
}

class _SseConnection {
  _SseConnection({
    required this.userId,
    required this.hub,
    required this.heartbeat,
  }) {
    _controller = StreamController<List<int>>(onCancel: dispose);
  }

  final String userId;
  final StreamHub hub;
  final Duration heartbeat;

  late final StreamController<List<int>> _controller;
  Timer? _heartbeatTimer;
  int? _lastCursor;
  bool _disposed = false;

  Stream<List<int>> get stream => _controller.stream;

  void startHeartbeat() {
    if (heartbeat <= Duration.zero) {
      return;
    }
    _heartbeatTimer = Timer.periodic(heartbeat, (_) => _add(': ping\n\n'));
  }

  void sendCursor(int seq) {
    // Signals are a strictly increasing head level; a racing initial head
    // read must never rewind a cursor the broadcaster already delivered.
    if (_lastCursor != null && seq <= _lastCursor!) {
      return;
    }
    _lastCursor = seq;
    _add('data: {"cursor":$seq}\n\n');
  }

  void _add(String chunk) {
    if (_disposed || _controller.isClosed) {
      return;
    }
    _controller.add(utf8.encode(chunk));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    hub._detach(this);
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

Future<int> _headSeq(AppDatabase db, String userId) async {
  final row = await (db.select(db.revisions)
        ..where((t) => t.userId.equals(userId)))
      .getSingleOrNull();
  return row?.seq ?? 0;
}

void registerStreamRoutes(
  Router router, {
  required Auth auth,
  required AppDatabase db,
  required StreamHub hub,
  Duration heartbeat = const Duration(seconds: 25),
}) {
  router.get('/sync/stream', auth.requireAuth((request, context) async {
    final userId = context.userId;
    final connection = _SseConnection(
      userId: userId,
      hub: hub,
      heartbeat: heartbeat,
    );
    // Attach before the head read so a push racing it still signals; the
    // monotonic sendCursor then folds head vs. broadcast into one stream.
    hub._attach(connection);
    connection.startHeartbeat();
    try {
      connection.sendCursor(await _headSeq(db, userId));
    } catch (_) {
      connection.dispose();
      rethrow;
    }
    return Response(
      200,
      body: connection.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
        // Tell nginx-family proxies not to buffer this stream, even with
        // default site config — buffered SSE would defeat invalidation.
        'x-accel-buffering': 'no',
      },
      // shelf_io buffers streamed responses by default; SSE frames must hit
      // the wire as they are produced.
      context: const {'shelf.io.buffer_output': false},
    );
  }));
}
