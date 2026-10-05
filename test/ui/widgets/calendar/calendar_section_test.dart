import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:kalender/kalender.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/calendar/event_tile.dart';
import 'package:dayspark/ui/widgets/calendar/task_allocation_tile.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';
import 'package:dayspark/ui/widgets/calendar/view_switcher.dart';

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required List<CalendaEventAdapter> events,
  List<TaskAllocationCalendarAdapter> allocations = const [],
  void Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationTapped,
  Future<void> Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationChanged,
  void Function(DateTimeRange range)? onTimeSlotTapped,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CalendarSection(
            events: events,
            allocations: allocations,
            onTaskAllocationTapped: onTaskAllocationTapped,
            onTaskAllocationChanged: onTaskAllocationChanged,
            onTimeSlotTapped: onTimeSlotTapped,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders header controls and view switcher', (tester) async {
    await _pumpCalendar(tester, events: []);

    expect(find.byType(ViewSwitcher), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_left), findsWidgets);
    expect(find.byIcon(CupertinoIcons.chevron_right), findsWidgets);
  });

  testWidgets('renders a timed event tile', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpCalendar(
      tester,
      events: [
        CalendaEventAdapter(
          drifId: 1,
          calendarId: 10,
          title: 'Timed meeting',
          start: today.add(const Duration(hours: 10)),
          end: today.add(const Duration(hours: 11)),
        ),
      ],
    );

    expect(find.text('Timed meeting'), findsWidgets);
  });

  testWidgets('renders and opens a TaskAllocation tile', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    TaskAllocationCalendarAdapter? tapped;
    final allocation = TaskAllocationCalendarAdapter(
      id: 71,
      todoId: 19,
      todoTitle: 'Prepare slides',
      start: today.add(const Duration(hours: 10)).toUtc(),
      end: today.add(const Duration(hours: 11)).toUtc(),
    );

    await _pumpCalendar(
      tester,
      events: [],
      allocations: [allocation],
      onTaskAllocationTapped: (value) => tapped = value,
    );

    expect(find.text('Prepare slides'), findsWidgets);
    expect(find.text('10:00 – 11:00'), findsOneWidget);
    await tester.tap(find.text('Prepare slides').first);
    expect(tapped?.id, allocation.id);
  });

  testWidgets(
    'dragging an Allocation reports its original identity and new range',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      TaskAllocationCalendarAdapter? changed;
      final allocation = TaskAllocationCalendarAdapter(
        id: 72,
        todoId: 20,
        todoTitle: 'Move allocation',
        start: today.add(const Duration(hours: 9)),
        end: today.add(const Duration(hours: 10)),
      );
      await _pumpCalendar(
        tester,
        events: [],
        allocations: [allocation],
        onTaskAllocationChanged: (value) async => changed = value,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Move allocation').first),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 64));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      expect(changed, isNotNull);
      expect(changed!.id, allocation.id);
      expect(changed!.todoId, allocation.todoId);
      expect(changed!.start, isNot(allocation.start));
    },
  );

  testWidgets(
    'drag persists only Allocation time and preserves Todo and Event',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final calendarId = await db
          .into(db.calendars)
          .insert(CalendarsCompanion.insert(name: 'Calendar'));
      final todoId = await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              calendarId: calendarId,
              summary: 'Drag persistence',
              dueDate: Value(DateTime(2026, 10, 10, 17)),
              description: const Value('Todo details'),
              priority: const Value(3),
            ),
          );
      final eventId = await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              calendarId: calendarId,
              summary: 'Unrelated event',
              startDt: DateTime(2026, 10, 7, 12),
              endDt: DateTime(2026, 10, 7, 13),
            ),
          );
      final dayNow = DateTime.now();
      final today = DateTime(dayNow.year, dayNow.month, dayNow.day);
      final allocationId = await container.read(createTaskAllocationProvider)(
        todoId: todoId,
        startAt: today.add(const Duration(hours: 9)),
        endAt: today.add(const Duration(hours: 10)),
      );
      final todoBefore = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final eventBefore = await (db.select(
        db.events,
      )..where((row) => row.id.equals(eventId))).getSingle();
      final allocationBefore = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(allocationId))).getSingle();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CalendarSection(
                events: [
                  CalendaEventAdapter(
                    drifId: eventId,
                    calendarId: calendarId,
                    title: eventBefore.summary,
                    start: eventBefore.startDt,
                    end: eventBefore.endDt,
                  ),
                ],
                allocations: [
                  TaskAllocationCalendarAdapter(
                    id: allocationId,
                    todoId: todoId,
                    todoTitle: todoBefore.summary,
                    start: allocationBefore.startAt,
                    end: allocationBefore.endAt,
                  ),
                ],
                onTaskAllocationChanged: (allocation) =>
                    container.read(rescheduleTaskAllocationProvider)(
                      id: allocation.id,
                      startAt: allocation.start,
                      endAt: allocation.end,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Drag persistence').first),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 64));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final allocationAfter = await (db.select(
        db.taskAllocations,
      )..where((row) => row.id.equals(allocationId))).getSingle();
      final todoAfter = await (db.select(
        db.todos,
      )..where((row) => row.id.equals(todoId))).getSingle();
      final eventAfter = await (db.select(
        db.events,
      )..where((row) => row.id.equals(eventId))).getSingle();
      expect(allocationAfter.id, allocationBefore.id);
      expect(allocationAfter.startAt, isNot(allocationBefore.startAt));
      expect(
        allocationAfter.endAt.difference(allocationAfter.startAt),
        const Duration(hours: 1),
      );
      expect(
        todoAfter.dueDate!.millisecondsSinceEpoch,
        todoBefore.dueDate!.millisecondsSinceEpoch,
      );
      expect(todoAfter.summary, todoBefore.summary);
      expect(todoAfter.description, todoBefore.description);
      expect(todoAfter.priority, todoBefore.priority);
      expect(todoAfter.status, todoBefore.status);
      expect(eventAfter, eventBefore);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      container.dispose();
      await db.close();
    },
  );

  testWidgets('renders all-day event (all-day bar shows every event)', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpCalendar(
      tester,
      events: [
        CalendaEventAdapter(
          drifId: 2,
          calendarId: 10,
          title: 'All day one',
          start: today,
          end: today.add(const Duration(days: 1)),
          isAllDay: true,
        ),
        CalendaEventAdapter(
          drifId: 3,
          calendarId: 10,
          title: 'All day two',
          start: today,
          end: today.add(const Duration(days: 1)),
          isAllDay: true,
        ),
      ],
    );

    expect(find.text('All day one'), findsWidgets);
    expect(find.text('All day two'), findsWidgets);
  });

  testWidgets(
    'failed Allocation drag restores persisted projection and reports error',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final allocation = TaskAllocationCalendarAdapter(
        id: 73,
        todoId: 21,
        todoTitle: 'Failed move',
        start: today.add(const Duration(hours: 9)),
        end: today.add(const Duration(hours: 10)),
      );
      await _pumpCalendar(
        tester,
        events: [],
        allocations: [allocation],
        onTaskAllocationChanged: (_) async => throw StateError('save failed'),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Failed move').first),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 64));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tile = tester.widget<TaskAllocationTile>(
        find.byType(TaskAllocationTile).first,
      );
      expect(tile.allocation.start, allocation.start);
      expect(find.textContaining('save failed'), findsOneWidget);
    },
  );

  testWidgets('slot tap uses the viewed (navigated) week, not today', (
    tester,
  ) async {
    DateTimeRange? tapped;
    await _pumpCalendar(
      tester,
      events: [],
      onTimeSlotTapped: (range) => tapped = range,
    );

    await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tapAt(const Offset(400, 400));
    await tester.pump();

    expect(tapped, isNotNull);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final nextWeekEnd = nextWeekStart.add(const Duration(days: 7));
    final start = tapped!.start;
    expect(
      !start.isBefore(nextWeekStart) && start.isBefore(nextWeekEnd),
      isTrue,
      reason: 'slot tap must land in the viewed week, got $start',
    );
    expect(tapped!.end.difference(tapped!.start), const Duration(hours: 1));
    // Regression (C1): wall-clock, not fake-UTC — the router encodes
    // millisecondsSinceEpoch and decodes as local; a shifted value would
    // land hours off (or next day) in the create prefill.
    expect(start.isUtc, isFalse);
    expect(
      DateTime.fromMillisecondsSinceEpoch(start.millisecondsSinceEpoch),
      start,
    );
  });

  testWidgets('month view slot tap routes to event creation with a range', (
    tester,
  ) async {
    DateTimeRange? tapped;
    await _pumpCalendar(
      tester,
      events: [],
      onTimeSlotTapped: (range) => tapped = range,
    );

    await tester.tap(find.text('Month'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    // Tap inside the month grid body. Located from the rendered grid so the
    // point survives toolbar/layout changes instead of being a fixed pixel.
    final grid = find.byType(MonthBody);
    expect(grid, findsOneWidget);
    await tester.tapAt(tester.getCenter(grid));
    await tester.pump();

    expect(tapped, isNotNull);
    expect(tapped!.end.difference(tapped!.start), const Duration(hours: 1));
    expect(tapped!.start.isUtc, isFalse);
  });

  testWidgets('title-only event update refreshes rendered tiles', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    CalendaEventAdapter build(String title) => CalendaEventAdapter(
      drifId: 7,
      calendarId: 10,
      title: title,
      start: today.add(const Duration(hours: 9)),
      end: today.add(const Duration(hours: 10)),
    );

    await _pumpCalendar(tester, events: [build('First title')]);
    expect(find.text('First title'), findsWidgets);

    await _pumpCalendar(tester, events: [build('Second title')]);
    expect(find.text('Second title'), findsWidgets);
    expect(find.text('First title'), findsNothing);
  });

  testWidgets('event rendering fields refresh independently', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    CalendaEventAdapter build({
      Color? color,
      bool isAllDay = false,
      String? rrule,
    }) => CalendaEventAdapter(
      drifId: 88,
      calendarId: 10,
      title: 'Refresh fields',
      start: today.add(const Duration(hours: 9)),
      end: today.add(const Duration(hours: 10)),
      color: color,
      isAllDay: isAllDay,
      rrule: rrule,
    );

    await _pumpCalendar(tester, events: [build()]);
    await _pumpCalendar(
      tester,
      events: [build(color: const Color(0xFF123456))],
    );
    var tile = tester.widget<EventTile>(find.byType(EventTile).first);
    expect(tile.event.color, const Color(0xFF123456));

    await _pumpCalendar(tester, events: [build(isAllDay: true)]);
    tile = tester.widget<EventTile>(find.byType(EventTile).first);
    expect(tile.event.isAllDay, isTrue);

    await _pumpCalendar(tester, events: [build(rrule: 'FREQ=WEEKLY;BYDAY=WE')]);
    tile = tester.widget<EventTile>(find.byType(EventTile).first);
    expect(tile.event.rrule, 'FREQ=WEEKLY;BYDAY=WE');
  });

  testWidgets('zero-hour all-day event renders in the all-day area', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _pumpCalendar(
      tester,
      events: [
        CalendaEventAdapter(
          drifId: 8,
          calendarId: 10,
          title: 'Zero hour day',
          start: today,
          end: today,
          isAllDay: true,
        ),
      ],
    );

    expect(find.text('Zero hour day'), findsWidgets);
  });

  testWidgets('day and week views open scrolled to 08:00', (tester) async {
    await _pumpCalendar(tester, events: []);

    final weekConfig = tester.widget<CalendarView>(find.byType(CalendarView));
    expect(weekConfig.viewConfiguration, isA<MultiDayViewConfiguration>());
    expect(
      (weekConfig.viewConfiguration as MultiDayViewConfiguration)
          .initialTimeOfDay,
      const TimeOfDay(hour: 8, minute: 0),
    );

    await tester.tap(find.text('Day'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    final dayConfig = tester.widget<CalendarView>(find.byType(CalendarView));
    expect(
      (dayConfig.viewConfiguration as MultiDayViewConfiguration)
          .initialTimeOfDay,
      const TimeOfDay(hour: 8, minute: 0),
    );
  });

  testWidgets('multi-day body exposes empty-slot button semantics', (
    tester,
  ) async {
    await _pumpCalendar(tester, events: []);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label ==
                'Empty time slot, activate to create an event',
      ),
      findsOneWidget,
    );
  });

  testWidgets('month view dims out-of-month day headers', (tester) async {
    await _pumpCalendar(tester, events: []);

    await tester.tap(find.text('Month'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    final headers = tester
        .widgetList<MarkedMonthDayHeader>(find.byType(MarkedMonthDayHeader))
        .toList();
    expect(headers, isNotEmpty);
    expect(headers.any((h) => h.dim), isTrue);
    expect(headers.any((h) => !h.dim), isTrue);
  });
}
