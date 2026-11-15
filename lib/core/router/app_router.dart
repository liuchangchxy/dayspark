import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/infrastructure/platform/home_widget_interactivity.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/event/event_detail_page.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/todo/todo_detail_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark/ui/pages/todo/quick_add_page.dart';
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

/// A page that floats over the one you were on instead of replacing it.
///
/// Quick add is a sheet, not a destination: an opaque route painted the app
/// away and left a card sitting in an empty window, so the page it covers has
/// to keep rendering underneath.
Page<void> _overlayPage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    opaque: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, page) => page,
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

class _DetailLoadingPage extends StatelessWidget {
  const _DetailLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const WorkspacePage(
      title: 'DaySpark',
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _TodoDetailLoader extends ConsumerWidget {
  const _TodoDetailLoader({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(liveTodoProvider(id));
    return async.when(
      loading: () => const _DetailLoadingPage(),
      error: (error, stack) => _MissingObjectPage(
        message: l?.missingTodoParam ?? 'This link did not carry a todo.',
      ),
      data: (todo) {
        if (todo == null) {
          return _MissingObjectPage(
            message: l?.missingTodoParam ?? 'This link did not carry a todo.',
          );
        }
        return TodoDetailPage(todo: todo);
      },
    );
  }
}

class _EventDetailLoader extends ConsumerWidget {
  const _EventDetailLoader({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(liveEventProvider(id));
    return async.when(
      loading: () => const _DetailLoadingPage(),
      error: (error, stack) => _MissingObjectPage(
        message: l?.missingEventParam ?? 'This link did not carry an event.',
      ),
      data: (event) {
        if (event == null) {
          return _MissingObjectPage(
            message:
                l?.missingEventParam ?? 'This link did not carry an event.',
          );
        }
        return EventDetailPage(event: event);
      },
    );
  }
}

String _initialLocationFromPlatform() {
  final raw = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  return widgetDeepLinkLocation(Uri.tryParse(raw)) ?? '/';
}

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: _initialLocationFromPlatform(),
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
        pageBuilder: (context, state) {
          final tabParam = state.uri.queryParameters['tab'];
          final dateParam = state.uri.queryParameters['date'];
          final viewParam = state.uri.queryParameters['view'];
          return _pageTransition(
            HomePage(
              initialTab: tabParam != null ? (int.tryParse(tabParam) ?? 0) : -1,
              initialDate: DateTime.tryParse(dateParam ?? ''),
              initialTodoView: viewParam,
            ),
          );
        },
      ),
      GoRoute(
        path: '/quick-add',
        name: 'quickAdd',
        pageBuilder: (context, state) {
          final date = DateTime.tryParse(
            state.uri.queryParameters['date'] ?? '',
          );
          return _overlayPage(
            QuickAddPage(
              contextDate: date == null
                  ? null
                  : DateTime(date.year, date.month, date.day),
            ),
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => WorkspaceScaffold(child: child),
        routes: [
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                _pageTransition(const SettingsPage()),
          ),
          GoRoute(
            path: '/event/new',
            name: 'eventCreate',
            pageBuilder: (context, state) {
              final start = state.uri.queryParameters['start'];
              final end = state.uri.queryParameters['end'];
              final date = DateTime.tryParse(
                state.uri.queryParameters['date'] ?? '',
              );
              final now = DateTime.now();
              final isToday =
                  date != null &&
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              final dateStart = date == null
                  ? null
                  : DateTime(
                      date.year,
                      date.month,
                      date.day,
                      isToday ? (now.hour + 1).clamp(0, 23) : 9,
                      0,
                    );
              return _pageTransition(
                EventFormPage(
                  initialStart: start != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          int.tryParse(start) ??
                              DateTime.now().millisecondsSinceEpoch,
                        )
                      : dateStart ?? DateTime.now(),
                  initialEnd: end != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          int.tryParse(end) ??
                              DateTime.now()
                                  .add(const Duration(hours: 1))
                                  .millisecondsSinceEpoch,
                        )
                      : (dateStart ?? DateTime.now()).add(
                          const Duration(hours: 1),
                        ),
                ),
              );
            },
          ),
          GoRoute(
            path: '/event/detail',
            name: 'eventDetail',
            pageBuilder: (context, state) {
              final event = state.extra;
              if (event is CalendaEventAdapter) {
                return _pageTransition(EventDetailPage(event: event));
              }
              final id = int.tryParse(state.uri.queryParameters['id'] ?? '');
              if (id != null && id > 0) {
                return _pageTransition(_EventDetailLoader(id: id));
              }
              return _pageTransition(
                _missingObjectPage(
                  AppLocalizations.of(context)?.missingEventParam ??
                      'This link did not carry an event.',
                ),
              );
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
              final due = state.uri.queryParameters['due'];
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
                  initialDueDate: parse(due),
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
              if (todo is Todo) {
                return _pageTransition(TodoDetailPage(todo: todo));
              }
              final id = int.tryParse(state.uri.queryParameters['id'] ?? '');
              if (id != null && id > 0) {
                return _pageTransition(_TodoDetailLoader(id: id));
              }
              return _pageTransition(
                _missingObjectPage(
                  AppLocalizations.of(context)?.missingTodoParam ??
                      'This link did not carry a todo.',
                ),
              );
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
            pageBuilder: (context, state) =>
                _pageTransition(const SearchPage()),
          ),
          GoRoute(
            path: '/tags',
            name: 'tags',
            pageBuilder: (context, state) => _pageTransition(const TagsPage()),
          ),
          GoRoute(
            path: '/calendars',
            name: 'calendars',
            pageBuilder: (context, state) =>
                _pageTransition(const CalendarsPage()),
          ),
          GoRoute(
            path: '/ai-chat',
            name: 'aiChat',
            pageBuilder: (context, state) =>
                _pageTransition(const AiChatPage()),
          ),
          GoRoute(
            path: '/about',
            name: 'about',
            pageBuilder: (context, state) => _pageTransition(const AboutPage()),
          ),
          GoRoute(
            path: '/trash',
            name: 'trash',
            pageBuilder: (context, state) => _pageTransition(const TrashPage()),
          ),
          GoRoute(
            path: '/feedback',
            name: 'feedback',
            pageBuilder: (context, state) =>
                _pageTransition(const FeedbackPage()),
          ),
        ],
      ),
    ],
  );
}
