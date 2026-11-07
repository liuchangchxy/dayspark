import 'package:flutter/foundation.dart';
import 'package:dayspark/core/router/app_router.dart';

// Custom scheme for widget/external deep links. Path-level routing still
// happens in go_router — this file only translates scheme URIs into
// locations, because go_router matches paths, not schemes.
const String widgetDeepLinkScheme = 'dayspark';

const String quickAddLocation = '/quick-add';
const String todayLocation = '/?tab=0';
const String todosLocation = '/?tab=2';
const String calendarLocation = '/?tab=1';

String? widgetDeepLinkLocation(Uri? uri) {
  if (uri == null) return null;
  // Flutter's Android cold-start hook reports only the path + query for an
  // ACTION_VIEW launch (dayspark://open/todo?id=1 arrives as /todo?id=1),
  // so widget paths must also resolve without a scheme.
  if (uri.scheme.isEmpty) return _widgetPathLocation(uri);
  if (uri.scheme != widgetDeepLinkScheme) return null;
  if (uri.host == 'quick-add' || uri.path == '/quick-add') {
    return _quickAddLocation(uri);
  }
  if (uri.host != 'open') return null;
  return _widgetPathLocation(uri);
}

String? _quickAddLocation(Uri uri) {
  final date = _validDate(uri.queryParameters['date']);
  return date == null ? quickAddLocation : '$quickAddLocation?date=$date';
}

String? _widgetPathLocation(Uri uri) {
  final segments = uri.pathSegments;
  final query = uri.queryParameters;
  if (segments.length == 1 && segments.first == 'quick-add') {
    return _quickAddLocation(uri);
  }
  if (segments.length == 1 && segments.first == 'today') {
    return todayLocation;
  }
  if (segments.length == 1 && segments.first == 'action') {
    return todayLocation;
  }
  if (segments.length == 1 && segments.first == 'home') {
    return '/';
  }
  if (segments.length == 1 && segments.first == 'calendar') {
    final date = _validDate(query['date']);
    return date == null ? calendarLocation : '$calendarLocation&date=$date';
  }
  if (segments.length == 1 && segments.first == 'todos') {
    final view = _todoView(query['view']);
    return '$todosLocation&view=$view';
  }
  if (segments.length == 1 && segments.first == 'new-todo') {
    return _quickAddLocation(uri);
  }
  if (segments.length == 1 && segments.first == 'new-event') {
    final date = _validDate(query['date']);
    return date == null ? '/event/new' : '/event/new?date=$date';
  }
  if (segments.length == 1 && segments.first == 'todo') {
    final id = _positiveInt(query['id']);
    return id == null ? todosLocation : '/todo/detail?id=$id';
  }
  if (segments.length == 1 && segments.first == 'event') {
    final id = _positiveInt(query['id']);
    return id == null ? calendarLocation : '/event/detail?id=$id';
  }
  return null;
}

String _todoView(String? raw) =>
    raw == 'inbox' || raw == 'all' ? raw! : 'today';

String? _validDate(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final date = DateTime.tryParse(raw);
  return date == null ? null : raw;
}

String? _positiveInt(String? raw) {
  final value = raw == null ? null : int.tryParse(raw);
  return value != null && value > 0 ? '$value' : null;
}

// Interactivity entry point T3's native widget buttons hit via
// `HomeWidget.registerInteractivityCallback`. Navigation only — consuming
// `pendingTaps` and enqueuing completes happens in the flush path, never
// here, so a background tap cannot write the database from two places.
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  final location = widgetDeepLinkLocation(uri);
  if (location == null) {
    debugPrint('home_widget: ignored interactivity uri: $uri');
    return;
  }
  AppRouter.router.push(location);
}
