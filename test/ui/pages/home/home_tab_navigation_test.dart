import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';
import 'package:dayspark/ui/widgets/todo/todo_list_tile.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

Widget _app(AppDatabase db, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db), ...overrides],
    child: MaterialApp(
      theme: AppTheme.light().copyWith(
        textTheme: AppTheme.light().textTheme.apply(
          fontFamily: 'Microsoft YaHei',
        ),
      ),
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

  setUpAll(() async {
    await _loadFont('Microsoft YaHei', r'C:\Windows\Fonts\Deng.ttf');
    await _loadFont('Segoe UI', r'C:\Windows\Fonts\segoeui.ttf');
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'bottom navigation bar displays 4 projections and defaults to Today',
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
      expect(find.text('AI Assistant'), findsWidgets);

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
  testWidgets('desktop bar switches destinations without moving the content', (
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
    expect(find.byType(SparkTopBar), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-tab-bar')), findsNothing);
    final origin = tester.getTopLeft(_content(0));

    Finder barItem(String label) => find
        .descendant(of: find.byType(SparkTopBar), matching: find.text(label))
        .first;

    await tester.tap(barItem('Month'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_content(1), findsOneWidget);
    expect(tester.getTopLeft(_content(1)), origin);

    await tester.tap(barItem('Tasks'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_content(2), findsOneWidget);
    expect(tester.getTopLeft(_content(2)), origin);

    await tester.tap(barItem('Day'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_content(0), findsOneWidget);
    expect(tester.takeException(), isNull);
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
      final rows = find.descendant(
        of: _content(tab),
        matching: find.byType(TodoListTile),
      );
      if (rows.evaluate().length < 2) return;
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
          .descendant(of: find.byType(SparkTopBar), matching: find.text('Tasks'))
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
    expect(find.byType(TodoBacklogHead), findsOneWidget);
    expect(find.byKey(const ValueKey('date-strip-week')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TodoBacklogHead),
        matching: find.text('All Tasks'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TodoBacklogHead),
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

  testWidgets('changing destination closes the detail pane', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calId,
            summary: 'Pick up',
            dueDate: Value(DateTime.now()),
          ),
        );
    await tester.pumpWidget(_app(db));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Pick up').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(workspaceSelectionProvider), isNotNull);

    await tester.tap(
      find
          .descendant(of: find.byType(SparkTopBar), matching: find.text('Month'))
          .first,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(container.read(workspaceSelectionProvider), isNull);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the bar appears exactly at the workspace breakpoint', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    for (final (width, expectBar) in [
      (390.0, false),
      (759.0, false),
      (999.0, false),
      (1000.0, true),
      (1240.0, true),
      (1440.0, true),
    ]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_app(db));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.byType(SparkTopBar),
        expectBar ? findsOneWidget : findsNothing,
        reason: 'width $width',
      );
      expect(
        find.byKey(const ValueKey('mobile-tab-bar')),
        expectBar ? findsNothing : findsOneWidget,
        reason: 'width $width',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
      await _unmount(tester);
    }
  });
}
