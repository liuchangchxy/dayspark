import 'dart:async';

/// Decides *when* the home-widget snapshot may be rebuilt.
///
/// The record bus publishes the instant a write commits, which is exactly when
/// the user's next keystroke arrives. Rebuilding the snapshot costs tens of
/// milliseconds on the UI isolate (projection queries + JSON) and a burst of
/// platform-channel calls, and with a widget pinned the Android main thread
/// then re-parses it and rebuilds RemoteViews. All of that competes with IME
/// delivery, so a create-heavy session could starve the keyboard.
///
/// Policy: coalesce a burst into one run, hold it while a text field owns
/// focus, and never hold longer than [maxDeferral] so widgets cannot go stale.
class WidgetRefreshScheduler {
  WidgetRefreshScheduler({
    required Future<void> Function() onRun,
    required bool Function() isEditing,
    this.debounce = const Duration(milliseconds: 400),
    this.maxDeferral = const Duration(seconds: 4),
  }) : _onRun = onRun,
       _isEditing = isEditing;

  final Future<void> Function() _onRun;
  final bool Function() _isEditing;
  final Duration debounce;
  final Duration maxDeferral;

  Timer? _debounceTimer;
  Timer? _maxTimer;
  bool _requested = false;
  bool _running = false;
  bool _disposed = false;

  bool get hasPendingWork => _requested;

  void request() {
    if (_disposed) return;
    _requested = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _onDebounceElapsed);
    _maxTimer ??= Timer(maxDeferral, _run);
  }

  void _onDebounceElapsed() {
    if (_isEditing()) return;
    _run();
  }

  void _run() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _maxTimer?.cancel();
    _maxTimer = null;
    if (!_requested) return;
    if (_running) {
      _requested = true;
      _debounceTimer = Timer(debounce, _onDebounceElapsed);
      return;
    }
    _requested = false;
    _running = true;
    unawaited(
      _onRun().catchError((Object e) {
        // A failed snapshot must not wedge the scheduler.
      }).whenComplete(() {
        _running = false;
        if (_requested && !_disposed) {
          _debounceTimer = Timer(debounce, _onDebounceElapsed);
        }
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _maxTimer?.cancel();
  }
}
