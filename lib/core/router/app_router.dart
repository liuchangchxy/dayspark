import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/event/event_create_page.dart';
import 'package:dayspark/ui/pages/event/event_edit_page.dart';
import 'package:dayspark/ui/pages/todo/todo_create_page.dart';
import 'package:dayspark/ui/pages/todo/todo_edit_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';
import 'package:dayspark/ui/pages/ai_chat/ai_chat_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';
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
    observers: [_NavObserver()],
    onException: (context, state, router) {
      debugPrint('[GoRouter] EXCEPTION at ${state.matchedLocation}');
      router.go('/');
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
                  ? DateTime.fromMillisecondsSinceEpoch(int.parse(start))
                  : DateTime.now(),
              initialEnd: end != null
                  ? DateTime.fromMillisecondsSinceEpoch(int.parse(end))
                  : DateTime.now().add(const Duration(hours: 1)),
            ),
          );
        },
      ),
      GoRoute(
        path: '/event/edit',
        name: 'eventEdit',
        pageBuilder: (context, state) {
          final event = state.extra as CalendaEventAdapter;
          return _fadeTransition(EventEditPage(event: event));
        },
      ),
      GoRoute(
        path: '/todo/new',
        name: 'todoCreate',
        pageBuilder: (context, state) =>
            _fadeTransition(const TodoCreatePage()),
      ),
      GoRoute(
        path: '/todo/edit',
        name: 'todoEdit',
        pageBuilder: (context, state) {
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
        path: '/ai-chat',
        name: 'aiChat',
        builder: (context, state) => const AiChatPage(),
      ),
      GoRoute(
        path: '/trash',
        name: 'trash',
        builder: (context, state) => const TrashPage(),
      ),
    ],
  );
}
