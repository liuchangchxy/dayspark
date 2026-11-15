// A″ screen capture harness. Not part of the suite: run it by path, then read
// the PNGs under build/a2-shots and compare them with the final design.
//
//   flutter test tool/shots/a2_shots_test.dart
//
// It writes whole screens, not component crops: the point is to judge the page
// against design/opendesign/a2-visual-rebase-2026-11-15/ref.
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
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/home/home_page.dart';

final _shotKey = GlobalKey();
final _now = DateTime(2026, 11, 15, 15, 0);

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

ThemeData _harnessTheme() {
  const family = 'Microsoft YaHei';
  final base = AppTheme.light();
  // The theme carries fontFamilyFallback only; on a device the platform face
  // fills in, in the harness nothing does. Buttons resolve their own style
  // before the inherited one, so the family has to be named there too — a
  // fallback list alone does not reach a button label.
  ButtonStyle named(ButtonStyle? style) {
    final resolved = style?.textStyle?.resolve({}) ?? const TextStyle();
    return (style ?? const ButtonStyle()).copyWith(
      textStyle: WidgetStatePropertyAll(resolved.copyWith(fontFamily: family)),
    );
  }

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    filledButtonTheme: FilledButtonThemeData(
      style: named(base.filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: named(base.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: named(base.outlinedButtonTheme.style),
    ),
  );
}

Widget _app(AppDatabase db, HomePage home) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: RepaintBoundary(
    key: _shotKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      // The harness has no platform face, and a ButtonStyle that names no
      // family falls back to the test binding's box face rather than to the
      // theme's. Bind the theme's family into the button styles too, so what
      // is captured is the layout, not a wall of rectangles.
      theme: _harnessTheme(),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: home,
    ),
  ),
);

Future<void> _settle(WidgetTester tester, [int frames = 25]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _teardown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 40));
  await db.close();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.pump();
  await expectLater(
    find.byKey(_shotKey),
    matchesGoldenFile('../../build/a2-shots/$name.png'),
  );
  // ignore: avoid_print
  print('shot build/a2-shots/$name.png');
}

Future<AppDatabase> _seed({bool empty = false, bool dense = false}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final personal = await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(name: 'Personal', color: const Value('#7D9B6A')),
      );
  final work = await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(name: 'Work', color: const Value('#5F7183')),
      );
  if (empty) return db;

  final day = DateTime(_now.year, _now.month, _now.day);
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          calendarId: personal,
          summary: 'Dentist · Mingzhou',
          startDt: DateTime(day.year, day.month, day.day, 14, 30),
          endDt: DateTime(day.year, day.month, day.day, 15, 15),
          isAllDay: const Value(false),
        ),
      );
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          calendarId: work,
          summary: 'Design sync',
          startDt: DateTime(day.year, day.month, day.day, 16),
          endDt: DateTime(day.year, day.month, day.day, 16, 45),
          isAllDay: const Value(false),
        ),
      );

  final allocated = await db
      .into(db.todos)
      .insert(
        TodosCompanion.insert(
          calendarId: work,
          summary: '整理周会纪要并发群',
          dueDate: Value(DateTime(day.year, day.month, day.day, 18)),
          sortOrder: const Value(0),
        ),
      );
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  await container.read(createTaskAllocationProvider)(
    todoId: allocated,
    startAt: DateTime(day.year, day.month, day.day, 16),
    endAt: DateTime(day.year, day.month, day.day, 17),
  );
  container.dispose();

  await db
      .into(db.todos)
      .insert(
        TodosCompanion.insert(
          calendarId: work,
          summary: '提交周报给林总（含下周排期与风险项，以及本季度招聘计划）',
          dueDate: Value(DateTime(day.year, day.month, day.day, 18)),
          sortOrder: const Value(1),
        ),
      );
  await db
      .into(db.todos)
      .insert(
        TodosCompanion.insert(
          calendarId: personal,
          summary: '交 10 月报销单',
          dueDate: Value(DateTime(day.year, day.month, day.day, 12)),
          status: const Value('COMPLETED'),
          completedAt: Value(DateTime(day.year, day.month, day.day, 12, 30)),
          percentComplete: const Value(100),
          sortOrder: const Value(2),
        ),
      );
  await db
      .into(db.todos)
      .insert(
        TodosCompanion.insert(
          calendarId: work,
          summary: 'Pay the invoice',
          dueDate: Value(DateTime(day.year, day.month, day.day - 4, 10)),
          sortOrder: const Value(3),
        ),
      );

  final unplanned = dense
      ? List.generate(
          12,
          (index) => 'Backlog item ${index + 1}',
        )
      : ['续签宽带', '给爸妈打电话', 'Read the design notes'];
  for (var index = 0; index < unplanned.length; index++) {
    await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: personal,
            summary: unplanned[index],
            sortOrder: Value(10 + index),
          ),
        );
  }
  if (dense) {
    for (var index = 0; index < 6; index++) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: index.isEven ? personal : work,
              summary: 'Meeting block ${index + 1}',
              startDt: DateTime(day.year, day.month, day.day, 9 + index),
              endDt: DateTime(day.year, day.month, day.day, 9 + index, 45),
              isAllDay: const Value(false),
            ),
          );
    }
  }
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Without the icon face every glyph in the UI renders as a box, which
    // would make each page look broken for reasons that are not the page.
    final icons = File(
      '${Platform.environment['LOCALAPPDATA'] ?? ''}'
      '/Pub/Cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
    );
    if (icons.existsSync()) {
      // IconData carries the package prefix, so that is the family the
      // renderer looks up; the bare name is registered too for widgets that
      // spell the family out themselves.
      await _loadFont('packages/cupertino_icons/CupertinoIcons', [icons.path]);
      await _loadFont('CupertinoIcons', [icons.path]);
    }
    await _loadFont('Microsoft YaHei', [
      r'C:\Windows\Fonts\Deng.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ]);
    // Flutter's test default family is the box-drawing Ahem face, and a style
    // that names no family (every AppTypography style) resolves to it. Bind a
    // real face to the default names so the capture shows the app, not boxes.
    for (final family in ['Roboto', '.SF UI Text', 'Segoe UI', 'FlutterTest']) {
      await _loadFont(family, [
        r'C:\Windows\Fonts\segoeui.ttf',
        '/System/Library/Fonts/Helvetica.ttc',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      ]);
    }
    await _loadFont('Segoe UI', [
      r'C:\Windows\Fonts\segoeui.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ]);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> boot(
    WidgetTester tester,
    AppDatabase db, {
    int tab = 0,
    void Function(ProviderContainer)? prepare,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    prepare?.call(container);
    container.dispose();
    await tester.pumpWidget(
      _app(db, HomePage(initialTab: tab, clock: () => _now)),
    );
    await _settle(tester);
  }


  testWidgets('phone: today', (tester) async {
    phone(tester);
    final db = await _seed();
    await boot(tester, db, tab: 0);
    await _shoot(tester, 'p-today');
    await _teardown(tester, db);
  });

  testWidgets('phone: today with the keyboard up', (tester) async {
    phone(tester);
    final db = await _seed();
    await boot(tester, db, tab: 0);
    await tester.tap(find.byKey(const ValueKey('today-capture-field')));
    await _settle(tester, 6);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await _settle(tester, 8);
    await _shoot(tester, 'p-today-keyboard');
    tester.view.resetViewInsets();
    await tester.pump(const Duration(milliseconds: 40));
    await _teardown(tester, db);
  });

  testWidgets('phone: an empty today', (tester) async {
    phone(tester);
    final db = await _seed(empty: true);
    await boot(tester, db, tab: 0);
    await _shoot(tester, 'p-today-empty');
    await _teardown(tester, db);
  });

  testWidgets('phone: a dense today', (tester) async {
    phone(tester);
    final db = await _seed(dense: true);
    await boot(tester, db, tab: 0);
    await _shoot(tester, 'p-today-dense');
    await _teardown(tester, db);
  });

  testWidgets('phone: todo modes', (tester) async {
    phone(tester);
    final db = await _seed();
    await boot(tester, db, tab: 2);
    await _shoot(tester, 'p-todo-date');

    await tester.tap(find.byKey(const ValueKey('todos-mode-switch')));
    await _settle(tester, 6);
    await tester.tap(find.text('Unplanned').last);
    await _settle(tester, 8);
    await _shoot(tester, 'p-todo-unplanned');

    await tester.tap(find.byKey(const ValueKey('todos-mode-switch')));
    await _settle(tester, 6);
    await tester.tap(find.text('All Tasks').last);
    await _settle(tester, 8);
    await _shoot(tester, 'p-todo-all');
    await _teardown(tester, db);
  });

  testWidgets('phone: composer in three promises', (tester) async {
    phone(tester);
    final db = await _seed();
    await boot(tester, db, tab: 2);

    await tester.tap(find.text('Plan this day'));
    await _settle(tester, 8);
    await _shoot(tester, 'p-composer-empty');

    await tester.enterText(
      find.byKey(const ValueKey('a2-composer-title')),
      'Write the retro',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('a2-composer-plan')));
    await _settle(tester, 4);
    await tester.tap(find.text('16:00–17:00'));
    await _settle(tester, 4);
    await _shoot(tester, 'p-composer-planned');

    await tester.tap(find.byKey(const ValueKey('a2-composer-due')));
    await _settle(tester, 4);
    await _shoot(tester, 'p-composer-due');
    await _teardown(tester, db);
  });

  testWidgets('phone: calendar week, month and day', (tester) async {
    phone(tester);
    final db = await _seed();
    await boot(tester, db, tab: 1);
    await _shoot(tester, 'p-calendar-week');

    await tester.tap(find.byTooltip('Day').first);
    await _settle(tester, 10);
    await _shoot(tester, 'p-calendar-day');

    await tester.tap(find.byTooltip('Month').first);
    await _settle(tester, 10);
    await _shoot(tester, 'p-calendar-month');
    await _teardown(tester, db);
  });

  testWidgets('desktop: today', (tester) async {
    desktop(tester);
    final db = await _seed();
    await boot(tester, db, tab: 0);
    await _shoot(tester, 'd-today');
    await _teardown(tester, db);
  });

  testWidgets('desktop: tasks', (tester) async {
    desktop(tester);
    final db = await _seed();
    await boot(tester, db, tab: 2);
    await _shoot(tester, 'd-todo');
    await _teardown(tester, db);
  });

  testWidgets('desktop: month grid', (tester) async {
    desktop(tester);
    final db = await _seed();
    await boot(tester, db, tab: 1);
    await tester.tap(find.text('Month').last);
    await _settle(tester, 12);
    await _shoot(tester, 'd-calendar-month');
    await _teardown(tester, db);
  });
}
