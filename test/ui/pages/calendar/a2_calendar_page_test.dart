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
    expect(find.textContaining('08:00'), findsNothing);

    // Day view prints the span, in local time.
    await tester.tap(find.byTooltip('Day'));
    await _settle(tester);
    expect(find.text('整理周会纪要并发群'), findsOneWidget);
    expect(find.textContaining('16:00 – 17:00'), findsOneWidget);
    expect(find.textContaining('08:00'), findsNothing);

    // Every view stays reachable from every other one.
    await tester.tap(find.byTooltip('Month'));
    await _settle(tester);
    expect(find.byTooltip('Week'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Day'));
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
    await tester.tap(find.byTooltip('Month'));
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
    await tester.tap(find.byTooltip('Month'));
    await _settle(tester);

    await tester.tap(find.byTooltip('Next page'));
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
    await tester.pumpWidget(
      _app(page, db: db, browse: DateTime(2026, 1, 31)),
    );
    await _settle(tester);
    await tester.tap(find.byTooltip('Month'));
    await _settle(tester);

    await tester.tap(find.byTooltip('Next page'));
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
    await tester.tap(find.byTooltip('Month'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('month-day-2026-11-15')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
