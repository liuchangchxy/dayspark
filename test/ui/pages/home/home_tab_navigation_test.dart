import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/shell/workspace_sidebar.dart';

Widget _app(AppDatabase db) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const HomePage(),
    ),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'bottom navigation bar displays 3 projections and defaults to Action',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_app(db));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 3);
      // Index 0 is Action
      expect(navBar.selectedIndex, 0);

      // Verify labels
      expect(find.text('Action'), findsWidgets);
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('Todos'), findsWidgets);

      await _unmount(tester);
    },
  );

  testWidgets('respects saved calendar preference on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});

    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 1); // Calendar tab

    await _unmount(tester);
  });

  testWidgets('respects saved todos preference on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});

    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 2); // Todos tab

    await _unmount(tester);
  });

  testWidgets('switching tabs updates selected destination', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 0);

    // Tap Calendar destination
    await tester.tap(find.text('Calendar'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 1);

    // Tap Todos destination
    await tester.tap(find.text('Todos'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 2);

    await _unmount(tester);
  });
  testWidgets('desktop destinations keep the same content origin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(WorkspaceSidebar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('workspace-content-0')),
    );
    for (final entry in [(1, 'Calendar'), (2, 'Todos'), (0, 'Action')]) {
      await tester.tap(
        find.descendant(
          of: find.byType(WorkspaceSidebar),
          matching: find.text(entry.$2),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        tester.getTopLeft(
          find.byKey(ValueKey('workspace-content-${entry.$1}')),
        ),
        origin,
      );
      expect(tester.takeException(), isNull);
    }
    await _unmount(tester);
  });

  testWidgets('desktop list content keeps the shared 28dp left origin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<double> firstTextLeft(String tab, int index) async {
      await tester.tap(
        find.descendant(
          of: find.byType(WorkspaceSidebar),
          matching: find.text(tab),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final content = find.byKey(ValueKey('workspace-content-$index'));
      final texts = find.descendant(of: content, matching: find.byType(Text));
      return tester.getTopLeft(texts.first).dx;
    }

    // Action rows and the Todo section header are both plain list content:
    // neither should carry an extra inset relative to the other.
    final actionLeft = await firstTextLeft('Action', 0);
    final todoLeft = await firstTextLeft('Todos', 2);
    expect(
      (actionLeft - todoLeft).abs(),
      lessThanOrEqualTo(1),
      reason: 'Action=$actionLeft Todos=$todoLeft',
    );
    await _unmount(tester);
  });

  testWidgets('desktop todo swaps the week strip for the compact toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(TodoDesktopToolbar), findsOneWidget);
    expect(find.byKey(const ValueKey('date-strip-week')), findsNothing);
    // The filters themselves stay available.
    expect(
      find.descendant(
        of: find.byType(TodoDesktopToolbar),
        matching: find.text('All Tasks'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TodoDesktopToolbar),
        matching: find.text('To-do Box'),
      ),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('mobile todo keeps the touch week strip', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(TodoDesktopToolbar), findsNothing);
    expect(find.byKey(const ValueKey('date-strip-week')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
