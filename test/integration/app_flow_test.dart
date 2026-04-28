import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/pages/settings/settings_page.dart';
import 'package:dayspark/ui/pages/event/event_create_page.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';

GoRouter _createRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    GoRoute(
      path: '/event/new',
      builder: (_, __) => EventCreatePage(
        initialStart: DateTime(2026, 5, 1),
        initialEnd: DateTime(2026, 5, 1).add(const Duration(hours: 1)),
      ),
    ),
    GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
    GoRoute(path: '/tags', builder: (_, __) => const TagsPage()),
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

Future<void> _settle(WidgetTester tester) async {
  // pumpAndSettle times out with infinite animations from kalender etc.
  // Use fixed number of pumps instead
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.tap(find.text('Settings'));
  await _settle(tester);
}

void main() {
  testWidgets('home page renders', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.settings), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
  });

  testWidgets('FAB opens event create', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    expect(find.text('New Event'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
  });

  testWidgets('event create has form fields', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    expect(find.text('Starts at'), findsOneWidget);
    expect(find.text('Ends at'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Location'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('settings page renders all sections', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await _openSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('CalDAV Account'), findsOneWidget);
    expect(find.text('Manage Tags'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('MCP Server'), findsOneWidget);

    // Scroll down to reveal items below the fold
    await tester.scrollUntilVisible(
      find.text('Appearance'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Appearance'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('About'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Calendar Todo v0.1.0'), findsOneWidget);
  });

  testWidgets('tags page from settings', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await _openSettings(tester);

    await tester.tap(find.text('Manage Tags'));
    await _settle(tester);

    expect(find.byIcon(CupertinoIcons.add), findsWidgets);
  });

  testWidgets('CalDAV section visible on settings', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await _openSettings(tester);

    // CalDAV Account section should be visible regardless of config state
    expect(find.text('CalDAV Account'), findsOneWidget);
  });

  testWidgets('theme dialog opens', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await _openSettings(tester);

    // Scroll down to find the Appearance tile
    await tester.scrollUntilVisible(
      find.text('Appearance'),
      100,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Appearance'));
    await _settle(tester);

    // Theme dialog should show theme options
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('search page renders', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await tester.tap(find.byIcon(CupertinoIcons.search));
    await _settle(tester);

    expect(find.byType(TextField), findsWidgets);
  });
}
