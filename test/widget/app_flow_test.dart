import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/about/about_page.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

GoRouter _createRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    GoRoute(
      path: '/event/new',
      builder: (_, __) => EventFormPage(
        initialStart: DateTime(2026, 5, 1),
        initialEnd: DateTime(2026, 5, 1).add(const Duration(hours: 1)),
      ),
    ),
    GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
    GoRoute(path: '/about', builder: (_, __) => const AboutPage()),
    GoRoute(path: '/trash', builder: (_, __) => const TrashPage()),
    GoRoute(path: '/todo/new', builder: (_, __) => const TodoFormPage()),
  ],
);

Widget _createTestApp() => ProviderScope(
  child: MaterialApp.router(
    routerConfig: _createRouter(),
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
  ),
);

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_createTestApp());
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  // Pump enough frames for initial async operations to complete.
  // Avoid pumpAndSettle since Drift broadcast streams never complete.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(CupertinoIcons.settings));
  await _settle(tester);
}

void main() {
  testWidgets('home page renders', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const ValueKey('workspace-create')), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Calendar'), findsWidgets);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.byIcon(CupertinoIcons.settings), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
  });

  testWidgets('create entry on Today asks which object to create', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await _settle(tester);

    expect(find.text('New'), findsWidgets);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('New Event'), findsWidgets);

    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('todo-quick-create-title')),
      findsOneWidget,
    );
  });

  testWidgets('create entry opens event create on calendar tab', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Calendar'));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await _settle(tester);

    expect(find.text('New Event'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
  });

  testWidgets('event create has form fields', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Calendar'));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('workspace-create')));
    await _settle(tester);

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Location'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('settings page renders core sections', (tester) async {
    await _pumpApp(tester);

    await _openSettings(tester);

    expect(find.text('Settings'), findsWidgets);

    expect(find.text('General'), findsOneWidget);
  });

  testWidgets('theme options render in settings', (tester) async {
    await _pumpApp(tester);

    await _openSettings(tester);

    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('search page renders', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(CupertinoIcons.search));
    await _settle(tester);

    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('about page renders', (tester) async {
    await _pumpApp(tester);

    final router = GoRouter.of(tester.element(find.byType(HomePage)));
    router.go('/about');
    await _settle(tester);

    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('trash page renders', (tester) async {
    await _pumpApp(tester);

    final router = GoRouter.of(tester.element(find.byType(HomePage)));
    router.go('/trash');
    await _settle(tester);

    expect(find.byType(TrashPage), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
  });

  testWidgets('todo create page renders', (tester) async {
    await _pumpApp(tester);

    final router = GoRouter.of(tester.element(find.byType(HomePage)));
    router.go('/todo/new');
    await _settle(tester);

    expect(find.byType(TodoFormPage), findsOneWidget);
    expect(find.text('New Task'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
  });
}
