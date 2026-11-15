import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_scope.dart';
import 'package:dayspark/domain/records/writers/todo_writer.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

// These tests assert on layout, so real glyph metrics help — but the faces live
// in different places per host, and the Linux CI image has no CJK face at all.
// Load whichever candidate exists and carry on without one; a missing system
// font must not fail the whole file, which is what a bare Windows path did.
Future<void> _loadFont(String family, List<String> candidates) async {
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer),
        ),
      );
    await loader.load();
    return;
  }
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

Future<void> _desktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _settle(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    await _loadFont('Microsoft YaHei', [
      r'C:\Windows\Fonts\Deng.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ]);
    await _loadFont('Segoe UI', [
      r'C:\Windows\Fonts\segoeui.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ]);
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the dock shows three destinations and defaults to Today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(find.byKey(const ValueKey('mobile-tab-bar')), findsOneWidget);
    expect(_content(0), findsOneWidget);

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Calendar'), findsWidgets);
    expect(find.text('Tasks'), findsWidgets);
    // The AI destination is gone from the dock; capture lives in the page.
    expect(find.text('AI Assistant'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('respects saved calendar preference on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(_content(1), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('respects saved todos preference on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(_content(2), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('switching destinations moves the content', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(_content(0), findsOneWidget);

    // The dock is the last child of the body, so `.last` is its label.
    await tester.tap(find.text('Calendar').last);
    await _settle(tester);
    expect(_content(1), findsOneWidget);

    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    expect(_content(2), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the desktop bar switches destinations in place', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _desktop(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    // The wordmark is the desktop bar's identity; the dock must not exist.
    expect(find.text('DaySpark'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-tab-bar')), findsNothing);
    final origin = tester.getTopLeft(_content(0));

    await tester.tap(find.text('Tasks').first);
    await _settle(tester, 10);
    expect(_content(2), findsOneWidget);
    expect(tester.getTopLeft(_content(2)), origin);

    await tester.tap(find.text('Calendar').first);
    await _settle(tester, 10);
    expect(_content(1), findsOneWidget);
    expect(tester.getTopLeft(_content(1)), origin);

    await tester.tap(find.text('Today').first);
    await _settle(tester, 10);
    expect(_content(0), findsOneWidget);
    expect(tester.getTopLeft(_content(0)), origin);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('ticking a recurring series row asks which occurrence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _phone(tester);
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    final spec = RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(2026, 10, 1),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY;COUNT=40',
    );
    final seriesId = await RecordScope.run(
      db,
      (tx) => TodoWriter.create(
        db,
        tx,
        TodosCompanion.insert(
          calendarId: calId,
          summary: 'Daily standup',
          rrule: Value(spec.rule.canonical),
        ),
        recurrenceSpec: spec,
      ),
    );

    await tester.pumpWidget(_app(db));
    await _settle(tester);
    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    await tester.tap(find.text('By date'));
    await _settle(tester);
    await tester.tap(find.text('Unplanned').last);
    await _settle(tester);

    expect(find.text('Daily standup'), findsOneWidget);
    await tester.tap(find.byType(DsCheck).first);
    await _settle(tester);

    // The writer refuses a series completion without an occurrence, so the
    // page asks for one instead of surfacing an error.
    expect(find.byType(Dialog), findsOneWidget);
    final series = await (db.select(db.todos)
          ..where((row) => row.id.equals(seriesId)))
        .getSingle();
    expect(series.status, 'NEEDS-ACTION');
    expect(await db.select(db.taskInstanceStates).get(), isEmpty);

    await _unmount(tester);
  });

  testWidgets('calendar and Todo by date share one browsed day', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _phone(tester);
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
      listen: false,
    );
    final now = DateTime.now();
    // A day in the same month as the month grid opens on, but not today, so
    // "today's page ignored it" is observable.
    final target = DateTime(now.year, now.month, now.day == 10 ? 11 : 10);

    await tester.tap(find.text('Calendar').last);
    await _settle(tester);
    await tester.tap(find.byTooltip('Month').first);
    await _settle(tester);
    await tester.tap(
      find.byKey(
        ValueKey('month-day-${target.year}-${target.month}-${target.day}'),
      ),
    );
    await _settle(tester);
    expect(container.read(viewedDateProvider).day, target.day);

    // The date the calendar picked is the date Todo · By date opens on.
    await tester.tap(find.text('Tasks').last);
    await _settle(tester);
    expect(container.read(viewedDateProvider).day, target.day);
    expect(
      find.textContaining(
        DateFormat.MMMd(
          Localizations.localeOf(tester.element(find.byType(HomePage)))
              .toString(),
        ).format(target),
      ),
      findsWidgets,
    );

    // Today answers to the clock, not to the browsed date.
    await tester.tap(find.text('Today').last);
    await _settle(tester);
    expect(container.read(viewedDateProvider).day, target.day);
    expect(
      find.textContaining(
        DateFormat.MMMMd(
          Localizations.localeOf(tester.element(find.byType(HomePage)))
              .toString(),
        ).format(now),
      ),
      findsWidgets,
    );

    await _unmount(tester);
  });

  testWidgets('one left origin per list, on Today and on Tasks', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _desktop(tester);
    final calId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    for (final title in ['Origin one', 'Origin two']) {
      await db
          .into(db.todos)
          .insert(TodosCompanion.insert(calendarId: calId, summary: title));
    }

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    void expectSingleOrigin() {
      final rows = find.byType(A2Row);
      expect(rows.evaluate().length, 2);
      final lefts = <double>[
        for (var i = 0; i < rows.evaluate().length; i++)
          tester.getTopLeft(rows.at(i)).dx,
      ];
      final spread = lefts.reduce((a, b) => a < b ? a : b);
      for (final left in lefts) {
        expect((left - spread).abs(), lessThanOrEqualTo(1));
      }
    }

    // Today shelves the two unplanned todos.
    expectSingleOrigin();

    await tester.tap(find.text('Tasks').first);
    await _settle(tester, 10);

    // Tasks opens on 按日期, which does not carry bare todos; switch to
    // 未安排 through the header's mode sheet.
    await tester.tap(find.text('By date'));
    await _settle(tester, 10);
    await tester.tap(find.text('Unplanned').last);
    await _settle(tester, 10);

    expectSingleOrigin();
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('desktop todo shows the browsed day and its plan bar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await _desktop(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(find.text('By date'), findsOneWidget);
    expect(find.byType(A2PlanBar), findsOneWidget);
    expect(find.text('Plan this day'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the day strip opens the month and year picker', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await _phone(tester);

    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(find.text('By date'), findsOneWidget);
    // Browsing today: the strip's first line is the day itself.
    await tester.tap(find.text('Today').first);
    await _settle(tester, 10);

    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.text('Return to Today'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('changing destination closes the detail pane', (tester) async {
    SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
    await _desktop(tester);
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
    await _settle(tester);

    await tester.tap(find.text('Pick up').first);
    await _settle(tester, 10);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(workspaceSelectionProvider), isNotNull);

    await tester.tap(find.text('Calendar').first);
    await _settle(tester, 10);

    expect(container.read(workspaceSelectionProvider), isNull);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the chrome splits exactly at the workspace breakpoint', (
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
      await _settle(tester);
      expect(
        find.text('DaySpark'),
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
