import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/models/task_allocation_calendar_adapter.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/calendar/calendar_section.dart';
import 'package:dayspark/ui/widgets/calendar/marked_month_day_header.dart';

const _gridKey = ValueKey('calendar-time-grid');
const _monthKey = ValueKey('calendar-month-body');

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required List<CalendaEventAdapter> events,
  List<TaskAllocationCalendarAdapter> allocations = const [],
  void Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationTapped,
  Future<void> Function(TaskAllocationCalendarAdapter allocation)?
  onTaskAllocationChanged,
  void Function(DateTimeRange range)? onTimeSlotTapped,
  Future<void> Function(CalendaEventAdapter event)? onEventChanged,
  void Function(CalendaEventAdapter event)? onEventTapped,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        CalendarSection(
          events: events,
          allocations: allocations,
          onTaskAllocationTapped: onTaskAllocationTapped,
          onTaskAllocationChanged: onTaskAllocationChanged,
          onTimeSlotTapped: onTimeSlotTapped,
          onEventChanged: onEventChanged,
          onEventTapped: onEventTapped,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _longPressDrag(
  WidgetTester tester,
  String label, {
  Offset by = const Offset(0, 64),
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text(label).first),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveBy(by);
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

CalendaEventAdapter _timedEvent({
  required DateTime today,
  String title = 'Timed',
  String? rrule,
  bool isAllDay = false,
}) => CalendaEventAdapter(
  drifId: 1,
  calendarId: 10,
  title: title,
  start: today.add(const Duration(hours: 9)),
  end: today.add(const Duration(hours: 10)),
  rrule: rrule,
  isAllDay: isAllDay,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders header controls and view switcher', (tester) async {
    await _pumpCalendar(tester, events: []);

    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
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
      start: today.add(const Duration(hours: 10)),
      end: today.add(const Duration(hours: 11)),
    );

    await _pumpCalendar(
      tester,
      events: [],
      allocations: [allocation],
      onTaskAllocationTapped: (value) => tapped = value,
    );

    expect(find.text('Prepare slides'), findsWidgets);
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

      await _longPressDrag(tester, 'Move allocation');

      expect(changed, isNotNull);
      expect(changed!.id, allocation.id);
      expect(changed!.todoId, allocation.todoId);
      expect(changed!.start, isNot(allocation.start));
      expect(
        changed!.end.difference(changed!.start),
        const Duration(hours: 1),
      );
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

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: _app(
            CalendarSection(
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
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      await _longPressDrag(tester, 'Drag persistence');

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

  group('drag interaction', () {
    testWidgets('a recurring event cannot be dragged', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      CalendaEventAdapter? changed;
      final event = _timedEvent(
        today: today,
        title: 'Daily standup',
        rrule: 'RRULE:FREQ=DAILY;COUNT=5',
      );

      await _pumpCalendar(
        tester,
        events: [event],
        onEventChanged: (value) async => changed = value,
      );
      final before = tester.getRect(find.text('Daily standup').first);

      await _longPressDrag(tester, 'Daily standup');

      expect(
        changed,
        isNull,
        reason: 'a recurring instance must never reach the write path',
      );
      expect(
        tester.getRect(find.text('Daily standup').first),
        before,
        reason: 'a tile that stayed put must not look like it moved',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an all-day event cannot be dragged', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      CalendaEventAdapter? changed;
      final event = _timedEvent(
        today: today,
        title: 'Company holiday',
        isAllDay: true,
      );

      await _pumpCalendar(
        tester,
        events: [event],
        onEventChanged: (value) async => changed = value,
      );
      final before = tester.getRect(find.text('Company holiday').first);

      await _longPressDrag(
        tester,
        'Company holiday',
        by: const Offset(120, 0),
      );

      expect(changed, isNull);
      final after = tester.getRect(find.text('Company holiday').first);
      expect(after.center.dy, closeTo(before.center.dy, 1));
      expect(after.center.dx, closeTo(before.center.dx, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a plain event still drags to a new time', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      CalendaEventAdapter? changed;
      final event = _timedEvent(today: today, title: 'Movable');

      await _pumpCalendar(
        tester,
        events: [event],
        onEventChanged: (value) async => changed = value,
      );

      await _longPressDrag(tester, 'Movable');

      expect(changed, isNotNull);
      expect(changed!.drifId, event.drifId);
      expect(changed!.start, isNot(event.start));
      expect(changed!.rrule, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed event drag restores the tile and reports it', (
      tester,
    ) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final event = _timedEvent(today: today, title: 'Doomed move');

      await _pumpCalendar(
        tester,
        events: [event],
        onEventChanged: (_) async => throw StateError('save failed'),
      );
      final before = tester.getRect(find.text('Doomed move').first);

      await _longPressDrag(tester, 'Doomed move');

      expect(
        find.text('That didn\'t work. Please try again.'),
        findsWidgets,
      );
      expect(
        tester.getRect(find.text('Doomed move').first),
        before,
        reason: 'a rejected move must not stay on screen',
      );
      expect(find.text('09:00–10:00'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

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

      await _longPressDrag(tester, 'Failed move');

      expect(find.text('09:00–10:00'), findsWidgets);
      expect(
        find.text('That didn\'t work. Please try again.'),
        findsWidgets,
      );
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

    await tester.tap(find.byIcon(CupertinoIcons.chevron_right).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final grid = tester.getRect(find.byKey(_gridKey));
    await tester.tapAt(
      Offset(grid.left + 200, grid.top + 120),
    );
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
    expect(start.isUtc, isFalse);
    expect(
      DateTime.fromMillisecondsSinceEpoch(start.millisecondsSinceEpoch),
      start,
    );
  });

  testWidgets('a week slot tap prefills the time that was tapped', (
    tester,
  ) async {
    DateTimeRange? tapped;
    await _pumpCalendar(
      tester,
      events: [],
      onTimeSlotTapped: (range) => tapped = range,
    );

    final grid = tester.getRect(find.byKey(_gridKey));
    await tester.tapAt(
      Offset(grid.center.dx, grid.top + (14 - 8) * 56 + 4),
    );
    await tester.pump();

    expect(tapped, isNotNull);
    expect(tapped!.start.hour, 14);
    expect(tapped!.start.minute, 0);
    expect(tapped!.end.difference(tapped!.start), const Duration(hours: 1));
    expect(tapped!.start.isUtc, isFalse);
  });

  testWidgets('month view shows lunar markers and dims other months', (
    tester,
  ) async {
    await _pumpCalendar(tester, events: []);

    await tester.tap(find.text('Month'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(_monthKey), findsOneWidget);
    final headers = tester
        .widgetList<MarkedMonthDayHeader>(find.byType(MarkedMonthDayHeader))
        .toList();
    expect(headers, isNotEmpty);
    expect(headers.any((h) => h.dim), isTrue);
    expect(headers.any((h) => !h.dim), isTrue);
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
    CalendaEventAdapter build({bool isAllDay = false}) => CalendaEventAdapter(
      drifId: 88,
      calendarId: 10,
      title: 'Refresh fields',
      start: today.add(const Duration(hours: 9)),
      end: today.add(const Duration(hours: 10)),
      isAllDay: isAllDay,
    );

    await _pumpCalendar(tester, events: [build()]);
    expect(find.text('Refresh fields'), findsWidgets);

    await _pumpCalendar(tester, events: [build(isAllDay: true)]);
    expect(find.text('Refresh fields'), findsWidgets);
    expect(find.text('Refresh fields'), findsWidgets);
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

  testWidgets('day and week grids start at 08:00', (tester) async {
    await _pumpCalendar(tester, events: []);

    expect(find.text('08:00'), findsWidgets);
    expect(find.text('07:00'), findsNothing);

    await tester.tap(find.text('Day'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('08:00'), findsWidgets);
    expect(find.text('07:00'), findsNothing);
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
      findsWidgets,
    );
  });
}
