import 'package:flutter/foundation.dart';
import 'package:dayspark/core/router/app_router.dart';

/// Custom scheme for widget/external deep links. Path-level routing still
/// happens in go_router — this file only translates scheme URIs into
/// locations, because go_router matches paths, not schemes.
const String widgetDeepLinkScheme = 'dayspark';

/// quick-add lands on todo_create prefilling `source=widget` so the page
/// knows it was opened from a home screen widget.
const String quickAddLocation = '/todo/new?source=widget';

/// Maps a deep-link URI to a go_router location, or null when the URI is
/// not one we own. Accepts `dayspark://quick-add` (host form) and
/// `dayspark:///quick-add` (path form).
String? widgetDeepLinkLocation(Uri? uri) {
  if (uri == null || uri.scheme != widgetDeepLinkScheme) return null;
  if (uri.host == 'quick-add' || uri.path == '/quick-add') {
    return quickAddLocation;
  }
  return null;
}

/// Interactivity entry point T3's native widget buttons hit via
/// `HomeWidget.registerInteractivityCallback`. Navigation only — consuming
/// `pendingTaps` and enqueuing completes happens in the flush path, never
/// here, so a background tap cannot write the database from two places.
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  final location = widgetDeepLinkLocation(uri);
  if (location == null) {
    debugPrint('home_widget: ignored interactivity uri: $uri');
    return;
  }
  AppRouter.router.push(location);
}
