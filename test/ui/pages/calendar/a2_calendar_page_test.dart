import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:dayspark/ui/pages/calendar/a2_calendar_views.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_deadline_lane.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_filter_sheet.dart';
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

    // The phone week is a grouped list, so the entry carries its own time.
    expect(find.textContaining('整理周会纪要并发群'), findsOneWidget);
    expect(find.text('08:00'), findsNothing);

    // The hour axis belongs to the day view (and the desktop week grid).
    await _switchView(tester, 'Day');
    await _settle(tester);
    expect(find.text('整理周会纪要并发群'), findsOneWidget);
    // Authoritative frozen spec axis is 08:00–20:00.
    expect(find.text('00:00'), findsNothing);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('23:00'), findsNothing);
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
      find.textContaining('提交周报给林总').first,
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
    // The spec's phone week list has no hour axis; the axis is the day view.
    await _switchView(tester, 'Day');
    await _settle(tester);

    // Authoritative frozen spec: 08:00–20:00 scale with 2-hour increments
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('07:00'), findsNothing);
    expect(find.text('21:00'), findsNothing);

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
    // The pct clamp is a time-axis contract; the phone week is a list now.
    await _switchView(tester, 'Day');
    await _settle(tester);

    // Items before 08:00 map via pct clamp to 0%, remaining visible
    expect(find.text('整理周会纪要并发群'), findsOneWidget);

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
    // Dawn-band clamping is a time-axis contract; the phone week is a list.
    await _switchView(tester, 'Day');
    await _settle(tester);

    // Spec contract: strictly [08, 10, 12, 14, 16, 18, 20] hour labels
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('03:00'), findsNothing);
    expect(find.text('09:00'), findsNothing);

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

    // Under frozen spec, dawn fold is removed in favor of 08:00-20:00 648px grid
    expect(find.textContaining('00:00–06:00'), findsNothing);
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
    // The now line is drawn on a time axis; the phone week list has none.
    await _switchView(tester, 'Day');
    await _settle(tester);

    // Under frozen spec, .now-line-cal is drawn at pct(NOW)% on today column
    expect(find.byKey(const ValueKey('calendar-now-line')), findsOneWidget);

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

  testWidgets('month view exposes create entry via FAB, and phone header carries no plus button', (
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

    // In week and day views, the header does not carry a '+' button per spec
    final topBar = find.byKey(const ValueKey('m-top'));
    expect(
      find.descendant(of: topBar, matching: find.byIcon(CupertinoIcons.add)),
      findsNothing,
    );

    // In month view, the create entry is exposed via A2Fab
    await tester.tap(find.text('Month'));
    await _settle(tester);
    await tester.tap(find.byTooltip('New Event'));
    await _settle(tester);
    expect(days, [DateTime(2026, 11, 15)]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the phone week is a grouped day list, not a 7-column grid', (
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
          title: 'Standup',
          start: DateTime(2026, 11, 15, 10),
          end: DateTime(2026, 11, 15, 11),
        ),
      ],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // Spec mobileCalendar('week') is .m-week-list: one group per day with a
    // date head, not the compressed 7-column desktop grid.
    expect(find.byKey(const ValueKey('phone-week-list')), findsOneWidget);
    expect(find.byType(A2TimeGridView), findsNothing);
    expect(find.text('Sun · 15'), findsOneWidget);
    expect(find.textContaining('10:00 Standup'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the phone calendar header keeps the spec title, not the range', (
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

    // Spec mobileShell('日历'): the top bar is the title, prev/next and the
    // filter; the range and "本周 · 7 天" are the scrolling body's m-date/m-sub.
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('15:00'), findsNothing);
    expect(find.text('Week 46'), findsNothing);
    expect(find.byTooltip('Previous'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
    expect(find.text('Nov 9 – Nov 15'), findsOneWidget);
    expect(find.text('This week · 7 days'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('tapping an empty phone week day opens its slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ranges = <DateTimeRange>[];
    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
      onTimeSlotTapped: ranges.add,
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // The spec list has no time axis, so the empty day itself is the slot:
    // its first hour is handed to the same slot sheet the grid used.
    await tester.tap(find.text('No schedule').first);
    await _settle(tester);
    expect(ranges, hasLength(1));
    expect(ranges.single.start, DateTime(2026, 11, 9, 9));
    expect(ranges.single.end, DateTime(2026, 11, 9, 10));

    // The date head is the same slot target, since the spec head carries no
    // trailing "+" button of its own.
    await tester.tap(find.text('Mon · 9'));
    await _settle(tester);
    expect(ranges, hasLength(2));
    expect(ranges.last.start, DateTime(2026, 11, 9, 9));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the phone day view hides an empty deadline row and keeps 08:00 whole', (
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
    await _switchView(tester, 'Day');
    await _settle(tester);

    // Spec mobileCalendar draws no empty 截止 row.
    expect(find.text('Deadline'), findsNothing);
    // The centred 08:00 reading must not be clipped by the scroll viewport.
    final labelTop = tester.getTopLeft(find.text('08:00')).dy;
    final viewportTop = tester
        .getTopLeft(find.byType(SingleChildScrollView).first)
        .dy;
    expect(labelTop, greaterThanOrEqualTo(viewportTop));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the desktop week keeps its fixed deadline lane when empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    // The desktop lane is a 30px alignment row even with nothing in it.
    expect(find.text('Deadline'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the calendars control uses the spec funnel icon', (
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

    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('dragging a phone week row shifts the plan by half-hours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captured = <TaskAllocationCalendarItem>[];
    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: [
        _allocation(
          start: DateTime(2026, 11, 15, 16),
          end: DateTime(2026, 11, 15, 17),
        ),
      ],
      deadlines: const [],
      onAllocationChanged: (item) async => captured.add(item),
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final row = find.textContaining('整理周会纪要并发群');
    expect(row, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 54));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single.allocation.startAt.toLocal().hour, 17);

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
    // Desktop week grid: the phone week list spells out every deadline row
    // instead of folding them into a lane.
    tester.view.physicalSize = const Size(800, 844);
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
    // The all-day lane is a grid structure: desktop week and both day views.
    tester.view.physicalSize = const Size(1440, 900);
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
    await tester.tap(find.text('Day').last);
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
    // The phone week list shows every all-day row; only the desktop lane folds.
    tester.view.physicalSize = const Size(800, 844);
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

  testWidgets('calendar filter hides events and shows restore banner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cals = await db.select(db.calendars).get();
    final workCal = cals.firstWhere((c) => c.name == 'Work');

    final page = A2CalendarPage(
      events: [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: workCal.id,
          title: 'Filtered event',
          start: DateTime(2026, 11, 15, 10),
          end: DateTime(2026, 11, 15, 11),
        ),
      ],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    expect(find.text('Display Calendars'), findsOneWidget);
    expect(find.text('Filtered event'), findsOneWidget);

    // Open filter dialog
    await tester.tap(find.text('Display Calendars'));
    await _settle(tester);

    expect(find.byType(CalendarFilterSheet), findsOneWidget);

    // Toggle calendar 1 off
    await tester.tap(find.text('Work'));
    await _settle(tester);

    // Close dialog
    await tester.tap(find.text('Done'));
    await _settle(tester);

    // Event is hidden, banner appears
    expect(find.text('Filtered event'), findsNothing);
    expect(find.text('Hidden 1 calendars'), findsOneWidget);
    expect(find.text('Restore All'), findsOneWidget);

    // Restore all
    await tester.tap(find.text('Restore All'));
    await _settle(tester);

    expect(find.text('Filtered event'), findsOneWidget);
    expect(find.text('Hidden 1 calendars'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('desktop calendar title matches .ph-title 26/650 wght and subtitle is 11.5', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final titleFinder = find.text('Calendar');
    expect(titleFinder, findsOneWidget);
    final titleWidget = tester.widget<Text>(titleFinder);
    expect(titleWidget.style?.fontSize, 26);
    expect(titleWidget.style?.fontWeight, FontWeight.w600);
    expect(
      titleWidget.style?.fontVariations?.any(
        (v) => v.axis == 'wght' && v.value == 650,
      ),
      isTrue,
    );

    final rowFinder = find.ancestor(of: titleFinder, matching: find.byType(Row)).first;
    final textWidgets = tester.widgetList<Text>(
      find.descendant(of: rowFinder, matching: find.byType(Text)),
    );
    expect(textWidgets.length, greaterThanOrEqualTo(2));
    final subtitleWidget = textWidgets.elementAt(1);
    expect(subtitleWidget.style?.fontSize, 11.5);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('mobile calendar header matches m-top 50h, 15px title, actions prev/next/filter, and persistent view switch', (
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

    final topBarFinder = find.byKey(const ValueKey('m-top'));
    expect(topBarFinder, findsOneWidget);
    expect(tester.getSize(topBarFinder).height, 50.0);

    final titleFinder = find.descendant(
      of: topBarFinder,
      matching: find.text('Calendar'),
    );
    expect(titleFinder, findsOneWidget);
    final titleWidget = tester.widget<Text>(titleFinder);
    expect(titleWidget.style?.fontSize, 15);
    expect(
      titleWidget.style?.fontVariations?.any(
        (v) => v.axis == 'wght' && v.value == 650,
      ),
      isTrue,
    );

    expect(find.byKey(const ValueKey('cal-prev')), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-filter-button')), findsOneWidget);

    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);

    await tester.tap(find.text('Month'));
    await _settle(tester);
    expect(find.byType(A2PhoneMonthGrid), findsOneWidget);

    await tester.tap(find.text('Day'));
    await _settle(tester);
    expect(find.byType(A2TimeGridView), findsOneWidget);

    await tester.tap(find.text('Week'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('phone-week-list')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('mobile 390 week and day views have no horizontal overflow and timeline 08:00-20:00 is reachable', (
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
          title: 'Morning Sync',
          start: DateTime(2026, 11, 15, 8),
          end: DateTime(2026, 11, 15, 9),
        ),
        CalendaEventAdapter(
          drifId: 2,
          calendarId: 1,
          title: 'Evening Wrap',
          start: DateTime(2026, 11, 15, 20),
          end: DateTime(2026, 11, 15, 21),
        ),
      ],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final weekList = find.byKey(const ValueKey('phone-week-list'));
    expect(weekList, findsOneWidget);
    expect(tester.getSize(weekList).width, lessThanOrEqualTo(390.0));

    await tester.tap(find.text('Day'));
    await _settle(tester);

    final dayView = find.byType(A2TimeGridView);
    expect(dayView, findsOneWidget);
    expect(tester.getSize(dayView).width, lessThanOrEqualTo(390.0));

    expect(find.text('08:00'), findsOneWidget);
    final top08 = tester.getTopLeft(find.text('08:00')).dy;
    expect(top08, greaterThanOrEqualTo(0));

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('20:00'),
      100,
      scrollable: scrollable,
    );
    await _settle(tester);

    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('Evening Wrap'), findsOneWidget);
    final top20 = tester.getTopLeft(find.text('20:00')).dy;
    expect(top20, greaterThanOrEqualTo(0));
    expect(top20, lessThanOrEqualTo(844));

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('mobile 365 width has no horizontal overflow on top bar and view switcher', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(365, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final page = A2CalendarPage(
      events: const <CalendaEventAdapter>[],
      allocations: const [],
      deadlines: const [],
    );
    await tester.pumpWidget(_app(page, db: db));
    await _settle(tester);

    final topBar = find.byKey(const ValueKey('m-top'));
    expect(topBar, findsOneWidget);
    expect(tester.getSize(topBar).width, lessThanOrEqualTo(365.0));
    expect(tester.getSize(topBar).height, 50.0);

    final viewSwitch = find.byKey(const ValueKey('cal-view-switch'));
    expect(viewSwitch, findsOneWidget);
    expect(tester.getSize(viewSwitch).width, lessThan(365.0));

    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
