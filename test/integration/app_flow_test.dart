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
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Drain any pending timers (e.g. stream timeouts).
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(CupertinoIcons.settings));
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
    expect(find.byIcon(CupertinoIcons.settings), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
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

  testWidgets('settings page renders core sections', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await _openSettings(tester);

    expect(find.text('Settings'), findsOneWidget);

    // Scroll down to find Appearance
    final gesture = await tester.startGesture(Offset.zero);
    for (int i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
    }
    await gesture.up();
    await _settle(tester);

    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('theme dialog opens', (tester) async {
    await tester.pumpWidget(_createTestApp());
    await _settle(tester);

    await _openSettings(tester);

    await tester.scrollUntilVisible(
      find.text('Appearance'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Appearance'));
    await _settle(tester);

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
