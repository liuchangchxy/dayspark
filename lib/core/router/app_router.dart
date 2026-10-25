import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/infrastructure/platform/home_widget_interactivity.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark/ui/pages/calendar/calendars_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';
import 'package:dayspark/ui/pages/ai_chat/ai_chat_page.dart';
import 'package:dayspark/ui/pages/about/about_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';
import 'package:dayspark/ui/pages/feedback/feedback_page.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

Page<void> _pageTransition(Widget child) {
  return NoTransitionPage(child: child);
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

/// Shown when a detail route is opened without its object — happens only on
/// deep links, since every in-app navigation passes `extra`.
Widget _missingObjectPage(String message) {
  return _MissingObjectPage(message: message);
}

class _MissingObjectPage extends StatelessWidget {
  const _MissingObjectPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return WorkspacePage(
      title: l?.navigationError ?? 'Navigation Error',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 28,
                color: context.semantic.textTertiary,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => GoRouter.maybeOf(context)?.go('/'),
                child: Text(l?.returnToHome ?? 'Return to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    observers: [if (!kReleaseMode) _NavObserver()],
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
        debugPrint(
          '[GoRouter] ERROR at ${state.matchedLocation}: ${state.error}',
        );
      }
      final l = AppLocalizations.of(context);
      return WorkspacePage(
        title: l?.navigationError ?? 'Navigation Error',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l?.pageNotFound(state.uri.toString()) ??
                      'Page not found or failed to load: ${state.uri}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: Text(l?.returnToHome ?? 'Return to Home'),
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
      // Every other destination nests inside the workspace shell, so the
      // desktop rail persists across the whole app instead of only on Home.
      ShellRoute(
        builder: (context, state, child) => WorkspaceScaffold(child: child),
        routes: [
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
              return _pageTransition(
                EventFormPage(
                  initialStart: start != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          int.tryParse(start) ??
                              DateTime.now().millisecondsSinceEpoch,
                        )
                      : DateTime.now(),
                  initialEnd: end != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          int.tryParse(end) ??
                              DateTime.now()
                                  .add(const Duration(hours: 1))
                                  .millisecondsSinceEpoch,
                        )
                      : DateTime.now().add(const Duration(hours: 1)),
                ),
              );
            },
          ),
          GoRoute(
            path: '/event/detail',
            name: 'eventDetail',
            pageBuilder: (context, state) {
              final event = state.extra;
              if (event is! CalendaEventAdapter) {
                return _pageTransition(
                  _missingObjectPage(
                    AppLocalizations.of(context)?.missingEventParam ??
                        'This link did not carry an event.',
                  ),
                );
              }
              return _pageTransition(EventDetailPage(event: event));
            },
          ),
          GoRoute(
            path: '/event/edit',
            name: 'eventEdit',
            pageBuilder: (context, state) {
              final event = state.extra;
              if (event is! CalendaEventAdapter) {
                return _pageTransition(
                  _missingObjectPage(
                    AppLocalizations.of(context)?.missingEventParam ??
                        'This link did not carry an event.',
                  ),
                );
              }
              return _pageTransition(EventFormPage(event: event));
            },
          ),
          GoRoute(
            path: '/todo/new',
            name: 'todoCreate',
            pageBuilder: (context, state) {
              final parentIdParam = state.uri.queryParameters['parentId'];
              final parentId = parentIdParam != null
                  ? int.tryParse(parentIdParam)
                  : null;
              final start = state.uri.queryParameters['start'];
              final end = state.uri.queryParameters['end'];
              DateTime? parse(String? value) => value == null
                  ? null
                  : DateTime.tryParse(value) ??
                        DateTime.fromMillisecondsSinceEpoch(
                          int.tryParse(value) ?? 0,
                        );
              return _pageTransition(
                TodoFormPage(
                  parentId: parentId,
                  source: state.uri.queryParameters['source'],
                  initialExecutionStart: parse(start),
                  initialExecutionEnd: parse(end),
                ),
              );
            },
          ),
          GoRoute(
            path: '/todo/detail',
            name: 'todoDetail',
            pageBuilder: (context, state) {
              final todo = state.extra;
              if (todo is! Todo) {
                return _pageTransition(
                  _missingObjectPage(
                    AppLocalizations.of(context)?.missingTodoParam ??
                        'This link did not carry a todo.',
                  ),
                );
              }
              return _pageTransition(TodoDetailPage(todo: todo));
            },
          ),
          GoRoute(
            path: '/todo/edit',
            name: 'todoEdit',
            pageBuilder: (context, state) {
              final todo = state.extra;
              if (todo is! Todo) {
                return _pageTransition(
                  _missingObjectPage(
                    AppLocalizations.of(context)?.missingTodoParam ??
                        'This link did not carry a todo.',
                  ),
                );
              }
              return _pageTransition(TodoFormPage(todo: todo));
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
      ),
    ],
  );
}
