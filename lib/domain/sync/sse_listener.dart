import 'dart:async';
import 'dart:math';

/// Keeps one SSE connection alive: parses `{"cursor":N}` signals from the
/// client's cursor stream, forwards them, and reconnects with 1s → 60s
/// backoff whenever the stream ends or errors.
class SseListener {
  SseListener({
    required Stream<int> Function() open,
    required void Function(int cursor) onCursor,
  }) : _open = open,
       _onCursor = onCursor;

  final Stream<int> Function() _open;
  final void Function(int cursor) _onCursor;

  StreamSubscription<int>? _sub;
  Timer? _reconnectTimer;
  bool _running = false;
  int _backoffSeconds = 1;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
  }

  void _connect() {
    if (!_running) return;
    late final StreamSubscription<int> sub;
    sub = _open().listen(
      (cursor) {
        _backoffSeconds = 1;
        _onCursor(cursor);
      },
      onError: (Object _) => _scheduleReconnect(sub),
      onDone: () => _scheduleReconnect(sub),
      cancelOnError: false,
    );
    _sub = sub;
  }

  void _scheduleReconnect(StreamSubscription<int> sub) {
    if (!_running) return;
    if (identical(_sub, sub)) _sub = null;
    unawaited(sub.cancel());
    _reconnectTimer?.cancel();
    final delay = _backoffSeconds;
    _backoffSeconds = min(backoffCap, _backoffSeconds * 2);
    _reconnectTimer = Timer(Duration(seconds: delay), _connect);
  }

  static const int backoffCap = 60;
}
