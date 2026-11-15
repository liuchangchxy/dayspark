import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/calendar/a2_calendar_page.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_shared.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

final _day = DateTime(2026, 11, 15);

Todo _todo(int id, int calendarId, String summary) => Todo(
  id: id,
  calendarId: calendarId,
  summary: summary,
  priority: 0,
  status: 'NEEDS-ACTION',
  dueDate: DateTime(2026, 11, 15, 18),
  sortOrder: 0,
  recurrenceRevision: 0,
  percentComplete: 0,
  createdAt: _day,
  updatedAt: _day,
  serverRev: 0,
);

TaskAllocationCalendarItem _allocation({
  required DateTime start,
  required DateTime end,
}) => TaskAllocationCalendarItem(
  allocation: TaskAllocation(
    id: 1,
    todoId: 1,
    // The writer stores allocation spans as UTC instants.
    startAt: start.toUtc(),
    endAt: end.toUtc(),
    state: 'active',
    createdAt: _day.toUtc(),
    updatedAt: _day.toUtc(),
    serverRev: 0,
  ),
  todo: _todo(1, 1, '整理周会纪要并发群'),
);

Widget _app(Widget page, {required AppDatabase db, DateTime? browse}) =>
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        calendarNowProvider.overrideWithValue(() => DateTime(2026, 11, 15, 15)),
        viewedDateProvider.overrideWith((ref) => browse ?? _day),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: page),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// The header names the three views in one menu instead of three icons, so a
/// test switches views the way a reader does: open the menu, pick the label.
Future<void> _switchView(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('calendar-view-menu')));
  await _settle(tester);
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'calendar_view_mode': 'week'});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            name: 'Work',
            color: const Value('#5F7183'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test('an allocation keeps its local day and its local clock', () {
    final adapter = TaskAllocationCalendarAdapter.fromItem(
      _allocation(
        start: DateTime(2026, 11, 15, 7),
        end: DateTime(2026, 11, 15, 8),
      ),
    );
    expect(adapter.start.hour, 7);
    expect(adapter.end.hour, 8);

    final blocks = calDayBlocks(
      day: _day,
      events: const <CalendaEventAdapter>[],
      allocations: [adapter],
    );
    expect(blocks, hasLength(1));
    expect(blocks.single.start.hour, 7);
  });

  testWidgets('the block prints the local span, not the stored UTC one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 16),
          end: DateTime(2026, 11, 15, 17),
        ),
      ],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // A week block carries only the title: the column already says when.
    expect(find.text('整理周会纪要并发群'), findsOneWidget);
    // The axis is a full day. With nothing in 00:00–06:00 that band folds to
    // one row, so 00:00 is gone but every drawn hour after it remains.
    expect(find.text('00:00'), findsNothing);
    expect(find.text('06:00'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);

    // Day view prints the span, in local time.
    await _switchView(tester, 'Day');
    await _settle(tester);
    expect(find.text('整理周会纪要并发群'), findsOneWidget);
    expect(find.textContaining('16:00 – 17:00'), findsOneWidget);

    // Every view stays reachable from every other one: the menu lists all
    // three whichever mode is current.
    await _switchView(tester, 'Month');
    await _settle(tester);
    expect(find.byKey(const ValueKey('calendar-view-menu')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a long deadline stays inside the lane', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: [
        CalendarDeadline(
          todoId: 7,
          title: '提交周报给林总（含下周排期与风险项，以及本季度招聘计划）',
          due: DateTime(2026, 11, 15, 18),
        ),
      ],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Day');
    await _settle(tester);

    expect(tester.takeException(), isNull);
    final text = tester.renderObject<RenderParagraph>(
      find.textContaining('提交周报给林总'),
    );
    expect(text.size.width, lessThanOrEqualTo(390));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the month "+" hands over a day, never an invented span', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final days = <DateTime>[];
    final ranges = <DateTimeRange>[];
    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
      onCreateAtDay: days.add,
      onTimeSlotTapped: ranges.add,
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Month');
    await _settle(tester);

    await tester.tap(find.byTooltip('New Event'));
    await _settle(tester);

    expect(days, hasLength(1));
    expect(days.single, DateTime(2026, 11, 15));
    // A month cell has no time axis: the "+" carries the day and no span, so
    // no slot-bound action can be taken from it.
    expect(ranges, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('paging the month keeps the browsed day-of-month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Month');
    await _settle(tester);

    await tester.tap(find.byTooltip('Next'));
    await _settle(tester);

    // Paging moves the month, not the day: the shared browse date keeps its
    // day-of-month, so Todo · By date still points where the user was.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );
    expect(container.read(viewedDateProvider), DateTime(2026, 12, 15));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('paging from a month-end clamps to the shorter month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db, browse: DateTime(2026, 1, 31)));
    await _settle(tester);
    await _switchView(tester, 'Month');
    await _settle(tester);

    await tester.tap(find.byTooltip('Next'));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );
    expect(container.read(viewedDateProvider), DateTime(2026, 2, 28));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the month grid marks the day an allocation falls on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 16),
          end: DateTime(2026, 11, 15, 17),
        ),
      ],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Month');
    await _settle(tester);

    expect(find.byKey(const ValueKey('month-day-2026-11-15')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('week and day views page by their own period', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );

    await tester.tap(find.byTooltip('Next'));
    await _settle(tester);
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 22));

    await _switchView(tester, 'Day');
    await _settle(tester);
    await tester.tap(find.byTooltip('Next'));
    await _settle(tester);
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 23));
    await tester.tap(find.byTooltip('Previous'));
    await _settle(tester);
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 22));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the time axis opens at 08:00', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    // 08:00 sits one folded dawn row below the top: the empty 00:00–06:00
    // band costs 28px, not 6 * 88.
    expect(scroll.controller!.offset, 28 + 2 * 88);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('an item before 08:00 pulls the viewport above itself', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 7),
          end: DateTime(2026, 11, 15, 8),
        ),
      ],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    // 07:00 is outside the folded band, so the band stays one row and the
    // viewport still opens at 06:00, the first drawn hour.
    expect(scroll.controller!.offset, 28);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('an item inside the dawn band keeps those hours drawn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 3),
          end: DateTime(2026, 11, 15, 4),
        ),
      ],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.controller!.offset, 2 * 88);
    expect(find.text('03:00'), findsOneWidget);
    expect(find.textContaining('00:00–06:00'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('an empty dawn band folds to one low-contrast row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    expect(find.textContaining('00:00–06:00'), findsOneWidget);
    expect(find.text('01:00'), findsNothing);
    expect(find.text('05:00'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a now-line scrolled past the top pins its clock reading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // Now is 15:00; the viewport opens at 08:00, so the line is still in
    // place and nothing is pinned over the axis.
    expect(find.byKey(const ValueKey('calendar-sticky-now')), findsNothing);

    final scrollable = find.byType(SingleChildScrollView);
    final controller = tester
        .widget<SingleChildScrollView>(scrollable)
        .controller!;
    // Scroll past 15:00: the line leaves the viewport, the clock stays.
    controller.jumpTo(28 + 10 * 88);
    await _settle(tester);

    expect(find.byKey(const ValueKey('calendar-sticky-now')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-sticky-now')),
        matching: find.text('15:00'),
      ),
      findsOneWidget,
    );
    // Within one screen of now, the jump-back key stays hidden.
    expect(find.byKey(const ValueKey('calendar-back-to-now')), findsNothing);

    // More than a screen away (here: the top of the axis, before dawn), the
    // key appears and the sticky reading hides because now is below again.
    controller.jumpTo(0);
    await _settle(tester);
    expect(find.byKey(const ValueKey('calendar-back-to-now')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-sticky-now')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a month day with content opens the day view', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 16),
          end: DateTime(2026, 11, 15, 17),
        ),
      ],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Month');
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(A2CalendarPage)),
    );

    await tester.tap(find.byKey(const ValueKey('month-day-2026-11-15')));
    await _settle(tester);
    expect(container.read(calendarViewModeProvider), CalendarViewMode.day);
    expect(find.textContaining('16:00 – 17:00'), findsOneWidget);

    // A day with nothing on it stays on the month grid.
    await _switchView(tester, 'Month');
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('month-day-2026-11-16')));
    await _settle(tester);
    expect(container.read(calendarViewModeProvider), CalendarViewMode.month);
    expect(container.read(viewedDateProvider), DateTime(2026, 11, 16));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('week and day views expose their own create entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final days = <DateTime>[];
    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
      onCreateAtDay: days.add,
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    await tester.tap(find.byTooltip('New Event'));
    await _settle(tester);
    expect(days, [DateTime(2026, 11, 15)]);

    await _switchView(tester, 'Day');
    await _settle(tester);
    await tester.tap(find.byTooltip('New Event'));
    await _settle(tester);
    expect(days.last, DateTime(2026, 11, 15));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a date-only deadline never shows a clock', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: [
        CalendarDeadline(todoId: 7, title: '提交周报', due: DateTime(2026, 11, 15)),
      ],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await _switchView(tester, 'Day');
    await _settle(tester);

    expect(find.textContaining('Deadline: Nov 15'), findsOneWidget);

    await _switchView(tester, 'Month');
    await _settle(tester);
    final cell = find.byKey(const ValueKey('month-day-2026-11-15'));
    expect(
      find.descendant(of: cell, matching: find.textContaining('00:00')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a date-only deadline chip carries no clock on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: [
        CalendarDeadline(todoId: 7, title: '提交周报', due: DateTime(2026, 11, 15)),
      ],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);
    await tester.tap(find.text('Month'));
    await _settle(tester);

    expect(find.text('Deadline'), findsOneWidget);
    expect(find.textContaining('00:00'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a full week deadline lane folds the overflow into +N', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: [
        CalendarDeadline(
          todoId: 1,
          title: 'A',
          due: DateTime(2026, 11, 15, 12),
        ),
        CalendarDeadline(
          todoId: 2,
          title: 'B',
          due: DateTime(2026, 11, 15, 18),
        ),
        CalendarDeadline(
          todoId: 3,
          title: 'C',
          due: DateTime(2026, 11, 15, 20),
        ),
      ],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    expect(find.text('+1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('an all-day event gets its own lane, not an hour block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tapped = <CalendaEventAdapter>[];
    final page = A2CalendarPage(
      events: [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 1,
          title: 'Company offsite',
          start: DateTime(2026, 11, 15),
          end: DateTime(2026, 11, 16),
          isAllDay: true,
        ),
      ],
      allocations: const [],
      deadlines: const [],
      onEventTapped: tapped.add,
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // The lane names itself and the chip sits in it.
    expect(find.text('All day'), findsOneWidget);
    expect(find.text('Company offsite'), findsOneWidget);

    await tester.tap(find.text('Company offsite'));
    await _settle(tester);
    expect(tapped.single.title, 'Company offsite');

    // The grid never draws it as an hour block: it is not inside the 24-hour
    // scroller at all, and it sits above the grid's viewport.
    expect(
      find.ancestor(
        of: find.text('Company offsite'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    final chipTop = tester.getTopLeft(find.text('Company offsite')).dy;
    final gridTop = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(chipTop, lessThan(gridTop));

    // Day view keeps the same lane, one column wide.
    await _switchView(tester, 'Day');
    await _settle(tester);
    expect(find.text('All day'), findsOneWidget);
    expect(find.text('Company offsite'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Company offsite'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('no all-day lane when every visible day has none', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 1,
          title: 'Timed review',
          start: DateTime(2026, 11, 15, 10),
          end: DateTime(2026, 11, 15, 11),
        ),
      ],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // Absent, not empty: the lane costs no height at all.
    expect(find.text('All day'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the week all-day lane folds a busy day into +N', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: [
        for (var i = 0; i < 3; i++)
          CalendaEventAdapter(
            drifId: i + 1,
            calendarId: 1,
            title: 'Day off $i',
            start: DateTime(2026, 11, 15),
            end: DateTime(2026, 11, 16),
            isAllDay: true,
          ),
      ],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // Same +N contract as the month cell and the deadline lane.
    expect(find.text('+1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
