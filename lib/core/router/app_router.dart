import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/ui/pages/home/home_page.dart';
import 'package:calendar_todo_app/ui/pages/settings/settings_page.dart';

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
    ],
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
