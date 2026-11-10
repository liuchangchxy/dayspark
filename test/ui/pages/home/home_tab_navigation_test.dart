import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/ui/shell/workspace_sidebar.dart';

Widget _app(AppDatabase db, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db), ...overrides],
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

Finder _content(int tab) => find.byKey(ValueKey('workspace-content-$tab'));

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
    'bottom navigation bar displays 3 projections and defaults to Today',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _phone(tester);

      await tester.pumpWidget(_app(db));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const ValueKey('mobile-tab-bar')), findsOneWidget);
      expect(_content(0), findsOneWidget);

      // Verify labels
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('Tasks'), findsWidgets);

      await _unmount(tester);
    },
  );

  testWidgets('respects saved calendar preference on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_content(1), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('respects saved todos preference on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_content(2), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('switching tabs updates selected destination', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_content(0), findsOneWidget);

    // Tap Calendar destination
    await tester.tap(find.text('Calendar').last);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_content(1), findsOneWidget);

    // Tap Todos destination
    await tester.tap(find.text('Tasks').last);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_content(2), findsOneWidget);

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
    expect(find.byKey(const ValueKey('mobile-tab-bar')), findsNothing);
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('workspace-content-0')),
    );
    for (final entry in [(1, 'Calendar'), (2, 'Tasks'), (0, 'Today')]) {
      await tester.tap(
        find
            .descendant(
              of: find.byType(WorkspaceSidebar),
              matching: find.text(entry.$2),
            )
            .first,
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

  testWidgets('desktop list rows keep one left origin per destination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    for (final title in ['Origin one', 'Origin two']) {
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calId,
              summary: title,
              dueDate: Value(DateTime.now()),
            ),
          );
    }
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    void expectSingleOrigin(int tab) {
      final content = find.byKey(ValueKey('workspace-content-$tab'));
      final rows = find.descendant(
        of: content,
        matching: find.byType(TodoListTile),
      );
      expect(rows, findsWidgets);
      final lefts = <double>[
        for (var i = 0; i < rows.evaluate().length; i++)
          tester.getTopLeft(rows.at(i)).dx,
      ];
      final spread = lefts.reduce((a, b) => a < b ? a : b);
      for (final left in lefts) {
        expect((left - spread).abs(), lessThanOrEqualTo(1));
      }
    }

    expectSingleOrigin(0);
    await tester.tap(
      find
          .descendant(
            of: find.byType(WorkspaceSidebar),
            matching: find.text('Tasks'),
          )
          .first,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expectSingleOrigin(2);
    await _unmount(tester);
  });

  testWidgets('desktop todo keeps its day navigation in the toolbar', (
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
    // Moving to another day is not a mobile-only need: the same strip is
    // rendered under the compact toolbar rather than dropped.
    expect(find.byKey(const ValueKey('date-strip-week')), findsOneWidget);
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
        matching: find.text('Unplanned'),
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

  /// The sidebar row alone carries the selection colour, so reading the
  /// nearest Material above the label says whether that row is highlighted.
  Color? sidebarRowColor(WidgetTester tester, String label) {
    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byType(WorkspaceSidebar),
              matching: find.text(label),
            ),
            matching: find.byType(Material),
          )
          .first,
    );
    return material.color;
  }

  testWidgets('sidebar highlights the primary Today destination', (
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
    expect(sidebarRowColor(tester, 'Today'), AppColors.lightSurfaceSecondary);
    await _unmount(tester);
  });

  testWidgets('sidebar shows Today once and not under Todos', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.descendant(
        of: find.byType(WorkspaceSidebar),
        matching: find.text('Today'),
      ),
      findsOneWidget,
    );
    expect(sidebarRowColor(tester, 'Today'), isNot(AppColors.lightSurfaceSecondary));
    await _unmount(tester);
  });

  testWidgets('the rail appears exactly at the workspace breakpoint', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    for (final (width, expectRail) in [
      (390.0, false),
      (759.0, false),
      (768.0, true),
      (999.0, true),
      (1000.0, true),
      (1440.0, true),
    ]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_app(db));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.byType(WorkspaceSidebar),
        expectRail ? findsOneWidget : findsNothing,
        reason: 'width $width',
      );
      expect(
        find.byKey(const ValueKey('mobile-tab-bar')),
        expectRail ? findsNothing : findsOneWidget,
        reason: 'width $width',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
      await _unmount(tester);
    }
  });
}
