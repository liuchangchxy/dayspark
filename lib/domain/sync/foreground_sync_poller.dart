import 'dart:async';

/// Foreground fallback rounds: some proxies leave the SSE stream lingering
/// without FIN (T4) so the client listener never errors or completes, no
/// reconnect fires, and cursor signals stop arriving even though the
/// server has changes. While the app is in the foreground, kick a round
/// every [interval] as a pull fallback (each tick is one push+pull HTTP —
/// acceptable per plan; the engine coalesces, so concurrent triggers
/// collapse into at most one queued round). paused/background stops it.
class ForegroundSyncPoller {
  ForegroundSyncPoller({
    required Future<void> Function() requestRound,
    this.interval = const Duration(seconds: 15),
  }) : _requestRound = requestRound;

  final Future<void> Function() _requestRound;
  final Duration interval;

  Timer? _timer;

  bool get isActive => _timer != null;

  /// Arms the cadence without an immediate round — cold start already
  /// rounds via engine.start().
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_requestRound()));
  }

  /// App resumed: round at once (catch the backgrounded gap), then the
  /// periodic fallback.
  void resumed() {
    start();
    unawaited(_requestRound());
  }

  void paused() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => paused();
}
