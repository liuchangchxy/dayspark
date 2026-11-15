import 'dart:convert';
import 'dart:ui' show FramePhase;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/core/router/app_router.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/home_widget_provider.dart';
import 'package:dayspark/main.dart' show DaySparkApp;

/// Input-cost probe, run in profile mode:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/input_latency_test.dart --profile -d DEVICE
///
/// The question is not "does typing feel slow" but "which half of the frame
/// does it, and does that cost grow with the amount of text". It records
/// `FrameTiming.buildDuration` (UI thread: rebuild + layout + paint recording)
/// and `rasterDuration` separately and attributes each frame to the keystroke
/// whose wall-clock window contains it, so a software-rendered emulator can
/// still give a usable build-side reading.
///
/// Phases per field:
///   idle      no input at all, the floor cost of the page being alive
///   tap       tap the field, nothing typed (focus + IME attach)
///   plain     committed text replaced one character at a time
///   composing IME pre-edit (pinyin buffer) one key at a time, as a CJK IME sends
///   delete    committed text removed one character at a time
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late List<({int at, Duration build, Duration raster, Duration total})> raw;
  late List<({String phase, int index, int start, int end, int wallMs})> steps;

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    raw = [];
    steps = [];
  });

  tearDown(() async {
    await db.close();
  });

  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      raw.add((
        at: t.timestampInMicroseconds(FramePhase.buildStart),
        build: t.buildDuration,
        raster: t.rasterDuration,
        total: t.totalSpan,
      ));
    }
  }

  String stats(Iterable<Duration> values) {
    final ms = values.map((d) => d.inMicroseconds / 1000).toList()..sort();
    if (ms.isEmpty) return '{"n":0}';
    double pct(double p) => ms[(ms.length * p).floor().clamp(0, ms.length - 1)];
    return jsonEncode({
      'n': ms.length,
      'median': pct(0.5).toStringAsFixed(1),
      'p90': pct(0.9).toStringAsFixed(1),
      'max': ms.last.toStringAsFixed(1),
    });
  }

  Future<void> measure(
    String phase,
    int index,
    Future<void> Function() action,
  ) async {
    final start = DateTime.now().microsecondsSinceEpoch;
    final watch = Stopwatch()..start();
    await action();
    watch.stop();
    final end = DateTime.now().microsecondsSinceEpoch;
    steps.add((
      phase: phase,
      index: index,
      start: start,
      end: end,
      wallMs: watch.elapsedMilliseconds,
    ));
  }

  Duration buildFor(({int start, int end}) window) {
    var slowest = Duration.zero;
    for (final f in raw) {
      if (f.at < window.start || f.at > window.end) continue;
      if (f.build > slowest) slowest = f.build;
    }
    return slowest;
  }

  void report(String field) {
    final mine = steps.where((s) => s.phase.startsWith('$field:')).toList();
    if (mine.isEmpty) {
      debugPrint('PERF ${jsonEncode({'field': field, 'steps': 0})}');
      return;
    }
    for (final phase in ['idle', 'tap', 'plain', 'composing', 'delete']) {
      final phaseSteps = mine.where((s) => s.phase == '$field:$phase').toList();
      if (phaseSteps.isEmpty) continue;
      final builds = [for (final s in phaseSteps) buildFor((start: s.start, end: s.end))];
      final walls = [for (final s in phaseSteps) Duration(milliseconds: s.wallMs)];
      final window = {
        for (final s in phaseSteps) 'build_${s.index}': (buildFor((start: s.start, end: s.end)).inMicroseconds / 1000).toStringAsFixed(1),
      };
      debugPrint(
        'PERF ${jsonEncode({
          'field': field,
      'phase': phase,
          'build': jsonDecode(stats(builds)),
          'wall': jsonDecode(stats(walls)),
          'series': window,
        })}',
      );
    }
    final rasters = [
      for (final f in raw)
        if (mine.any((s) => f.at >= s.start && f.at <= s.end)) f.raster,
    ];
    debugPrint('PERF ${jsonEncode({'field': field, 'raster': jsonDecode(stats(rasters))})}');
    steps.removeWhere((s) => s.phase.startsWith('$field:'));
    raw.removeWhere((f) => mine.any((s) => f.at >= s.start && f.at <= s.end));
  }

  Future<void> settle(WidgetTester tester, {int ms = 1200}) async {
    final watch = Stopwatch()..start();
    while (watch.elapsedMilliseconds < ms) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> seed() async {
    final calendarId = await db
        .into(db.calendars)
        .insert(CalendarsCompanion.insert(name: 'Personal'));
    for (var i = 0; i < 60; i++) {
      await db.into(db.todos).insert(
        TodosCompanion.insert(
          calendarId: calendarId,
          summary: 'seeded task $i',
          dueDate: Value(DateTime(2026, 11, 14, 9)),
        ),
      );
    }
    for (var i = 0; i < 20; i++) {
      await db.into(db.events).insert(
        EventsCompanion.insert(
          calendarId: calendarId,
          summary: 'seeded event $i',
          startDt: DateTime(2026, 11, 14, 9 + (i % 8)),
          endDt: DateTime(2026, 11, 14, 10 + (i % 8)),
        ),
      );
    }
  }

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppRouter.router.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          homeWidgetAutoRefreshProvider.overrideWith((ref) {}),
          updateHomeWidgetProvider.overrideWith((ref) => () async {}),
        ],
        child: const DaySparkApp(),
      ),
    );
    await settle(tester, ms: 2500);
  }

  /// pinyin pre-edit as a CJK IME sends it: the composing range covers the
  /// latin buffer, the committed part in front is untouched.
  void imeEdit(WidgetTester tester, String committed, String buffer) {
    final text = '$committed$buffer';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: buffer.isEmpty
            ? TextRange.empty
            : TextRange(start: committed.length, end: text.length),
      ),
    );
  }

  Future<void> probeField(
    WidgetTester tester,
    Finder field, {
    required String name,
  }) async {
    if (field.evaluate().isEmpty) {
      debugPrint('PERF ${jsonEncode({'field': name, 'error': 'field not found'})}');
      return;
    }

    for (var i = 0; i < 3; i++) {
      await measure('$name:idle', i, () async {
        await tester.pump(const Duration(milliseconds: 16));
      });
    }

    await measure('$name:tap', 0, () async {
      await tester.tap(field);
      await tester.pump();
    });
    await settle(tester, ms: 800);

    var text = '';
    for (var i = 0; i < 30; i++) {
      text += '灵';
      await measure('$name:plain', i, () async {
        await tester.enterText(field, text);
        await tester.pump();
      });
    }
    await settle(tester, ms: 400);

    const pinyin = 'lingguangtianxieshenmedongxi';
    var committed = '';
    for (var i = 0; i < pinyin.length; i++) {
      final buffer = pinyin.substring(0, i + 1);
      await measure('$name:composing', i, () async {
        imeEdit(tester, committed, buffer);
        await tester.pump();
      });
    }
    // Commit the pre-edit, then delete it character by character.
    imeEdit(tester, '$committed灵光', '');
    await settle(tester, ms: 400);
    committed = '$text灵光';
    var current = committed;
    for (var i = 0; i < 30; i++) {
      current = current.substring(0, current.length - 1);
      final target = current;
      await measure('$name:delete', i, () async {
        imeEdit(tester, target, '');
        await tester.pump();
      });
    }
    await settle(tester, ms: 400);

    report(name);
  }

  testWidgets('input cost does not grow with text', (tester) async {
    binding.addTimingsCallback(onTimings);

    await seed();
    await launch(tester);

    await probeField(
      tester,
      find.byKey(const ValueKey('todo-quick-add')),
      name: 'quick-add',
    );

    AppRouter.router.go('/todo/new');
    await settle(tester, ms: 1500);
    await probeField(tester, find.byType(TextField).first, name: 'todo-form');

    AppRouter.router.go('/event/new');
    await settle(tester, ms: 1500);
    await probeField(tester, find.byType(TextField).first, name: 'event-form');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
