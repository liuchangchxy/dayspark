import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/ui/pages/home/home_page.dart';
import 'package:calendar_todo_app/ui/pages/settings/settings_page.dart';
import 'package:calendar_todo_app/ui/pages/event/event_create_page.dart';
import 'package:calendar_todo_app/ui/pages/event/event_edit_page.dart';
import 'package:calendar_todo_app/ui/pages/todo/todo_create_page.dart';
import 'package:calendar_todo_app/ui/pages/todo/todo_edit_page.dart';
import 'package:calendar_todo_app/ui/pages/search/search_page.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/event/new',
        name: 'eventCreate',
        builder: (context, state) {
          final start = state.uri.queryParameters['start'];
          final end = state.uri.queryParameters['end'];
          return EventCreatePage(
            initialStart: start != null
                ? DateTime.fromMillisecondsSinceEpoch(int.parse(start))
                : DateTime.now(),
            initialEnd: end != null
                ? DateTime.fromMillisecondsSinceEpoch(int.parse(end))
                : DateTime.now().add(const Duration(hours: 1)),
          );
        },
      ),
      GoRoute(
        path: '/event/edit',
        name: 'eventEdit',
        builder: (context, state) {
          final event = state.extra as CalendaEventAdapter;
          return EventEditPage(event: event);
        },
      ),
      GoRoute(
        path: '/todo/new',
        name: 'todoCreate',
        builder: (context, state) => const TodoCreatePage(),
      ),
      GoRoute(
        path: '/todo/edit',
        name: 'todoEdit',
        builder: (context, state) {
          final todo = state.extra as Todo;
          return TodoEditPage(todo: todo);
        },
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) => const SearchPage(),
      ),
    ],
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
