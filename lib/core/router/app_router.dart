import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/ui/pages/home/home_page.dart';
import 'package:calendar_todo_app/ui/pages/settings/settings_page.dart';
import 'package:calendar_todo_app/ui/pages/event/event_create_page.dart';
import 'package:calendar_todo_app/ui/pages/event/event_edit_page.dart';
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
    ],
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
