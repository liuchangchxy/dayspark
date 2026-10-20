import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/infrastructure/platform/home_widget_interactivity.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/event/event_create_page.dart';
import 'package:dayspark/ui/pages/event/event_edit_page.dart';
import 'package:dayspark/ui/pages/todo/todo_create_page.dart';
import 'package:dayspark/ui/pages/todo/todo_edit_page.dart';
import 'package:dayspark/ui/pages/calendar/calendars_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';
import 'package:dayspark/ui/pages/ai_chat/ai_chat_page.dart';
import 'package:dayspark/ui/pages/about/about_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';
import 'package:dayspark/ui/pages/feedback/feedback_page.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';

CustomTransitionPage<void> _fadeTransition(Widget child) {
  return CustomTransitionPage(
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _NavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[GoRouter] PUSH: ${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[GoRouter] POP: ${route.settings.name}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    debugPrint(
      '[GoRouter] REPLACE: ${oldRoute?.settings.name} → ${newRoute?.settings.name}',
    );
  }
}

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    observers: [
      if (!kReleaseMode) _NavObserver(),
    ],
    // Engine deep links (widget quick-add on Android/iOS/macOS) arrive as
    // raw scheme URIs (dayspark://quick-add) before any path match exists;
    // go_router only routes paths, so every scheme URI is funnelled through
    // widgetDeepLinkLocation — the single scheme→path translation point.
    redirect: (context, state) {
      final location = widgetDeepLinkLocation(state.uri);
      if (location != null && location != state.uri.toString()) {
        return location;
      }
      return null;
    },
    errorBuilder: (context, state) {
      if (!kReleaseMode) {
        debugPrint('[GoRouter] ERROR at ${state.matchedLocation}: ${state.error}');
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Page not found or failed to load: ${state.uri}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Return to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) {
          final tabParam = state.uri.queryParameters['tab'];
          return HomePage(
            initialTab: tabParam != null ? (int.tryParse(tabParam) ?? 0) : -1,
          );
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/event/new',
        name: 'eventCreate',
        pageBuilder: (context, state) {
          final start = state.uri.queryParameters['start'];
          final end = state.uri.queryParameters['end'];
          return _fadeTransition(
            EventCreatePage(
              initialStart: start != null
                  ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(start) ?? DateTime.now().millisecondsSinceEpoch)
                  : DateTime.now(),
              initialEnd: end != null
                  ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(end) ?? DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch)
                  : DateTime.now().add(const Duration(hours: 1)),
            ),
          );
        },
      ),
      GoRoute(
        path: '/event/edit',
        name: 'eventEdit',
        pageBuilder: (context, state) {
          if (state.extra is! CalendaEventAdapter) {
            return _fadeTransition(
              Scaffold(
                appBar: AppBar(title: const Text('Event Not Found')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                        const SizedBox(height: 16),
                        const Text(
                          'Missing event parameter to edit.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Return to Home'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final event = state.extra as CalendaEventAdapter;
          return _fadeTransition(EventEditPage(event: event));
        },
      ),
      GoRoute(
        path: '/todo/new',
        name: 'todoCreate',
        pageBuilder: (context, state) {
          final parentIdParam = state.uri.queryParameters['parentId'];
          final parentId = parentIdParam != null ? int.tryParse(parentIdParam) : null;
          return _fadeTransition(
            TodoCreatePage(
              parentId: parentId,
              source: state.uri.queryParameters['source'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/todo/edit',
        name: 'todoEdit',
        pageBuilder: (context, state) {
          if (state.extra is! Todo) {
            return _fadeTransition(
              Scaffold(
                appBar: AppBar(title: const Text('Todo Not Found')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
                        const SizedBox(height: 16),
                        const Text(
                          'Missing todo parameter to edit.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Return to Home'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final todo = state.extra as Todo;
          return _fadeTransition(TodoEditPage(todo: todo));
        },
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: '/tags',
        name: 'tags',
        builder: (context, state) => const TagsPage(),
      ),
      GoRoute(
        path: '/calendars',
        name: 'calendars',
        builder: (context, state) => const CalendarsPage(),
      ),
      GoRoute(
        path: '/ai-chat',
        name: 'aiChat',
        builder: (context, state) => const AiChatPage(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: '/trash',
        name: 'trash',
        builder: (context, state) => const TrashPage(),
      ),
      GoRoute(
        path: '/feedback',
        name: 'feedback',
        builder: (context, state) => const FeedbackPage(),
      ),
    ],
  );
}
